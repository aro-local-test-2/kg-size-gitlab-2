# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class StartWorkflowService
      include Gitlab::Utils::StrongMemoize

      # When updating this image version, ensure the Duo CLI e2e test image stays in sync:
      # https://gitlab.com/gitlab-org/editor-extensions/gitlab-lsp/-/blob/main/packages/cli/test/production-headless-e2e/docker/Dockerfile#L3
      IMAGE_PATH = "gitlab-org/duo-workflow/default-docker-image/workflow-generic-image:v0.0.16"
      DUO_CLI_VERSION = "9.21.0"
      DUO_CLI_PROJECT_ID = "46519181"
      DUO_CLI_INSTALL_DIR = "/usr/local/bin"
      DUO_CLI_REGISTRY_BASE_URL = "https://gitlab.com/api/v4/projects"
      # /tmp is within the sandbox allowWrite list, so this directory is writable by the agent.
      GIT_HOOKS_DIR = "/tmp/git-hooks"
      # Scheme, host and any non-default port, no path. Used for the helper's own
      # stdin check: git sends the host (not the path) in the credential request, so
      # the check must match on protocol+host only.
      def self.gitlab_origin
        uri = URI.parse(Gitlab.config.gitlab.url)
        origin = "#{uri.scheme}://#{uri.host}"
        origin += ":#{uri.port}" unless uri.port == uri.default_port

        origin
      end

      # Reads the token at invocation time, so it never lands in a URL or .git/config.
      #
      # The credential.<url>.helper key this is installed under is the real access
      # control; these checks are defence in depth. Were the instance URL ever blank the
      # key becomes credential..helper, which git treats as unscoped and offers to every
      # host. Protocol is checked with host so the same case cannot be downgraded to
      # http. Git sends the request on stdin, and it is matched per whole line because a
      # glob over the raw request would answer a host merely containing our own.
      #
      # An absent token prints nothing: git ignores a helper's exit status and accepts a
      # bare `password=` as an empty password, so declining to print is what stops it
      # sending oauth: with no secret and failing auth on every operation.
      def self.git_credential_helper
        '!f() { [ "$1" = get ] || exit 0; p=; h=; while IFS= read -r l; do ' \
          'case "$l" in protocol=*) p="${l#protocol=}";; host=*) h="${l#host=}";; esac; done; ' \
          "[ \"$p://$h\" = \"#{gitlab_origin}\" ] || exit 0; " \
          '[ -n "${GIT_PASSWORD}" ] || exit 1; ' \
          'echo "username=oauth"; echo "password=${GIT_PASSWORD}"; }; f'
      end

      def initialize(workflow:, params:)
        @workflow = workflow
        @current_user = workflow.user
        @service_account = params[:service_account]
        @params = params
      end

      def execute
        unless @workflow.project_level?
          return ServiceResponse.error(
            message: 'Only project-level workflow is supported',
            reason: :unprocessable_entity)
        end

        unless @current_user.can?(:execute_duo_workflow_in_ci, @workflow)
          return ServiceResponse.error(message: 'Can not execute workflow in CI',
            reason: :feature_unavailable)
        end

        if duo_config.config_present? && !duo_config.valid_format?
          config_file = ::Gitlab::DuoAgentPlatform::Config::CONFIG_FILE_NAME
          errors = duo_config.validation_errors.join('; ').first(2000)
          return ServiceResponse.error(
            message: "Invalid config file #{config_file} -> #{errors}",
            reason: :unprocessable_entity)
        end

        unless service_account.present?
          return ServiceResponse.error(
            message: 'Service account is required but was not provided.',
            reason: :invalid_service_account)
        end

        link_composite_identity

        branch_response = create_workload_branch
        unless branch_response.success?
          return ServiceResponse.error(message: branch_response.message, reason: branch_response.reason)
        end

        @ref = branch_response.payload[:ref]

        run_workload
      end

      private

      attr_reader :service_account

      # Derives the legacy DUO_WORKFLOW_DEFINITION env var from the explicit
      # routing components. Older CLI versions use this for flow routing;
      # newer ones use FLOW_CONFIG_ID + FLOW_CONFIG_SCHEMA_VERSION directly.
      #
      # Custom (non-foundational) flows have no flow_config_id; fall back to
      # the stable identity on the workflow record (e.g. 'ai_catalog_agent').
      def resolved_workflow_definition
        return @workflow.workflow_definition if @params[:flow_config_id].blank?

        "#{@params[:flow_config_id]}/#{@params[:flow_config_schema_version]}"
      end

      def run_workload
        service = ::Ci::Workloads::RunWorkloadService.new(
          project: project,
          current_user: service_account,
          source: :duo_workflow,
          workload_definition: workload_definition,
          ref: @ref,
          # `duo_workflow_definition:` uses the stable identity (@workflow.workflow_definition,
          # e.g. "developer/v1") - NOT the resolved routing value. This string is the key for:
          #   - Pipeline rate-limit exclusions (Gitlab::Ci::Pipeline::Chain::Limit::RateLimit)
          #   - Credits/billing (Ai::UsageQuotaService -> CustomersDot feature_qualified_name)
          #   - Analytics (`duo_workflow_workload_completed` event property)
          # Changing it on a feature-flag route-switch would silently affect all three.
          # Routing-derived value is used for DUO_WORKFLOW_DEFINITION env var below.
          duo_workflow_definition: @workflow.workflow_definition
        )
        response = service.execute

        if response.success?
          workload = response.payload
          workflow_workload = @workflow.workflows_workloads.create(project_id: project.id, workload_id: workload.id)
          unless workflow_workload.persisted?
            return ServiceResponse.error(
              message: workflow_workload.errors.full_messages.join(', '),
              reason: :workflow_workload_failure
            )
          end

          ServiceResponse.success(payload: { workload_id: workload.id })
        else
          ServiceResponse.error(message: response.message, reason: :workload_failure)
        end
      end

      def workload_definition
        ::Ci::Workloads::WorkloadDefinition.new do |d|
          d.image = @workflow.image.presence || configured_image || instance_image
          d.variables = variables
          d.id_tokens = duo_config.id_tokens
          d.commands = commands
          # Caches serve the setup script; skip when there is no coding environment to set up.
          d.cache = cache_configuration if cache_configuration.present? && !skip_coding_environment?
          d.tags = [::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG]
          # Forward report_artifacts from the foundational flow definition so the
          # CI job declares artifact reports (e.g. SAST).
          reports = @params[:report_artifacts]

          if reports.present? && !reports.is_a?(Hash)
            Gitlab::AppJsonLogger.warn(
              message: 'report_artifacts is not a Hash, ignoring',
              report_artifacts_class: reports.class.name,
              foundational_flow_reference: @params[:flow_config_id],
              workflow_id: @workflow&.id,
              project_id: @workflow&.project_id
            )
          end

          d.artifacts_reports = reports if reports.is_a?(Hash) && reports.present?
        end
      end

      def configured_image
        return unless project

        duo_config.default_image
      end

      def instance_image
        host = ci_template_registry_host

        # Return the host if it appears to be a full path to an image rather than
        # just a registry domain:
        return host if host.include?('/')

        "#{host}/#{IMAGE_PATH}"
      end

      def ci_template_registry_host
        Gitlab::CurrentSettings.duo_workflows_default_image_registry.presence || 'registry.gitlab.com'
      end

      def sandbox
        @sandbox ||= ::Gitlab::DuoWorkflow::Sandbox.new(
          current_user: @current_user,
          duo_workflow_service_url: duo_workflow_service_url,
          duo_config: duo_config,
          project: project,
          unmask_env_variables: unmask_env_variables
        )
      end

      def duo_config
        @duo_config ||= ::Gitlab::DuoAgentPlatform::Config.new(project)
      end

      def cache_configuration
        return unless project

        duo_config.cache_config
      end

      def id_tokens
        return {} unless project

        duo_config.id_tokens || {}
      end

      # A list of environment variables which should not be stripped from the
      # running agent execution environment.
      def unmask_env_variables
        base_variables.merge(git_environment_variables)
          .merge(token_variables)
          .merge(id_tokens)
          .keys
      end

      def setup_script_commands
        return [] unless project

        duo_config.setup_script || []
      end

      # Installs a commit-msg git hook that appends Duo session trailers to every
      # commit. The hook is placed in GIT_HOOKS_DIR (/tmp/git-hooks), which is
      # within the sandbox allowWrite list. core.hooksPath is set via GIT_CONFIG_*
      # environment variables so all git invocations pick it up automatically,
      # regardless of whether they use run_git_command or run_command.
      #
      # The hook is only installed when session tracking is enabled for the project.
      def git_hooks_setup_commands
        return [] unless project.project_setting.dap_session_tracking_enabled?

        duo_session_url = @workflow.web_url

        # --if-exists addIfDifferent makes the operation idempotent: trailers are
        # only appended when not already present, so re-runs and amends are safe.
        hook_lines = [
          "#!/bin/sh",
          # Run the pre-existing (framework) commit-msg hook first, if we saved one.
          # Preserve its ability to reject the commit by propagating a non-zero exit.
          %(if [ -x "#{GIT_HOOKS_DIR}/commit-msg.orig" ]; then "#{GIT_HOOKS_DIR}/commit-msg.orig" "$1" || exit $?; fi),
          "git interpret-trailers \\",
          "  --if-exists addIfDifferent \\",
          "  --trailer #{Shellwords.escape('Co-authored-by: GitLab Duo <duo@gitlab.com>')} \\",
          "  --trailer #{Shellwords.escape("Duo-Session: #{duo_session_url}")} \\",
          "  --in-place \"$1\""
        ]

        hook_content = Shellwords.escape(hook_lines.join("\n"))

        [
          %(mkdir -p #{GIT_HOOKS_DIR}),
          # If a commit-msg hook already exists (e.g. installed by lefthook during
          # setup_script), preserve it as commit-msg.orig so our hook can chain to it.
          %([ -f #{GIT_HOOKS_DIR}/commit-msg ] && ) +
            %(mv #{GIT_HOOKS_DIR}/commit-msg #{GIT_HOOKS_DIR}/commit-msg.orig || true),
          %(printf %s #{hook_content} > #{GIT_HOOKS_DIR}/commit-msg),
          %(chmod +x #{GIT_HOOKS_DIR}/commit-msg)
        ]
      end

      def coding_environment
        @coding_environment ||= ::Ai::Catalog::CodingEnvironment.resolve(
          workflow_definition: @workflow.workflow_definition,
          flow_config: @params[:flow_config]
        )
      end

      def skip_coding_environment?
        coding_environment == :none
      end

      def git_clone_variables
        return { GIT_STRATEGY: 'none' } if skip_coding_environment?

        { GIT_DEPTH: 0, GIT_LFS_SKIP_SMUDGE: 1 }.merge(
          unfiltered_clone? ? native_clone_variables : blobless_fetch_variables
        )
      end

      # Native `git clone` bootstraps from the Gitaly bundle URI, so only the delta
      # is fetched from Gitaly. GIT_FETCH_EXTRA_FLAGS is ignored on this path.
      def native_clone_variables
        {
          GIT_STRATEGY: 'clone',
          FF_USE_GIT_NATIVE_CLONE: 'true',
          GIT_CLONE_EXTRA_FLAGS: '--quiet'
        }
      end

      # GIT_FETCH_EXTRA_FLAGS replaces the runner's default `--prune --quiet`, so both
      # are restored: --quiet keeps ~28k per-ref lines out of the 4 MB job log and
      # --prune drops stale origin/* refs in reused build directories.
      def blobless_fetch_variables
        { GIT_FETCH_EXTRA_FLAGS: '--prune --quiet --filter=blob:none' }
      end

      def git_credential_helper?
        Feature.enabled?(:dap_git_credential_helper, project)
      end

      def unfiltered_clone?
        Feature.enabled?(:dap_unfiltered_clone, project)
      end

      def blob_none_filter
        '--filter=blob:none' unless unfiltered_clone?
      end

      def git_environment_variables
        vars = {
          GIT_TERMINAL_PROMPT: '0',
          GIT_CONFIG_NOSYSTEM: '1',
          GIT_AUTHOR_NAME: git_user_name(service_account),
          GIT_AUTHOR_EMAIL: git_user_email(service_account),
          GIT_COMMITTER_NAME: git_user_name(@current_user),
          GIT_COMMITTER_EMAIL: git_user_email(@current_user)
        }

        git_config = [
          ['safe.directory', '/builds/*'],
          ["url.#{Gitlab.config.gitlab.url}/.insteadOf", "git@#{URI.parse(Gitlab.config.gitlab.url).host}:"]
        ]

        if project.project_setting.dap_session_tracking_enabled?
          # Install a git hooks directory via GIT_CONFIG so that all git commands
          # (including those run via run_command / run_shell_command) pick up the
          # commit-msg hook that appends the session trailers.
          git_config << ['core.hooksPath', GIT_HOOKS_DIR]
        end

        if git_credential_helper?
          # Tells the runner not to embed CI_JOB_TOKEN in clone URLs or insteadOf rules,
          # leaving the origin URL credential-free for the helper installed below.
          vars[:FF_GIT_URLS_WITHOUT_TOKENS] = 'true'

          # Path-scoped keys match without useHttpPath, so using the full instance URL
          # (including any relative-URL path) narrows the scope: the OAuth token is only
          # offered to the GitLab instance path, not to unrelated applications on the
          # same host. gitlab_origin (scheme+host) is kept for the helper's stdin check
          # because git sends the host (not the path) in the credential request.
          helper_key = "credential.#{Gitlab.config.gitlab.url}.helper"

          # An empty value resets the helper list at this scope, and it has to come first:
          # the Runner installs its own CI_JOB_TOKEN helper at this same scope, GIT_CONFIG_*
          # pairs apply after all config files, and git stops at the first helper that
          # yields a password - so without this the job token wins, and it cannot push.
          git_config << [helper_key, '']

          # Scoped to the instance URL rather than the bare credential.helper key, so
          # the token is only offered to GitLab and the reset leaves other hosts alone.
          git_config << [helper_key, self.class.git_credential_helper]
        end

        # Authenticate proactively (first request, not after a 401). No-op on
        # git < 2.46, which silently ignores the key. Scoped to the GitLab host
        # so credentials are not sent proactively to other hosts (submodules,
        # LFS, bundle URIs) - matching the runner's FF_USE_GIT_PROACTIVE_AUTH.
        git_config << ["http.#{Gitlab.config.gitlab.url}.proactiveAuth", 'basic']

        git_config.each_with_index do |(key, value), index|
          vars[:"GIT_CONFIG_KEY_#{index}"] = key
          vars[:"GIT_CONFIG_VALUE_#{index}"] = value
        end

        vars.merge(GIT_CONFIG_COUNT: git_config.size.to_s)
      end

      def base_variables
        secure = Gitlab::DuoWorkflow::Client.secure?(feature_setting: feature_setting)

        base_variables = {
          DUO_WORKFLOW_ADDITIONAL_CONTEXT_CONTENT: serialized_flow_additional_context,
          DUO_WORKFLOW_BASE_PATH: './',
          DUO_WORKFLOW_DEFINITION: resolved_workflow_definition,
          DUO_WORKFLOW_FLOW_CONFIG: serialized_duo_flow_config,
          DUO_WORKFLOW_FLOW_CONFIG_ID: @params[:flow_config_id],
          DUO_WORKFLOW_FLOW_CONFIG_SCHEMA_VERSION: @params[:flow_config_schema_version],
          DUO_WORKFLOW_AGENTS: workspace_agents_json,
          DUO_WORKFLOW_FLOW_VERSION: @params[:flow_version],
          DUO_WORKFLOW_GOAL: workflow_goal,
          DUO_WORKFLOW_SOURCE_BRANCH: resolve_source_branch,
          DUO_WORKFLOW_WORKFLOW_ID: String(@workflow.id),
          DUO_WORKFLOW_SERVICE_SERVER: duo_workflow_service_url,
          DUO_WORKFLOW_SERVICE_REALM: ::CloudConnector.gitlab_realm,
          DUO_WORKFLOW_GLOBAL_USER_ID: Gitlab::GlobalAnonymousId.user_id(@current_user),
          DUO_WORKFLOW_INSTANCE_ID: Gitlab::GlobalAnonymousId.instance_id,
          DUO_WORKFLOW_INSECURE: secure ? 'false' : 'true',
          DUO_WORKFLOW_DEBUG: Gitlab::DuoWorkflow::Client.debug_mode? ? 'true' : 'false',
          LOG_LEVEL: 'debug',
          DUO_WORKFLOW_GIT_HTTP_BASE_URL: Gitlab.config.gitlab.url,
          DUO_WORKFLOW_GIT_HTTP_USER: "oauth",
          DUO_WORKFLOW_GIT_USER_EMAIL: git_user_email(@current_user),
          DUO_WORKFLOW_GIT_USER_NAME: git_user_name(@current_user),
          DUO_WORKFLOW_GIT_AUTHOR_EMAIL: git_user_email(service_account),
          DUO_WORKFLOW_GIT_AUTHOR_USER_NAME: git_user_name(service_account),
          DUO_WORKFLOW_METADATA: workflow_metadata,
          DUO_WORKFLOW_PROJECT_ID: project.id,
          DUO_WORKFLOW_NAMESPACE_ID: project.root_namespace.id,
          GITLAB_BASE_URL: Gitlab.config.gitlab.url,
          GITLAB_PROJECT_PATH: project.full_path,
          AGENT_PLATFORM_GITLAB_VERSION: Gitlab.version_info.to_s,
          AGENT_PLATFORM_MODEL_METADATA: agent_platform_model_metadata_json,
          AGENT_PLATFORM_FEATURE_SETTING_NAME: feature_setting_name,
          GITLAB_ENABLE_GLOBAL_SKILLS: 'true',
          DUO_SESSION_TRACKING_ENABLED: project.project_setting.dap_session_tracking_enabled?.to_s,
          # The Duo Workflow executor image pins a specific glab version,
          # so glab's post-command "update available" nudge isn't actionable
          # for users. Silence it to avoid agents relaying misleading hints.
          GLAB_CHECK_UPDATE: '0'
        }

        base_variables[:LANGSMITH_TRACE] = @params[:langsmith_trace] if @params[:langsmith_trace].present?

        base_variables
      end

      # Always sent, since the AI Gateway gates on dap_workspace_agents and ignores agents on flows that
      # don't bind them; the flag here only skips the repository reads. Memoized: base_variables runs twice.
      # https://gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/-/blob/c61ab3bdd2083c94bb2f15dd4efc3e1288617652/duo_workflow_service/agent_platform/v1/catalog/sources/base.py#L73
      # https://gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/-/merge_requests/6842
      def workspace_agents_json
        enabled = Feature.enabled?(:dap_workspace_agents, @current_user)
        agents = enabled ? ::Gitlab::DuoWorkflow::WorkspaceAgentsReader.new(project).agents : []

        ::Gitlab::Json.dump(agents)
      end
      strong_memoize_attr :workspace_agents_json

      def workflow_goal
        @params[:goal]
      end

      def token_variables
        {
          GITLAB_OAUTH_TOKEN: @params[:workflow_oauth_token],
          DUO_WORKFLOW_SERVICE_TOKEN: @params[:workflow_service_token],
          DUO_WORKFLOW_GIT_HTTP_PASSWORD: @params[:workflow_oauth_token],
          GITLAB_TOKEN: @params[:workflow_oauth_token],
          GIT_PASSWORD: @params[:workflow_oauth_token],
          # From glab 1.111.0, a token supplied via GITLAB_TOKEN is treated as a
          # PAT and sent as Private-Token unless the OAuth flag also comes from
          # the environment, which would 401 our OAuth token.
          GLAB_IS_OAUTH2: 'true'
        }
      end

      def variables
        git_clone_variables
          .merge(base_variables)
          .merge(token_variables)
          .merge(git_environment_variables)
          .merge(sandbox.environment_variables)
      end

      def commands
        sandbox.setup_sandbox_commands +
          coding_environment_commands +
          git_hooks_setup_commands +
          executor_commands
      end

      def coding_environment_commands
        return [] if skip_coding_environment?

        setup_script_commands +
          oauth_remote_commands +
          workspace_fixup_commands
      end

      def executor_commands
        workflow_echo_commands + set_up_executor_commands
      end

      def workspace_fixup_commands
        [
          'cd "$CI_PROJECT_DIR"',
          # `git clone --revision` writes no fetch refspec, so `git fetch origin` would
          # update no remote-tracking refs. Idempotent on the init+fetch path.
          'git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"',
          # The runner checks out a detached HEAD at the commit SHA; re-attach to a named branch.
          'git checkout -B "${DUO_WORKFLOW_SOURCE_BRANCH:-$CI_DEFAULT_BRANCH}"',
          fetch_default_branch_command
        ]
      end

      # Base-branch diffs and rebases need the remote-tracking ref.
      def fetch_default_branch_command
        [
          'git fetch --no-tags', blob_none_filter, 'origin',
          '"+refs/heads/${CI_DEFAULT_BRANCH}:refs/remotes/origin/${CI_DEFAULT_BRANCH}"',
          '|| true'
        ].compact.join(' ')
      end

      def workflow_echo_commands
        [
          %(echo $DUO_WORKFLOW_DEFINITION),
          %(echo $DUO_WORKFLOW_FLOW_CONFIG_ID),
          %(echo $DUO_WORKFLOW_FLOW_VERSION),
          goal_echo_command,
          %(echo $DUO_WORKFLOW_SOURCE_BRANCH),
          %(echo $DUO_WORKFLOW_FLOW_CONFIG),
          %(echo $DUO_WORKFLOW_FLOW_CONFIG_SCHEMA_VERSION),
          # NOTE: Do not echo $DUO_WORKFLOW_ADDITIONAL_CONTEXT_CONTENT. It can carry
          # sensitive payloads (e.g. the raw secret for the secrets_fp_detection flow,
          # or diffs/file contents for other flows) and the job trace is readable by
          # low-privilege/anonymous users. See gitlab-org/gitlab#602194.
          %(echo Starting Workflow #{@workflow.id})
        ].compact
      end

      # Overridden to nil on the resume path, where the goal can carry a
      # user's free-text reply rather than this class's templated one; see
      # ResumeWorkflowService.
      def goal_echo_command
        %(echo $DUO_WORKFLOW_GOAL)
      end

      # Point origin at an oauth URL so the runner's insteadOf rules (which inject the
      # CI job token) do not apply - they only match http://host, not http://user@host.
      #
      # Superseded by the credential.helper; kept for the flag-off path and deleted
      # with the flag.
      def oauth_remote_commands
        return [] if git_credential_helper?

        [
          "git remote set-url origin " \
            '"$(echo "${DUO_WORKFLOW_GIT_HTTP_BASE_URL}" | ' \
            "sed 's|://|://oauth:'\"${GIT_PASSWORD}\"'@|')/${GITLAB_PROJECT_PATH}.git\""
        ]
      end

      def set_up_executor_commands
        wrapped_commands = sandbox.wrap_command(executor_cli_command)

        cli_install_commands + glab_setup.commands + orbit_local_setup.commands + wrapped_commands
      end

      # Downloads the duo-cli binary for the runner OS and architecture from the
      # GitLab package registry, unless the image already ships `duo`.
      def cli_install_commands
        registry_url = "#{DUO_CLI_REGISTRY_BASE_URL}/#{DUO_CLI_PROJECT_ID}" \
          "/packages/generic/duo-cli/#{DUO_CLI_VERSION}/${BINARY}"

        binary_install_command = [
          "command -v duo > /dev/null 2>&1 && ",
          "echo \"duo-cli already present, skipping installation\" || ",
          "{ ",
          "OS=$(uname -s | tr '[:upper:]' '[:lower:]') && ",
          "ARCH=$(uname -m) && ",
          "case \"${ARCH}\" in x86_64|amd64) ARCH=x64 ;; arm64|aarch64) ARCH=arm64 ;; *) " \
            "echo \"Unsupported architecture: ${ARCH}\" && exit 1 ;; esac && ",
          "BINARY=\"duo-${OS}-${ARCH}\" && ",
          "DOWNLOAD_URL=\"#{registry_url}\" && ",
          "echo \"Downloading duo-cli #{DUO_CLI_VERSION} (${BINARY})...\" && ",
          "curl -fsSL \"${DOWNLOAD_URL}\" -o \"#{DUO_CLI_INSTALL_DIR}/duo\" && ",
          "chmod +x \"#{DUO_CLI_INSTALL_DIR}/duo\"; ",
          "} || exit 1"
        ].join

        [
          binary_install_command,
          %(which duo || echo "duo not in PATH"),
          %(duo --version || echo "duo version check failed")
        ]
      end

      def executor_cli_command
        %(duo run --existing-session-id #{@workflow.id} --connection-type websocket)
      end

      def glab_setup
        @glab_setup ||= ::Gitlab::DuoWorkflow::GlabSetup.new(current_user: @current_user)
      end

      def orbit_local_setup
        @orbit_local_setup ||= ::Gitlab::DuoWorkflow::OrbitLocalSetup.new(current_user: @current_user)
      end

      def workflow_metadata
        # TODO: This is temporary workaround to pass model selection via
        # metadata into node executor to address
        # https://gitlab.com/gitlab-org/editor-extensions/gitlab-lsp/-/issues/1767
        # it will be cleaned up by
        # https://gitlab.com/gitlab-org/editor-extensions/gitlab-lsp/-/issues/1630
        ::Gitlab::Json.dump(
          ::Gitlab::Json.safe_parse(@params[:workflow_metadata]).merge(
            'modelMetadata' => agent_platform_model_metadata_json
          )
        )
      end

      def duo_workflow_service_url
        Gitlab::DuoWorkflow::Client.url_for(
          feature_setting: feature_setting,
          user: @current_user
        )
      end

      def project
        @workflow.project
      end

      def feature_setting
        @params.fetch(:duo_agent_platform_feature_setting, nil)
      end

      def feature_setting_name
        # If no feature setting is provided, use the default workflow feature name,
        # which is :duo_agent_platform.

        # All workflows originating from CI should have a feature setting name set.
        # This is because the value of the feature_setting_name is sent as `AGENT_PLATFORM_FEATURE_SETTING_NAME`
        # to the Node Executor. Node executor then sends this value to the websockets endpoint as the header
        # `X-Gitlab-Agent-Platform-Feature-Setting-Name`.

        # We expect all non-chat workflows to have a feature setting name set. Consequently, if this header
        # does not exist, we treat that request as a chat request, so it is essential to have the fallback to
        # workflow_feature_name, just in case.
        (feature_setting&.feature || ::Ai::ModelSelection::FeaturesConfigurable.workflow_feature_name).to_s
      end

      def agent_platform_model_metadata_json
        response = ::Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata.new(
          feature_setting: feature_setting
        ).execute

        response.fetch(Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata::HEADER_KEY, nil)
      end

      def link_composite_identity
        identity = ::Gitlab::Auth::Identity.fabricate(service_account)
        identity.link!(@current_user, context: :permission_check) if identity&.composite?
      end

      def serialized_duo_flow_config
        return unless @params[:flow_config].present? && @params[:flow_config].is_a?(Hash)

        ::Gitlab::Json.dump(@params[:flow_config])
      end

      def serialized_flow_additional_context
        context = Ai::DuoWorkflows::BuildAdditionalContextService.new(
          standard_context_params: {
            project: project,
            current_user: @current_user,
            service_account: service_account,
            source_branch: @params.fetch(:source_branch, nil),
            session_url: @workflow.web_url,
            ref: @ref
          },
          trigger_params: {
            event_type: @params[:event_type],
            triggering_conversation: @params[:triggering_conversation]
          },
          additional_context: @params[:additional_context],
          resource: workflow_resource
        ).execute.payload[:context]

        ::Gitlab::Json.dump(context)
      end

      # pipeline_links: fix_pipeline; resource: code_review/workplan/etc; goal: vulnerability flows.
      def workflow_resource
        @workflow.pipeline_links.link_type_source.first&.pipeline ||
          @workflow.resource ||
          resolve_vulnerability_resource
      end

      def resolve_vulnerability_resource
        return unless ::Vulnerabilities::TriggeredWorkflow::WORKFLOW_DEFINITIONS_TO_NAMES
                        .key?(@workflow.workflow_definition)

        project.vulnerabilities.find_by_id(@params[:goal])
      end

      def git_user_email(user)
        return "" unless user.respond_to?(:commit_email_or_default)

        user.commit_email_or_default
      end

      def git_user_name(user)
        return "" unless user.respond_to?(:name)

        user.name
      end

      # Returns the source branch to use for the workflow. Falls back to the
      # project's default branch when the requested source branch is blank or no
      # longer exists (for example, a merged MR whose source branch was deleted).
      def resolve_source_branch
        source_branch = @params.fetch(:source_branch, nil)
        return project.default_branch_or_main if source_branch.blank?

        project.repository.branch_exists?(source_branch) ? source_branch : project.default_branch_or_main
      end

      def create_workload_branch
        workload_branch_service = ::Ci::Workloads::WorkloadBranchService.new(
          current_user: service_account,
          project: project,
          source_branch: @params.fetch(:source_branch, nil)
        )
        workload_branch_service.execute
      end
    end
  end
end
