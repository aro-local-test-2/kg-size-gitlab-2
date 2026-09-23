# frozen_string_literal: true

module API
  module Ai
    module DuoWorkflows
      class Workflows < ::API::Base
        include PaginationParams
        include APIGuard
        include ::API::Concerns::McpAccess

        HEADERS_TO_FORWARD_AS_GRPC_METADATA = %w[
          X-Gitlab-Language-Server-Version
          X-Gitlab-Client-Type
          Langsmith-Trace
          X-Gitlab-Client-Name
          X-Gitlab-Client-Version
          X-Gitlab-Tracking-Context
        ].freeze

        TRACE_MAX_RESPONSE_BYTESIZE = 25.megabytes

        # Channels exposed to non-owner readers of a pipeline-triggered workflow.
        # Other channels (e.g. conversation_history, handover) carry raw tool
        # outputs that may include secrets or repository contents and are only
        # returned to the workflow owner.
        TRACE_SAFE_CHANNELS = %w[ui_chat_log plan status].freeze

        RESOLVE_DEPENDENCY_BUMP_WORKFLOW_DEFINITION =
          ::DependencyManagement::SecurityUpdate::TriggerResolveDependencyBumpWorkflowWorker::WORKFLOW_DEFINITION

        WORKFLOW_EVENTS = {
          ::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker::WORKFLOW_DEFINITION =>
            'trigger_sast_vulnerability_fp_detection_workflow',
          ::Vulnerabilities::TriggerResolutionWorkflowWorker::WORKFLOW_DEFINITION =>
            'trigger_sast_vulnerability_resolution_workflow',
          ::Vulnerabilities::TriggerSecretDetectionFalsePositiveDetectionWorkflowWorker::WORKFLOW_DEFINITION =>
            'trigger_secret_detection_vulnerability_fp_detection_workflow',
          RESOLVE_DEPENDENCY_BUMP_WORKFLOW_DEFINITION =>
            'trigger_resolve_dependency_bump_workflow'
        }.freeze

        helpers ::API::Helpers::DuoWorkflowHelpers
        helpers Gitlab::InternalEventsTracking

        feature_category :duo_agent_platform
        urgency :low

        allow_access_with_scope :ai_workflows, if: ->(request) do
          workflows_base = Gitlab::Utils.append_path(
            Gitlab.config.gitlab.relative_url_root, '/api/v4/ai/duo_workflows/workflows/')

          if request.get?
            ws_path = Gitlab::Utils.append_path(
              Gitlab.config.gitlab.relative_url_root, '/api/v4/ai/duo_workflows/ws')
            trace_path_pattern = %r{\A#{Regexp.escape(workflows_base)}\d+/trace\.jsonl\z}

            request.path == ws_path || request.path.match?(trace_path_pattern)
          elsif request.post?
            request.path.match?(%r{\A#{Regexp.escape(workflows_base)}\d+/execute\z})
          else
            false
          end
        end

        # The `send_duo_session_input` MCP tool re-dispatches the MCP request to the resume
        # endpoint, so the mcp scope must be accepted here. Only the request method is reliable
        # at that point (the path is still /api/v4/mcp), hence the method-based concern rather
        # than a path check. Narrowing this to declared MCP routes is tracked in
        # gitlab-org/security/gitlab#1751.
        allow_mcp_access_create

        before do
          authenticate!
        end

        helpers do
          # Prefers the most specific (subgroup) namespace from namespace_id/header,
          # falling back to root_namespace_id. Use this when checking cascading
          # settings that subgroups can override.
          def find_most_specific_namespace
            subgroup_id = params[:namespace_id].presence ||
              headers['X-Gitlab-Namespace-Id'].presence

            if subgroup_id
              ns = find_namespace(subgroup_id)

              if ns.nil?
                Gitlab::AppLogger.warn(
                  message: 'Namespace not found, falling back to root namespace',
                  namespace_id: subgroup_id
                )
              elsif !Ability.allowed?(current_user, :read_group, ns, composite_identity_check: false)
                Gitlab::AppLogger.warn(
                  message: 'User lacks permission on namespace, falling back to root namespace',
                  namespace_id: subgroup_id
                )
              else
                return ns
              end
            end

            find_request_namespace
          end

          def most_specific_namespace_or_root(root_namespace)
            find_most_specific_namespace || root_namespace
          end

          def find_root_namespace!
            namespace_id = request_namespace_id

            # First find the namespace (returns nil if not found)
            namespace = namespace_id && find_namespace(namespace_id)
            return current_user.governing_namespace unless namespace

            # Then enforce authorization (raises 404 if no access)
            not_found!('Namespace') unless Ability.allowed?(
              current_user, :read_group, namespace, composite_identity_check: false)

            root_namespace = namespace.root_ancestor

            # Validate namespace is contextually relevant to prevent
            # unauthorized access to model settings from unrelated namespaces
            validate_namespace_context!(root_namespace)

            root_namespace
          end

          def validate_namespace_context!(namespace)
            # If working in a project context, namespace must be the project's root namespace
            if params[:project_id].presence
              project = find_project!(params[:project_id])
              forbidden!("Namespace does not match project context") unless namespace.id == project.root_namespace.id
            end

            # If working in a namespace context (without project), must match or be ancestor
            return unless params[:namespace_id].presence

            context_namespace = find_namespace(params[:namespace_id])
            not_found!('Namespace') unless Ability.allowed?(
              current_user, :read_group, context_namespace, composite_identity_check: false)

            return if namespace.id == context_namespace.root_ancestor.id

            forbidden!("Namespace does not match workflow context")
          end

          def find_feature_setting_name
            # This header is sent only from the Node Executor.
            feature_setting_name_from_header =
              headers['X-Gitlab-Agent-Platform-Feature-Setting-Name'].presence

            # We treat agentic chat as the default feature for the /ws endpoint if
            # no header is present.
            (feature_setting_name_from_header ||
              ::Ai::ModelSelection::FeaturesConfigurable.agentic_chat_feature_name).to_sym
          end

          def find_user_selected_model_identifier
            # Currently, only the web agentic chat UI sends this attribute, as a query param.
            # The IDE does not yet send this attribute.
            params[:user_selected_model_identifier].presence
          end

          def find_workflow!(id)
            workflow = ::Ai::DuoWorkflows::Workflow.for_user_with_id!(current_user.id, id)
            return workflow if current_user.can?(:read_duo_workflow, workflow)

            forbidden_if_identity_verification_required!(workflow.resource_parent)
            forbidden!
          end

          def get_current_organization_id
            Current.organization.id if Current.organization_assigned
          end

          def find_catalog_consumer_for_workflow!(workflow)
            catalog_item = workflow.ai_catalog_item_version&.item
            not_found!('AI Catalog item not found for this workflow') unless catalog_item

            consumer = ::Ai::Catalog::ItemConsumersFinder.new(current_user, params: {
              project_id: workflow.project.id,
              item_id: catalog_item.id,
              include_inherited: true
            }).execute.first

            not_found!('AI Catalog consumer not found for this workflow') unless consumer

            consumer
          end

          def gitlab_oauth_token(workflow_context_service = nil)
            workflow_context_service ||= workflow_context_generation_service

            # TODO: https://gitlab.com/gitlab-org/gitlab/-/issues/581556
            # It should be if find_feature_setting_name == FeaturesConfigurable.agentic_chat_feature_name
            oauth_token_result =
              if headers['X-Gitlab-Agent-Platform-Feature-Setting-Name'].present?
                workflow_context_service.generate_oauth_token_with_composite_identity_support
              else
                workflow_context_service.generate_oauth_token
              end

            if oauth_token_result.error?
              render_api_error!(oauth_token_result[:message], oauth_token_result[:http_status] || :forbidden)
            end

            oauth_token_result[:oauth_access_token]
          end

          def duo_workflow_token(container: nil)
            workflow_context_service = workflow_context_generation_service(container: container)
            workflow_token_result = workflow_context_service.generate_workflow_token
            bad_request!(workflow_token_result[:message]) if workflow_token_result.error?

            workflow_token_result
          end

          def duo_workflow_list_tools
            duo_workflow_list_tools_result = ::Ai::DuoWorkflow::DuoWorkflowService::Client.new(
              duo_workflow_service_url: Gitlab::DuoWorkflow::Client.url(user: current_user),
              current_user: current_user,
              secure: Gitlab::DuoWorkflow::Client.secure?(feature_setting: nil)
            ).list_tools
            bad_request!(duo_workflow_list_tools_result[:message]) if duo_workflow_list_tools_result[:status] == :error

            duo_workflow_list_tools_result
          end

          def build_messaging_callback_context(container)
            return if params[:callback_hook_id].blank?

            unless ::Gitlab::WebHooks::DuoFlowCallback.available?(container)
              bad_request!('callback_hook_id is not available for this namespace')
            end

            hook = ::Ai::DuoWorkflows::CallbackHooksFinder
              .new(container: container)
              .find_by_id(params[:callback_hook_id])

            unless hook
              bad_request!('callback_hook_id does not reference a webhook with Duo flow callbacks ' \
                'enabled in this project or its ancestor groups')
            end

            {
              'adapter' => ::Ai::Messaging::Adapters::Webhook.adapter_key,
              'hook_id' => hook.id,
              'client_reference' => params[:client_reference].presence
            }.compact
          end

          def create_workflow_params(container)
            wrkf_params = declared_params(include_missing: false).except(
              :start_workflow,
              :source_branch,
              :additional_context,
              :ai_catalog_item_consumer_id,
              :callback_hook_id,
              :client_reference
            )

            callback_context = build_messaging_callback_context(container)
            wrkf_params[:messaging_callback_context] = callback_context if callback_context

            if wrkf_params[:ai_catalog_item_version_id]
              wrkf_params[:ai_catalog_item_version] = ::Ai::Catalog::ItemVersion
                                                        .find(wrkf_params.delete(:ai_catalog_item_version_id))
            end

            if wrkf_params[:issue_id] && wrkf_params[:project_id]
              project = find_project!(wrkf_params[:project_id])
              wrkf_params[:issue] = project.issues.find_by_iid!(wrkf_params.delete(:issue_id))
            end

            if wrkf_params[:merge_request_id] && wrkf_params[:project_id]
              project = find_project!(wrkf_params[:project_id])
              wrkf_params[:merge_request] = project.merge_requests.find_by_iid!(wrkf_params.delete(:merge_request_id))
            end

            wrkf_params
          end

          def validate_flow_goal!(workflow_definition, container)
            result = ::Ai::Catalog::FoundationalFlow[workflow_definition]&.validate_goal(
              container: container, goal: params[:goal]
            )
            return unless result

            bad_request!(result.message) if result.error?

            params[:goal] = result.payload[:goal]
          end

          def track_event(consumer: nil, workflow: nil)
            workflow_definition = resolve_workflow_definition(consumer)
            return unless workflow_definition && WORKFLOW_EVENTS.key?(workflow_definition)

            if workflow_definition == RESOLVE_DEPENDENCY_BUMP_WORKFLOW_DEFINITION
              track_resolve_dependency_bump_event(workflow)
            else
              track_vulnerability_event(WORKFLOW_EVENTS[workflow_definition])
            end
          end

          def track_vulnerability_event(event_name)
            vulnerability = vulnerability_from_goal
            return unless vulnerability

            track_internal_event(
              event_name,
              project: vulnerability.project,
              additional_properties: {
                label: 'manual',
                value: vulnerability.id,
                property: vulnerability.severity
              }
            )
          end

          # Only use the project when the caller can read it and it's inside the namespace, so a foreign
          # or unreadable project_id can't sway governance.
          def request_project_within(namespace)
            project = find_project(params[:project_id].presence)
            return unless project && can?(current_user, :read_project, project)
            return unless namespace && project.root_ancestor.id == namespace.root_ancestor.id

            project
          end

          def track_resolve_dependency_bump_event(workflow)
            return unless workflow

            merge_request = workflow.merge_request

            track_internal_event(
              WORKFLOW_EVENTS[RESOLVE_DEPENDENCY_BUMP_WORKFLOW_DEFINITION],
              project: workflow.project,
              additional_properties: {
                label: 'manual',
                value: merge_request&.id,
                property: merge_request ? resolve_dependency_bump_iteration(merge_request).to_s : nil
              }.compact
            )
          end

          # Iteration = number of resolve_dependency_bump workflows that exist for
          # the MR, including the one just created. This mirrors the automatic
          # trigger, which reads the count before creating and adds one.
          def resolve_dependency_bump_iteration(merge_request)
            ::Ai::DuoWorkflows::Workflow
              .for_merge_request(merge_request)
              .with_workflow_definition(RESOLVE_DEPENDENCY_BUMP_WORKFLOW_DEFINITION)
              .count
          end

          def compute_server_capabilities(dws_capabilities:, namespace:)
            rails_capabilities = %w[job_trace_pagination tool_call_approval_source incremental_checkpoints]
            rails_capabilities << "advanced_search" if advanced_search_enabled?

            # The instance keeps only the slim header and the blobs, so the gateway
            # can stop sending channel_values (see Workflow#write_incremental_only?).
            if ::Ai::DuoWorkflows::Workflow.write_incremental_only_enabled_for?(namespace)
              rails_capabilities << "incremental_checkpoints_only"
            end

            # Filter DWS capabilities based on admin/namespace/project settings
            unless tool_approval_for_session_enabled?(namespace)
              dws_capabilities.delete('tool_call_approval')
              dws_capabilities.delete('tool_call_pattern_approval')
            end

            rails_capabilities << 'duo_auto_mode' if duo_auto_mode_enabled?(namespace)

            (rails_capabilities + dws_capabilities).uniq
          end

          def tool_approval_for_session_enabled?(namespace)
            ::Ai::DuoSettings::CascadingSettingResolver.enabled?(
              project: request_project_within(namespace),
              namespace: namespace,
              attribute: :tool_approval_for_session_enabled?
            )
          end

          # Mirrors `tool_approval_for_session_enabled?` above. The flag is keyed
          # on the root ancestor (like GovernanceSurface) so a percentage rollout
          # cannot disagree with the GraphQL `aiFlowsMetadata` path for the same scope.
          # Both compute_server_capabilities call sites forbid a nil namespace first,
          # so root_ancestor is always present here.
          def duo_auto_mode_enabled?(namespace)
            return false unless Feature.enabled?(:duo_auto_mode, namespace.root_ancestor)

            ::Ai::DuoSettings::CascadingSettingResolver.enabled?(
              project: request_project_within(namespace),
              namespace: namespace,
              attribute: :duo_auto_mode_enabled?
            )
          end

          def serialize_channel_entries(channel, value)
            if value.is_a?(Array)
              value.map do |item|
                entry = item.is_a?(Hash) ? item.merge('channel' => channel) : { 'channel' => channel, 'value' => item }
                "#{Gitlab::Json.dump(entry)}\n"
              end
            elsif value.is_a?(Hash) && value.values.any? { |v| v.is_a?(Array) && v.any? }
              value.flat_map do |sub_key, sub_value|
                serialize_channel_entries("#{channel}.#{sub_key}", sub_value)
              end
            else
              ["#{Gitlab::Json.dump({ 'channel' => channel, 'value' => value })}\n"]
            end
          end

          # The full p_duo_workflows_checkpoints table is being retired
          # (gitlab-org/gitlab#605653); behind the read flag, source the trace's
          # channel_values from the slim header + incremental blobs so this path
          # stops reading that table.
          def trace_channel_values(workflow, thread, read, channels:)
            return blob_trace_channel_values(workflow, thread, channels: channels) if use_blob_read?(workflow, read)

            # The flag-off path reads the compacted latest checkpoint row, which
            # cannot span threads, so the thread filter has nothing to act on.
            # rubocop:disable Gitlab/Ai/AvoidDirectCheckpointTableRead -- legacy flag-off branch, removed in https://gitlab.com/gitlab-org/gitlab/-/work_items/611971
            latest = workflow.checkpoints.latest
            # rubocop:enable Gitlab/Ai/AvoidDirectCheckpointTableRead
            latest&.checkpoint&.dig('channel_values') || {}
          end

          # `read` is an undeclared internal override, removed with the read flag:
          # it forces the read path past the flag gate. 'incremental' reads the
          # header and blobs; 'legacy' reads the checkpoints table; any other value
          # (including nil) falls through to the default flag gate. 'incremental'
          # still requires incremental_checkpoints_enabled: a workflow that never
          # wrote blobs has nothing to reconstruct, so it falls back to the legacy
          # path instead of returning an empty trace.
          def use_blob_read?(workflow, read)
            case read
            when 'incremental' then workflow.incremental_checkpoints_enabled?
            when 'legacy' then false
            else workflow.incremental_blob_gate.for_trace?
            end
          end

          # `thread`: absent -> full cross-thread trace (default); `latest` -> the
          # latest thread only; an integer -> that current_thread group only. A
          # value with no matching group (non-numeric, or numeric but out of the
          # current_thread column's int4 range) returns an empty trace instead of
          # querying, since the query itself would raise on an out-of-range integer.
          def blob_trace_channel_values(workflow, thread, channels:)
            case thread
            when nil, ''
              workflow.full_trace_channel_values(channels: channels)
            when 'latest'
              header = workflow.latest_checkpoint_header
              header ? workflow.reconstructed_channel_values(header, channels: channels) : {}
            else
              return {} unless thread.match?(/\A\d+\z/) && thread.to_i <= ::Gitlab::Database::MAX_INT_VALUE

              # Scoped to the top-level lineage, like #latest_checkpoint_header: a
              # nested subagent's header can share a current_thread id with the
              # workflow's own group, and only the workflow's own group is meant here.
              header = workflow.checkpoint_headers.for_checkpoint_ns(nil).for_current_thread(thread.to_i).last
              header ? workflow.reconstructed_channel_values(header, channels: channels) : {}
            end
          end

          def advanced_search_enabled?
            # advanced_search is a capability flag, not governance, so it uses the project directly.
            project = find_project(params[:project_id].presence)
            namespace_id = params[:root_namespace_id].presence ||
              params[:namespace_id].presence ||
              headers['X-Gitlab-Namespace-Id'].presence
            namespace = find_namespace(namespace_id)

            ::Gitlab::CurrentSettings.search_using_elasticsearch?(scope: project || namespace)
          end

          def duo_cli_request?
            headers['X-Gitlab-Client-Name'] == 'Duo CLI'
          end

          def mcp_dispatched_request?
            request.path == Gitlab::Utils.append_path(
              Gitlab.config.gitlab.relative_url_root, '/api/v4/mcp')
          end

          def duo_cli_disabled_by_admin?
            !::Ai::Setting.for_organization_read_only(::Current.organization).duo_cli_enabled
          end

          def audit_duo_cli_session_blocked
            audit_context = {
              name: 'duo_cli_session_blocked',
              author: current_user,
              scope: current_user,
              target: current_user,
              message: 'Duo CLI session was blocked because the administrator disabled Duo CLI'
            }

            ::Gitlab::Audit::Auditor.audit(audit_context)
          end

          # Resolves the request context, then delegates payload assembly to
          # ConnectionConfigService. The workflow is passed in because the WebSocket
          # handshake and :execute resolve it differently, and so is the definition:
          # :ws has no workflow to read it from until the client sends StartWorkflowRequest.
          def duo_workflow_connection_config(workflow:, workflow_definition: params[:workflow_definition])
            root_namespace = find_root_namespace!

            forbidden!("Missing default GitLab Duo namespace user preference") unless root_namespace

            forbidden_if_identity_verification_required!(root_namespace)

            most_specific_namespace = most_specific_namespace_or_root(root_namespace)

            push_feature_flags(root_namespace, feature_setting_name: find_feature_setting_name)

            ::Ai::DuoWorkflows::ConnectionConfigService.new(
              current_user,
              duo_workflow_gitlab_token(workflow_definition),
              root_namespace: root_namespace,
              namespace: most_specific_namespace,
              project: request_project_within(root_namespace),
              workflow: workflow,
              request_metadata: duo_workflow_request_metadata(workflow_definition),
              # dws_capabilities is empty here because the pre-authorization endpoints do not
              # fetch a DWS token. DWS-advertised capabilities flow through the access path.
              # See https://gitlab.com/gitlab-org/gitlab/-/work_items/592850 for a longer-term fix.
              server_capabilities: compute_server_capabilities(
                dws_capabilities: [],
                namespace: most_specific_namespace
              )
            ).execute
          end

          def duo_workflow_request_metadata(workflow_definition)
            ::Ai::DuoWorkflows::ConnectionConfigService::RequestMetadata.new(
              project_id: params[:project_id],
              namespace_id: params[:namespace_id],
              client_type: params[:client_type],
              organization_id: get_current_organization_id,
              feature_setting_name: find_feature_setting_name,
              user_selected_model_identifier: find_user_selected_model_identifier,
              workflow_definition: workflow_definition,
              ai_catalog_item_version_id: params[:ai_catalog_item_version_id],
              forwarded_grpc_metadata: duo_workflow_forwarded_grpc_metadata
            )
          end

          def duo_workflow_forwarded_grpc_metadata
            HEADERS_TO_FORWARD_AS_GRPC_METADATA.each_with_object({}) do |header, forwarded|
              header_value = headers[header]

              forwarded[header.downcase] = header_value if header_value.present?
            end
          end

          # Reuses the caller's bearer when it is already scoped for AI workflows,
          # otherwise mints a token for the flow.
          def duo_workflow_gitlab_token(workflow_definition)
            workflow_context_service = workflow_context_generation_service(
              workflow_definition: workflow_definition
            )

            if workflow_context_service.already_scoped_for_ai_workflows?(access_token)
              parsed_oauth_token
            else
              gitlab_oauth_token(workflow_context_service).plaintext_token
            end
          end

          # The request attributes duo_workflow_connection_config reads. The :ws
          # endpoint reads the same set but leaves it undeclared; declare it here so
          # the new endpoint gets Grape validation and API docs. workflow_definition and
          # environment are absent on purpose: both are read off the workflow record here.
          params :duo_workflow_connection_params do
            optional :project_id, type: String, limit: 255, desc: 'The ID or path of the workflow project',
              documentation: { example: '1' }
            optional :namespace_id, type: String, limit: 255, desc: 'The ID or path of the workflow namespace',
              documentation: { example: '1' }
            optional :root_namespace_id, type: String, limit: 255, desc: 'The ID of the root namespace',
              documentation: { example: '1' }
            optional :ai_catalog_item_version_id, type: Integer,
              desc: 'The ID of the AI Catalog ItemVersion that sourced the flow config used by the workflow.',
              documentation: { example: 1 }
            optional :client_type, type: String, limit: 255, desc: 'The type of client starting the session',
              documentation: { example: 'browser' }
            optional :user_selected_model_identifier, type: String, limit: 255,
              desc: 'Identifier of the model the user selected for this session',
              documentation: { example: 'claude_sonnet_4_5' }
          end

          params :workflow_params do
            optional :project_id, type: String, desc: 'The ID or path of the workflow project',
              documentation: { example: '1' }
            optional :namespace_id, type: String, desc: 'The ID or path of the workflow namespace',
              documentation: { example: '1' }
            optional :ai_catalog_item_consumer_id, type: Integer,
              desc: 'The ID of AI Catalog ItemConsumer that configures which catalog item to execute.',
              documentation: { example: 1 }
            optional :start_workflow, type: Boolean,
              desc: 'Optional parameter to start workflow in a CI pipeline.' \
                'This feature is currently in an experimental state.',
              documentation: { example: true }
            optional :goal, type: String, desc: 'Goal of the workflow',
              documentation: { example: 'Fix pipeline for merge request 1 in project 1' }
            optional :agent_privileges, type: [Integer], desc: 'The actions the agent is allowed to perform',
              documentation: { example: [1] }
            optional :pre_approved_agent_privileges, type: [Integer],
              desc: 'The actions the agent can perform without asking for approval',
              documentation: { example: [1] }
            optional :workflow_definition, type: String, desc: 'workflow type based on its capability',
              documentation: { example: 'software_developer' }
            optional :allow_agent_to_request_user, type: Boolean,
              desc: 'When this is enabled Duo Agent Platform may stop to ask the user questions before proceeding. ' \
                'When it is disabled Duo Agent Platform will always just run through the workflow without ever ' \
                'asking for user input. Defaults to true.',
              documentation: { example: true }
            optional :image, type: String, desc: 'Container image to use for running the workflow in CI pipeline.',
              documentation: { example: 'registry.gitlab.com/gitlab-org/duo-workflow/custom-image:latest' }
            optional :source_branch, type: String,
              desc: 'Source branch for the CI pipeline. Uses default branch when not specified.',
              documentation: { example: 'main' }
            optional :environment, type: String,
              values: ::Ai::DuoWorkflows::Workflow.environments.keys.map(&:to_s),
              desc: 'Environment for the workflow.',
              documentation: { example: 'web' }
            optional :ai_catalog_item_version_id, type: Integer,
              desc: 'The ID of AI Catalog ItemVersion that sourced flow config used by the workflow.',
              documentation: { example: 1 }
            optional :additional_context, type: Array,
              desc: 'Additional Context required by the Flow, in JSON format. Contains an array of context details, ' \
                'where each detail is a Hash with a minimum of "Category" and "Content" keys.',
              documentation: {
                example: '[{"Category": "agent_user_environment", "Content": "{\"merge_request_url\": ' \
                  '\"https://gitlab.com/project/-/merge_requests/1\"}", "Metadata": "{}"}]'
              } do
                requires :Category, type: String, desc: 'The category of the context detail'
                requires :Content, type: String, desc: 'The content type of the context detail'
              end
            optional :issue_id, type: Integer,
              desc: 'IID of the Issue noteable that the workflow is associated with.',
              documentation: { example: 123 }
            optional :merge_request_id, type: Integer,
              desc: 'IID of the MergeRequest noteable that the workflow is associated with.',
              documentation: { example: 123 }
            optional :source, type: String, desc: 'Where the session was triggered from',
              values: ::Ai::DuoWorkflows::Workflow::CLIENT_SOURCE_TYPES.keys.map(&:to_s),
              documentation: { example: 'merge_request_code_conflict' }
            optional :callback_hook_id, type: Integer,
              desc: 'ID of a webhook with GitLab Duo flow callbacks enabled. When provided, GitLab POSTs flow ' \
                'lifecycle events to that webhook so the client does not have to poll. The hook must belong ' \
                'to the project or namespace the flow runs in, or to one of its ancestor groups.',
              documentation: { example: 42 }
            optional :client_reference, type: String, limit: 255,
              desc: 'An opaque string echoed back in every callback payload, ' \
                'useful for correlating callbacks to the triggering request.',
              documentation: { example: 'autoflow-run-abc123' }
          end
        end

        namespace :ai do
          namespace :duo_workflows do
            resources :direct_access do
              desc 'Connection details for accessing Duo Agent Platform Service directly' do
                tags ['gitlab_duo_workflows']
                success code: 201
                failure [
                  { code: 401, message: 'Unauthorized' },
                  { code: 403, message: 'Forbidden' },
                  { code: 404, message: 'Not found' },
                  { code: 429, message: 'Too many requests' }
                ]
              end

              params do
                optional :workflow_definition, type: String, desc: 'workflow type based on its capability',
                  documentation: { example: 'software_developer' }
                optional :root_namespace_id, type: String, desc: 'the ID of the root namespace',
                  documentation: { example: '1' }
                optional :project_id, type: String, desc: 'The ID or path of the project',
                  documentation: { example: '1' }
              end

              route_setting :lifecycle, :experiment
              route_setting :authorization,
                permissions: :create_duo_workflow_direct_access_token,
                boundary_type: :user
              post do
                check_rate_limit!(:duo_workflow_direct_access, scope: current_user)

                root_namespace = find_root_namespace!

                forbidden_if_identity_verification_required!(root_namespace)

                quota_check_response = ::Ai::UsageQuotaService.new(
                  user: current_user,
                  namespace: root_namespace
                ).execute

                if quota_check_response.error?
                  message = case quota_check_response.reason
                            when :usage_quota_exceeded
                              "USAGE_QUOTA_EXCEEDED: #{quota_check_response.message}"
                            when :usage_billing_forbidden
                              "USAGE_BILLING_FORBIDDEN: #{quota_check_response.message}"
                            when :namespace_missing
                              ::Ai::FoundationalFlowMessages.namespace_missing_error(current_user)
                            else
                              quota_check_response.message
                            end

                  forbidden!(message)
                end

                oauth_token = gitlab_oauth_token
                governed_project = request_project_within(root_namespace)
                workflow_token = duo_workflow_token(container: governed_project || root_namespace)

                # Extract DWS capabilities from token response
                dws_capabilities = workflow_token[:capabilities] || []

                access = {
                  gitlab_rails: {
                    base_url: Gitlab.config.gitlab.url,
                    token: oauth_token.plaintext_token,
                    token_expires_at: oauth_token.expires_at
                  },
                  duo_workflow_service: {
                    base_url: Gitlab::DuoWorkflow::Client.url(user: current_user),
                    token: workflow_token[:token],
                    token_expires_at: workflow_token[:expires_at],
                    headers: Gitlab::AiGateway.public_headers(
                      user: current_user,
                      ai_feature_name: :duo_workflow,
                      unit_primitive_name: :duo_workflow_execute_workflow,
                      organization_id: get_current_organization_id,
                      namespace_id: find_most_specific_namespace&.id,
                      project_id: governed_project&.id,
                      governing_namespace_id: root_namespace&.id
                    ).transform_keys(&:downcase),
                    secure: Gitlab::DuoWorkflow::Client.secure?(feature_setting: nil)
                  },
                  workflow_metadata: Gitlab::DuoWorkflow::Client.metadata(current_user,
                    namespace: find_request_namespace || root_namespace,
                    project: governed_project),
                  server_capabilities: compute_server_capabilities(
                    dws_capabilities: dws_capabilities,
                    namespace: most_specific_namespace_or_root(root_namespace)
                  )
                }

                present access, with: Grape::Presenters::Presenter
              end
            end

            resources :list_tools do
              desc 'List Duo Agent Platform tools' do
                tags ['gitlab_duo_workflows']
                success code: 200
                failure [
                  { code: 401, message: 'Unauthorized' },
                  { code: 403, message: 'Forbidden' },
                  { code: 404, message: 'Not found' },
                  { code: 429, message: 'Too many requests' }
                ]
              end

              params do
                optional :workflow_definition, type: String, desc: 'workflow type based on its capability',
                  documentation: { example: 'software_developer' }
              end

              route_setting :lifecycle, :experiment
              route_setting :authorization,
                permissions: :read_duo_workflow_tool,
                boundary_type: :user
              get do
                check_rate_limit!(:duo_workflow_direct_access, scope: current_user)

                forbidden_if_identity_verification_required!(current_user.governing_namespace)

                result = duo_workflow_list_tools

                present(result.payload, with: Grape::Presenters::Presenter)
              end
            end

            desc 'Get Duo Workflows WebSocket connection details' do
              tags ['gitlab_duo_workflows']
              success code: 200
              failure [
                { code: 401, message: 'Unauthorized' },
                { code: 403, message: 'Forbidden' },
                { code: 404, message: 'Not found' }
              ]
            end
            params do
              optional :workflow_id, type: String,
                desc: 'The ID of an existing workflow. When provided and the workflow has a stored ' \
                  'model selection, that selection is reused to ensure provider stickiness.',
                documentation: { example: '1' }
            end
            route_setting :lifecycle, :experiment
            route_setting :authorization,
              permissions: :read_duo_workflow_websocket,
              boundary_type: :user
            get :ws do
              require_gitlab_workhorse!

              status :ok
              content_type Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE

              workflow = if params[:workflow_id].present?
                           ::Ai::DuoWorkflows::Workflow.for_user_with_id!(current_user.id, params[:workflow_id])
                         end

              { DuoWorkflow: duo_workflow_connection_config(workflow: workflow) }
            end

            namespace :workflows do
              namespace ':workflow_id' do
                desc 'Get workflow trace as JSONL' do
                  detail 'Returns the full trace of a workflow session as JSON Lines (JSONL). ' \
                    'Each line is a JSON object representing one checkpoint event in chronological order.'
                  tags ['gitlab_duo_workflows']
                  success code: 200
                  failure [
                    { code: 401, message: 'Unauthorized' },
                    { code: 403, message: 'Forbidden' },
                    { code: 404, message: 'Not found' }
                  ]
                end
                params do
                  requires :workflow_id, type: Integer, desc: 'The ID of the workflow',
                    documentation: { example: 1 }
                  optional :full, type: Boolean,
                    desc: 'Include internal channels (conversation history, handover, etc). ' \
                      'Restricted to the workflow owner; non-owners receive a 403.',
                    documentation: { example: false }
                  optional :thread, type: String,
                    desc: 'Which thread to return: omit for the full cross-thread trace (default), ' \
                      "'latest' for the latest thread only, or a current_thread id for that thread only. " \
                      'Only applies on the blob-read path.',
                    documentation: { example: 'latest' }
                  # `read` is an internal override read straight from params (see
                  # use_blob_read?). It is intentionally not declared here, so it
                  # stays out of the published API docs and no consumer depends on
                  # it before the read flag removes it (gitlab-org/gitlab#605653).
                end
                route_setting :lifecycle, :experiment
                route_setting :authorization,
                  permissions: :read_duo_workflow,
                  boundary_type: :user
                get 'trace.jsonl' do
                  full = params[:full].present?

                  workflow = if full
                               # for_user_with_id! scopes to current_user; a non-owner
                               # requesting full=true gets 404, mirroring the legacy behavior.
                               find_workflow!(params[:workflow_id])
                             else
                               found = ::Ai::DuoWorkflows::Workflow.find_by_id(params[:workflow_id])
                               not_found!('Workflow') unless found

                               # A 403 would confirm the session exists; other users'
                               # private sessions must be indistinguishable from unknown ids.
                               if found.private_messaging_session? && !found.invoked_by?(current_user)
                                 not_found!('Workflow')
                               end

                               forbidden_if_identity_verification_required!(found.resource_parent)

                               authorize!(:read_duo_workflow, found)

                               found
                             end

                  content_type 'application/x-ndjson'
                  env['api.format'] = :binary

                  lines = []

                  if workflow.goal.present?
                    lines << "#{Gitlab::Json.dump({ 'channel' => 'goal', 'value' => workflow.goal })}\n"
                  end

                  # channels: nil on the blob-read path fetches and decodes only the
                  # safe set up front for full: false, instead of loading every
                  # channel's full history and discarding the internal ones below.
                  channels = full ? nil : TRACE_SAFE_CHANNELS
                  channel_values = trace_channel_values(workflow, params[:thread], params[:read], channels: channels)
                  channel_values = channel_values.slice(*TRACE_SAFE_CHANNELS) unless full
                  lines += channel_values.flat_map { |channel, value| serialize_channel_entries(channel, value) }

                  body = lines.join
                  if body.bytesize > TRACE_MAX_RESPONSE_BYTESIZE
                    file_too_large!('Workflow trace exceeds maximum allowed size')
                  end

                  body
                end
              end

              desc 'Create a flow' do
                detail 'Creates and starts a flow.'
                tags ['gitlab_duo_workflows']
                success code: 200
                failure [
                  { code: 400, message: 'Validation failed' },
                  { code: 401, message: 'Unauthorized' },
                  { code: 403, message: '403 Forbidden' },
                  { code: 404, message: 'Not found' }
                ]
              end
              params do
                use :workflow_params
              end
              route_setting :lifecycle, :experiment
              route_setting :mcp, tool_name: :create_duo_workflow,
                params: ::Mcp::Tools::DuoWorkflows::StartDuoSessionService::ROUTE_PARAMS,
                annotations: { readOnlyHint: false, destructiveHint: false }, resource_name: 'project',
                aggregators: [::Mcp::Tools::DuoWorkflows::StartDuoSessionService]
              route_setting :authorization,
                permissions: :create_duo_workflow,
                boundary_type: :user
              post do
                if duo_cli_request? && duo_cli_disabled_by_admin?
                  audit_duo_cli_session_blocked
                  forbidden!('Duo CLI has been disabled by your administrator')
                end

                ::Gitlab::QueryLimiting.disable!(
                  'https://gitlab.com/gitlab-org/gitlab/-/issues/566195', new_threshold: 125
                )

                container = if params[:project_id]
                              find_project!(params[:project_id])
                            elsif params[:namespace_id]
                              find_namespace!(params[:namespace_id])
                            else
                              current_user.default_duo_namespace
                            end

                if container.nil?
                  bad_request!('No default namespace found. Please provide project_id or namespace_id, ' \
                    'or configure a default Duo namespace.')
                end

                forbidden!('Access to the container is not allowed') unless container_access_allowed?(container)

                forbidden_if_identity_verification_required!(container)

                if params[:ai_catalog_item_consumer_id]
                  unless container.is_a?(Project)
                    bad_request!('AI Catalog flows can only be executed in project context')
                  end

                  consumer = find_item_consumer!(params[:ai_catalog_item_consumer_id], container)

                  # Not resolve_workflow_definition: that is params-first, so a caller
                  # could bypass the guard by sending a different workflow_definition.
                  validate_flow_goal!(consumer.item&.foundational_flow_reference, container)

                  service_account = if consumer.project.present?
                                      consumer.parent_item_consumer&.service_account
                                    else
                                      consumer.service_account
                                    end

                  service_account = enforce_start_workflow_service_account(
                    service_account, container, consumer: consumer
                  )

                  flow_params = {
                    item_consumer: consumer,
                    service_account: service_account,
                    execute_workflow: params[:start_workflow].present?,
                    event_type: 'api_execution',
                    user_prompt: params[:goal],
                    source_branch: params[:source_branch],
                    additional_context: build_additional_context(consumer, params[:additional_context]),
                    issue_id: params[:issue_id],
                    merge_request_id: params[:merge_request_id],
                    messaging_callback_context: build_messaging_callback_context(container),
                    # Server-derived MCP attribution wins over the client-reported `source`.
                    source_type: mcp_dispatched_request? ? :mcp : params[:source]
                  }

                  result = ::Ai::Catalog::Flows::ExecuteService.new(
                    project: container,
                    current_user: current_user,
                    params: flow_params
                  ).execute

                  if result.error? && result.http_status == :unprocessable_entity
                    render_api_error!(result.message, :unprocessable_entity)
                  end

                  bad_request!(result.message) if result.error?

                  workflow = result.payload[:workflow]
                  workload_id = result.payload[:workload_id]

                  link_vulnerability_to_user_triggered_workflow(workflow)

                  track_event(consumer: consumer, workflow: workflow)

                  present workflow, with: ::API::Entities::Ai::DuoWorkflows::Workflow,
                    workload: { id: workload_id, message: result.message }
                else
                  validate_flow_goal!(params[:workflow_definition], container)

                  workflow_params = create_workflow_params(container)

                  execution = authorize_flow_execution!(
                    workflow_params, container,
                    caller_can_execute: true,
                    start_workflow: params[:start_workflow].present?,
                    item_consumer_id: params[:ai_catalog_item_consumer_id]
                  )

                  workflow_params[:service_account] = enforce_start_workflow_service_account(
                    workflow_params[:service_account], container
                  )

                  service = ::Ai::DuoWorkflows::CreateWorkflowService.new(
                    container: container, current_user: current_user, params: workflow_params,
                    execution: execution, privileges_from_client: true)

                  result = service.execute

                  forbidden!(result.message) if result.error? && result.http_status == :forbidden
                  not_found!(result.message) if result.error? && result.http_status == :not_found
                  if result.error? && result.http_status == :payment_required
                    forbidden!("session failed to start due to insufficient GitLab credits. " \
                      "Purchase more credits to continue.")
                  end

                  if result.error? && result.http_status == :unprocessable_entity
                    render_api_error!(result[:message], :unprocessable_entity)
                  end

                  bad_request!(result[:message]) if result[:status] == :error

                  link_vulnerability_to_user_triggered_workflow(result[:workflow])

                  push_ai_gateway_headers(scope: container,
                    subject: workflow_params[:service_account] || current_user)

                  if params[:start_workflow].present?
                    response = ::Ai::DuoWorkflows::StartWorkflowService.new(
                      workflow: result[:workflow],
                      params: start_workflow_params(result[:workflow].id, container: container,
                        service_account: workflow_params[:service_account],
                        workflow_definition: workflow_params[:workflow_definition])
                    ).execute

                    if response.error?
                      status_code = case response.reason
                                    when :unprocessable_entity
                                      :unprocessable_entity
                                    when :feature_unavailable, :invalid_service_account
                                      :forbidden
                                    when :workload_failure
                                      :unprocessable_entity
                                    else
                                      :internal_server_error
                                    end
                      render_api_error!(response.message, status_code)
                    else
                      workload_id = response.payload && response.payload[:workload_id]
                      message = response.message

                      track_event
                    end
                  end

                  present result[:workflow], with: ::API::Entities::Ai::DuoWorkflows::Workflow,
                    workload: { id: workload_id, message: message }
                end
              end

              desc 'List all agent privileges' do
                detail 'Lists all available agent privileges with their IDs, names, descriptions, and whether each ' \
                  'is enabled by default. This endpoint has no supported attributes.'
                tags ['gitlab_duo_workflows']
                success code: 200
                failure [
                  { code: 401, message: 'Unauthorized' }
                ]
              end
              route_setting :authorization,
                permissions: :read_duo_workflow_agent_privilege,
                boundary_type: :user
              get 'agent_privileges' do
                present ::Ai::DuoWorkflows::Workflow::AgentPrivileges,
                  with: ::API::Entities::Ai::DuoWorkflows::Workflow::AgentPrivileges
              end

              params do
                requires :workflow_id, type: String, desc: 'The ID of the workflow'
              end
              namespace ':workflow_id' do
                desc 'Request Duo Workflows server-side execution connection details' do
                  detail 'Workhorse pre-authorization endpoint. Returns the connection details Workhorse ' \
                    'needs to run the flow itself over gRPC and stream the actions it receives back to the ' \
                    'caller, for callers that cannot execute actions of their own. Requests must arrive ' \
                    'through Workhorse.'
                  tags ['gitlab_duo_workflows']
                  success code: 200
                  failure [
                    { code: 401, message: 'Unauthorized' },
                    { code: 403, message: 'Forbidden' },
                    { code: 404, message: 'Not found' },
                    { code: 429, message: 'Too many requests' }
                  ]
                end
                params do
                  requires :workflow_id, type: String, regexp: /\A\d+\z/,
                    desc: 'The ID of the workflow to execute',
                    documentation: { example: '1' }
                  use :duo_workflow_connection_params
                end
                route_setting :lifecycle, :experiment
                route_setting :authorization,
                  permissions: :read_duo_workflow_websocket,
                  boundary_type: :user
                post :execute do
                  require_gitlab_workhorse!

                  # Shares the limit with the other session bootstrap endpoints: every
                  # request here makes Workhorse hold a gRPC stream open for the whole run.
                  check_rate_limit!(:duo_workflow_direct_access, scope: current_user)

                  workflow = find_workflow!(params[:workflow_id])

                  # Workhorse takes the workflow ID from here rather than from the caller's
                  # request body, which it does not authorize. The definition comes off the
                  # record for the same reason: it selects the MCP tool set and the minted
                  # token's feature, so the body must not be able to swap in another flow's.
                  config = duo_workflow_connection_config(
                    workflow: workflow,
                    workflow_definition: workflow.workflow_definition
                  ).merge(WorkflowID: workflow.id.to_s)

                  status :ok
                  content_type Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE

                  { DuoWorkflow: config }
                end

                desc 'Resume a paused workflow' do
                  tags ['gitlab_duo_workflows']
                  success code: 201
                  failure [
                    { code: 400, message: 'Validation failed' },
                    { code: 401, message: 'Unauthorized' },
                    { code: 403, message: 'Forbidden' },
                    { code: 404, message: 'Not found' },
                    { code: 422, message: 'Unprocessable entity' }
                  ]
                end
                params do
                  requires :workflow_id, type: String, desc: 'The ID of the workflow to resume',
                    documentation: { example: '1' }
                  requires :human_approval, type: Boolean,
                    desc: 'Whether the human approves resuming the workflow',
                    documentation: { example: true }
                  optional :human_message, type: String,
                    desc: 'Optional message accompanying the human decision',
                    documentation: { example: 'Looks good, please proceed' },
                    limit: ::Mcp::Tools::DuoWorkflows::SendDuoSessionInputService::HUMAN_MESSAGE_MAX_LENGTH
                end
                # Exposed to MCP only through the `send_duo_session_input` aggregator, which owns the
                # model-facing description and input schema.
                route_setting :mcp, tool_name: :resume_duo_workflow,
                  params: [:workflow_id, :human_approval, :human_message],
                  annotations: { readOnlyHint: false, destructiveHint: false }, resource_name: 'workflow',
                  aggregators: [::Mcp::Tools::DuoWorkflows::SendDuoSessionInputService]
                route_setting :authorization, permissions: :resume_duo_workflow, boundary_type: :user
                post :resume do
                  workflow = find_workflow!(params[:workflow_id])
                  authorize!(:resume_duo_workflow, workflow)

                  container = workflow.project || workflow.namespace

                  push_ai_gateway_headers(scope: container,
                    subject: workflow.service_account || current_user)
                  consumer = find_catalog_consumer_for_workflow!(workflow)

                  flow_params = {
                    item_consumer: consumer,
                    service_account: consumer.active_service_account,
                    execute_workflow: true,
                    event_type: 'api_execution',
                    user_prompt: workflow.goal,
                    resume_context: {
                      existing_workflow: workflow,
                      human_approval: params[:human_approval],
                      human_message: params[:human_message]
                    }
                  }

                  result = ::Ai::Catalog::Flows::ExecuteService.new(
                    project: container,
                    current_user: current_user,
                    params: flow_params
                  ).execute

                  bad_request!(result.message) if result.error?

                  workload_id = result.payload[:workload_id]
                  message = result.message

                  present workflow, with: ::API::Entities::Ai::DuoWorkflows::Workflow,
                    workload: { id: workload_id, message: message }
                end

                desc 'Restart a failed or stopped workflow as a new session' do
                  detail 'Creates and starts a new session with the flow, goal, noteable, source, privileges ' \
                    'and trigger of the given workflow. The original workflow is not modified.'
                  tags ['gitlab_duo_workflows']
                  success code: 201
                  failure [
                    { code: 400, message: 'Validation failed' },
                    { code: 401, message: 'Unauthorized' },
                    { code: 403, message: 'Forbidden' },
                    { code: 404, message: 'Not found' },
                    { code: 409, message: 'Conflict' },
                    { code: 422, message: 'Unprocessable entity' }
                  ]
                end
                params do
                  requires :workflow_id, type: String, desc: 'The ID of the workflow to restart',
                    documentation: { example: '1' }
                end
                route_setting :authorization, permissions: :restart_duo_workflow, boundary_type: :user
                post :restart do
                  workflow = find_workflow!(params[:workflow_id])
                  authorize!(:restart_duo_workflow, workflow)
                  forbidden_if_identity_verification_required!(workflow.project)

                  push_ai_gateway_headers(scope: workflow.project || workflow.namespace,
                    subject: workflow.service_account || current_user)
                  consumer = find_catalog_consumer_for_workflow!(workflow)

                  result = ::Ai::DuoWorkflows::RestartWorkflowService.new(
                    workflow: workflow,
                    current_user: current_user,
                    item_consumer: consumer,
                    service_account: consumer.active_service_account
                  ).execute

                  if result.error?
                    case result.reason
                    when :forbidden then forbidden!(result.message)
                    when :conflict then conflict!(result.message)
                    else bad_request!(result.message)
                    end
                  end

                  present result.payload[:workflow], with: ::API::Entities::Ai::DuoWorkflows::Workflow,
                    workload: { id: result.payload[:workload_id], message: result.message }
                end
              end
            end
          end
        end
      end
    end
  end
end
