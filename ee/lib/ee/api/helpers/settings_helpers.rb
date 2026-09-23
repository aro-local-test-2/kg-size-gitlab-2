# frozen_string_literal: true

module EE
  module API
    module Helpers
      module SettingsHelpers
        extend ActiveSupport::Concern

        prepended do
          params :optional_params_ee do
            optional :elasticsearch_aws, type: Grape::API::Boolean, desc: 'Enable support for AWS hosted elasticsearch'

            given elasticsearch_aws: ->(val) { val } do
              optional :elasticsearch_aws_access_key, type: String, desc: 'AWS IAM access key'
              requires :elasticsearch_aws_region, type: String, desc: 'The AWS region the elasticsearch domain is configured'
              optional :elasticsearch_aws_secret_access_key, type: String, desc: 'AWS IAM secret access key'
            end

            optional :elasticsearch_indexing, type: Grape::API::Boolean, desc: 'Enable Elasticsearch indexing'

            given elasticsearch_indexing: ->(val) { val } do
              optional :elasticsearch_search, type: Grape::API::Boolean, desc: 'Enable Elasticsearch search'
              optional :elasticsearch_pause_indexing, type: Grape::API::Boolean, desc: 'Pause Elasticsearch indexing (global control for both Advanced Search and ActiveContext)'
              optional :elasticsearch_advanced_search_pause_indexing, type: Grape::API::Boolean, desc: 'Pause advanced search indexing'
              requires :elasticsearch_url, type: String, desc: 'The url to use for connecting to Elasticsearch. Use a comma-separated list to support clustering (e.g., "http://localhost:9200, http://localhost:9201")'
              optional :elasticsearch_username, type: String, desc: 'The username of your Elasticsearch instance.'
              optional :elasticsearch_password, type: String, desc: 'The password of your Elasticsearch instance.'
              optional :elasticsearch_limit_indexing, type: Grape::API::Boolean, desc: 'Limit Elasticsearch to index certain namespaces and projects'
            end

            optional :active_context_pause_indexing, type: Grape::API::Boolean, desc: 'Pause ActiveContext indexing'

            given elasticsearch_limit_indexing: ->(val) { val } do
              optional :elasticsearch_namespace_ids, type: Array[Integer], coerce_with: ::API::Validations::Types::CommaSeparatedToIntegerArray.coerce, desc: 'The namespace ids to index with Elasticsearch.'
              optional :elasticsearch_project_ids, type: Array[Integer], coerce_with: ::API::Validations::Types::CommaSeparatedToIntegerArray.coerce, desc: 'The project ids to index with Elasticsearch.'
            end

            optional :secret_detection_token_revocation_enabled, type: ::Grape::API::Boolean, desc: 'Enable Secret Detection Token Revocation'
            # The two URLs below configure the external Token Revocation API, which is only used
            # for third-party secret types. GitLab PAT revocation is handled internally and does
            # not need them, so enabling the setting must not require them.
            optional :secret_detection_token_revocation_url, type: String, desc: 'The configured Secret Detection Token Revocation instance URL'
            optional :secret_detection_revocation_token_types_url, type: String, desc: 'The configured Secret Detection Revocation Token Types instance URL'

            optional :email_additional_text, type: String, desc: 'Additional text added to the bottom of every email for legal/auditing/compliance reasons'
            optional :default_project_deletion_protection, type: Grape::API::Boolean, desc: 'Disable project owners ability to delete project'
            optional :disable_personal_access_tokens, type: Grape::API::Boolean, desc: 'Disable personal access tokens'
            optional :repository_size_limit, type: Integer, desc: 'Size limit per repository (MB)'
            optional :file_template_project_id, type: Integer, desc: 'ID of project where instance-level file templates are stored.'
            optional :usage_ping_enabled, type: Grape::API::Boolean, desc: 'Every week GitLab will report license usage back to GitLab, Inc.'
            optional :updating_name_disabled_for_users, type: Grape::API::Boolean, desc: 'Flag indicating if users are permitted to update their profile name'
            optional :disable_overriding_approvers_per_merge_request, type: Grape::API::Boolean, desc: 'Disable Users ability to overwrite approvers in merge requests.'
            optional :prevent_merge_requests_author_approval, type: Grape::API::Boolean, desc: 'Disable Merge request author ability to approve request.'
            optional :prevent_merge_requests_committers_approval, type: Grape::API::Boolean, desc: 'Disable Merge request committer ability to approve request.'
            optional :maven_package_requests_forwarding, type: Grape::API::Boolean, desc: 'Maven package requests are forwarded to repo.maven.apache.org if not found on GitLab.'
            optional :npm_package_requests_forwarding, type: Grape::API::Boolean, desc: 'NPM package requests are forwarded to npmjs.org if not found on GitLab.'
            optional :pypi_package_requests_forwarding, type: Grape::API::Boolean, desc: 'PyPI package requests are forwarded to pypi.org if not found on GitLab.'
            optional :rubygems_package_requests_forwarding, type: Grape::API::Boolean, desc: 'RubyGems package requests are forwarded to rubygems.org if not found on GitLab.'
            optional :virtual_registries_endpoints_api_limit, type: Integer, desc: 'Virtual Registries API endpoints rate limit.'
            optional :audit_events_api_limit, type: Integer, desc: 'Maximum number of requests per minute per user to the instance audit events API.'
            optional :project_audit_events_api_limit, type: Integer, desc: 'Maximum number of requests per minute per user per project to the project audit events API.'
            optional :group_audit_events_api_limit, type: Integer, desc: 'Maximum number of requests per minute per user per group to the group audit events API.'
            optional :group_owners_can_manage_default_branch_protection, type: Grape::API::Boolean, desc: 'Allow owners to manage default branch protection in groups'
            optional :maintenance_mode, type: Grape::API::Boolean, desc: 'When instance is in maintenance mode, non-admin users can sign in with read-only access and make read-only API requests'
            optional :maintenance_mode_message, type: String, desc: 'Message displayed when instance is in maintenance mode'
            optional :git_two_factor_session_expiry, type: Integer, desc: 'Maximum duration (in minutes) of a session for Git operations when 2FA is enabled'
            optional :max_number_of_repository_downloads, type: Integer, desc: 'Maximum number of unique repositories a user can download in the specified time period before they are banned'
            optional :max_number_of_repository_downloads_within_time_period, type: Integer, desc: 'Reporting time period (in seconds)'
            optional :git_rate_limit_users_allowlist, type: Array[String], coerce_with: ::API::Validations::Types::CommaSeparatedToArray.coerce, desc: 'List of usernames excluded from Git anti-abuse rate limits'
            optional :git_rate_limit_users_alertlist, type: Array[Integer], desc: 'List of user ids who will be emailed when Git abuse rate limit is exceeded'
            optional :auto_ban_user_on_excessive_projects_download, type: Grape::API::Boolean, desc: 'Ban users from the application when they exceed maximum number of unique projects download in the specified time period'
            optional :make_profile_private, type: Grape::API::Boolean, desc: 'Flag indicating if users are permitted to make their profiles private'
            optional :service_access_tokens_expiration_enforced, type: Grape::API::Boolean, desc: "To enforce token expiration for Service accounts users"
            optional :duo_features_enabled, type: ::Grape::API::Boolean, desc: "Indicates whether GitLab Duo features are enabled for the group"
            optional :lock_duo_features_enabled, type: ::Grape::API::Boolean, desc: "Indicates if the GitLab Duo features enabled setting is enforced for all subgroups"
            optional :disabled_direct_code_suggestions, type: ::Grape::API::Boolean, desc: "Indicates if direct connection for Code Suggestions is disabled for users"
            optional :receptive_cluster_agents_enabled, type: ::Grape::API::Boolean, desc: 'Enable receptive mode for GitLab Agents for Kubernetes'
            optional :auto_duo_code_review_enabled, type: ::Grape::API::Boolean, desc: "Enable automatic reviews by GitLab Duo on merge requests"
            optional :security_scan_stale_after_days, type: Integer, desc: 'Number of days before security scan data is considered stale (7-90)'
            optional :duo_custom_agents_enabled, type: ::Grape::API::Boolean, desc: "Indicates whether custom agents are allowed for this instance"
            optional :lock_duo_custom_agents_enabled, type: ::Grape::API::Boolean, desc: "Indicates if the custom agents enabled setting is enforced for all groups"
            optional :duo_custom_flows_enabled, type: ::Grape::API::Boolean, desc: "Indicates whether custom flows are allowed for this instance"
            optional :lock_duo_custom_flows_enabled, type: ::Grape::API::Boolean, desc: "Indicates if the custom flows enabled setting is enforced for all groups"
            optional :duo_external_agents_enabled, type: ::Grape::API::Boolean, desc: "Indicates whether external agents are allowed for this instance"
            optional :lock_duo_external_agents_enabled, type: ::Grape::API::Boolean, desc: "Indicates if the external agents enabled setting is enforced for all groups"
            optional :duo_remote_flows_enabled, type: ::Grape::API::Boolean, desc: "Indicates whether GitLab Duo remote flows are enabled for the instance"
            optional :lock_duo_remote_flows_enabled, type: ::Grape::API::Boolean, desc: "Indicates if the GitLab Duo remote flows enabled setting is enforced for all subgroups"
            optional :duo_workflows_default_image_registry, type: String, desc: "Default container registry for Duo Agent Platform foundational flow images"
            optional :ci_telemetry_otel_endpoint, type: String, desc: "OTEL Collector endpoint URL for CI job telemetry"
            optional :ci_job_telemetry_sampling_rate, type: Float, desc: "Sampling rate for CI job telemetry (0.0 to 1.0)"
            optional :duo_namespace_access_rules, type: Array, desc: 'AI entity access rules for controlling Duo feature access' do
              optional :through_namespace, type: Hash, desc: 'Object containing through namespace information' do
                requires :id, type: Integer, desc: 'ID of the through namespace'
                optional :name, type: String, desc: 'Name of the through namespace'
                optional :full_path, type: String, desc: 'Full path of the through namespace'
              end
              requires :features, type: Array[String], desc: 'List of accessible features', allow_blank: true
            end
            optional :built_in_project_templates_enabled, type: ::Grape::API::Boolean, desc: 'Enable built-in project templates for project creation'
            optional :lock_built_in_project_templates_enabled, type: ::Grape::API::Boolean, desc: 'Enforce the built-in project templates setting for all groups'
            optional :duo_template_project_id,
              type: Integer,
              desc: 'The ID of a project to use as the Duo Code Review custom instructions template for this instance'
            optional :use_nats_for_audit_streaming,
              type: ::Grape::API::Boolean,
              desc: 'Route audit event streaming through NATS JetStream when the instance has NATS configured'
            # The parameters below are also declared by the `optional_attributes` splat in
            # API::Settings, which cannot carry per-parameter metadata. Descriptions are verbatim
            # from doc/api/settings.md. Only `desc` is set: adding `type` here would make Grape
            # reject values that ActiveRecord currently coerces, which is a breaking change.
            # See https://gitlab.com/gitlab-org/gitlab/-/work_items/612735
            # rubocop:disable API/ParameterType -- types are added in https://gitlab.com/gitlab-org/gitlab/-/work_items/618695
            optional :allow_all_integrations,
              desc: 'When `false`, only integrations in `allowed_integrations` are allowed on the instance. Ultimate ' \
                'only.'
            optional :allow_group_owners_to_manage_ldap,
              desc: 'Set to `true` to allow group owners to manage LDAP. Premium and Ultimate only.'
            optional :allowed_integrations,
              desc: 'When `allow_all_integrations` is `false`, only integrations in this list are allowed on the ' \
                'instance. Ultimate only.'
            optional :automatic_purchased_storage_allocation,
              desc: 'Enabling this permits automatic allocation of purchased storage in a namespace. Relevant only ' \
                'to EE distributions.'
            optional :check_namespace_plan,
              desc: "Enabling this makes only licensed EE features available to projects if the project namespace's " \
                "plan includes the feature or if the project is public. Premium and Ultimate only."
            optional :delete_unconfirmed_users,
              desc: 'Specifies whether users who have not confirmed their email should be deleted. Default is ' \
                '`false`. When set to `true`, unconfirmed users are deleted after ' \
                '`unconfirmed_users_delete_after_days` days. GitLab Self-Managed, Premium and Ultimate only.'
            optional :disable_invite_members, desc: 'Disable invite members functionality for group.'
            optional :elasticsearch_client_adapter,
              desc: 'The Faraday adapter used by the Elasticsearch Ruby Client. Defaults to `typhoeus`. Possible ' \
                'values are `typhoeus` and `net_http`. ' \
                '[Introduced](https://gitlab.com/gitlab-org/gitlab/-/issues/550805) in GitLab 18.5. Premium and ' \
                'Ultimate only.'
            optional :elasticsearch_indexed_field_length_limit,
              desc: 'Maximum size of text fields to index by Elasticsearch. 0 value means no limit. This does not ' \
                'apply to repository and wiki indexing. Premium and Ultimate only.'
            optional :elasticsearch_indexed_file_size_limit_kb,
              desc: 'Maximum size of repository and wiki files that are indexed by Elasticsearch. Premium and ' \
                'Ultimate only.'
            optional :elasticsearch_max_bulk_concurrency,
              desc: 'Maximum concurrency of Elasticsearch bulk requests per indexing operation. This only applies to ' \
                'repository indexing operations. Premium and Ultimate only.'
            optional :elasticsearch_max_bulk_size_mb,
              desc: 'Maximum size of Elasticsearch bulk indexing requests in MB. This only applies to repository ' \
                'indexing operations. Premium and Ultimate only.'
            optional :elasticsearch_max_code_indexing_concurrency,
              desc: 'Maximum concurrency of Elasticsearch code indexing background jobs. This only applies to ' \
                'repository indexing operations. Premium and Ultimate only.'
            optional :elasticsearch_replicas,
              desc: 'Number of replicas for Elasticsearch indices. Use an integer to set all indices to the same ' \
                'value. Use an object to set per-index values. For example: `{"gitlab-production": 1, ' \
                '"gitlab-production-notes": 2}`. <br>When using an object, you must provide both ' \
                '`elasticsearch_shards` and `elasticsearch_replicas` for each index. If either value is missing for ' \
                'an index, that index is skipped. Premium and Ultimate only.'
            optional :elasticsearch_requeue_workers,
              desc: 'Enable automatic requeuing of indexing workers. This improves non-code indexing throughput by ' \
                'enqueuing Sidekiq jobs until all documents are processed. Premium and Ultimate only.'
            optional :elasticsearch_retry_on_failure,
              desc: 'Maximum number of possible retries for Elasticsearch search requests. Premium and Ultimate ' \
                'only.'
            optional :elasticsearch_shards,
              desc: 'Number of shards for Elasticsearch indices. Use an integer to set all indices to the same ' \
                'value. Use an object to set per-index values. For example: `{"gitlab-production": 5, ' \
                '"gitlab-production-notes": 3}`. <br>When using an object, you must provide both ' \
                '`elasticsearch_shards` and `elasticsearch_replicas` for each index. If either value is missing for ' \
                'an index, that index is skipped. Premium and Ultimate only.'
            optional :elasticsearch_worker_number_of_shards,
              desc: 'Number of indexing worker shards. This improves non-code indexing throughput by enqueuing more ' \
                'parallel Sidekiq jobs. Default is `2`. Premium and Ultimate only.'
            optional :enforce_namespace_storage_limit,
              desc: 'Enabling this permits enforcement of namespace storage limits.'
            optional :enforce_pipl_compliance,
              desc: 'Sets whether pipl compliance is enforced for the saas application or not'
            optional :geo_node_allowed_ips,
              desc: 'Comma-separated list of IPs and CIDRs of allowed secondary nodes. For example, `1.1.1.1, ' \
                '2.2.2.0/24`. GitLab Self-Managed, Premium and Ultimate only.'
            optional :geo_status_timeout,
              desc: 'The amount of seconds after which a request to get a secondary node status times out. GitLab ' \
                'Self-Managed, Premium and Ultimate only.'
            optional :globally_allowed_ips,
              desc: 'Comma-separated list of IP addresses and CIDRs always allowed for inbound traffic. For example, ' \
                '`1.1.1.1, 2.2.2.0/24`.'
            optional :group_secrets_limit,
              desc: 'Maximum number of secrets allowed per group in Secrets Manager. Default: 500. To disable the ' \
                'limit, set to `0`. Ultimate only. ' \
                '[Introduced](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/219436) in GitLab 18.9.'
            optional :lock_memberships_to_saml, desc: 'Enforce a global lock on SAML group memberships.'
            optional :max_personal_access_token_lifetime,
              desc: 'Maximum allowable lifetime for access tokens in days. When left blank, default value of 365 is ' \
                'applied. When set, value must be 365 or less. When changed, existing access tokens with an ' \
                'expiration date beyond the maximum allowable lifetime are revoked. GitLab Self-Managed, Ultimate ' \
                'only. In GitLab 17.6 or later, the maximum lifetime limit can be [extended to 400 ' \
                'days](https://gitlab.com/gitlab-org/gitlab/-/issues/461901) by enabling a feature flag named ' \
                '`buffered_token_expiration_limit`.'
            optional :max_ssh_key_lifetime,
              desc: 'Maximum allowable lifetime for SSH keys in days. GitLab Self-Managed, Ultimate only. In GitLab ' \
                '17.6 or later, the maximum lifetime limit can be [extended to 400 ' \
                'days](https://gitlab.com/gitlab-org/gitlab/-/issues/461901) by enabling a feature flag named ' \
                '`buffered_token_expiration_limit`.'
            optional :mirror_capacity_threshold,
              desc: 'Minimum capacity to be available before scheduling more mirrors preemptively. Premium and ' \
                'Ultimate only.'
            optional :mirror_max_capacity,
              desc: 'Maximum number of mirrors that can be synchronizing at the same time. Premium and Ultimate only.'
            optional :mirror_max_delay,
              desc: 'Maximum time (in minutes) between updates that a mirror can have when scheduled to ' \
                'synchronize. Premium and Ultimate only.'
            optional :package_metadata_purl_types,
              desc: 'List of package registry metadata to sync. See [the ' \
                'list](https://gitlab.com/gitlab-org/gitlab/-/blob/ace16c20d5da7c4928dd03fb139692638b557fe3/app/models/concerns/enums/package_metadata.rb#L5) ' \
                'of the available values. GitLab Self-Managed, Ultimate only.'
            optional :password_lowercase_required,
              desc: 'Indicates whether passwords require at least one lowercase letter. Premium and Ultimate only.'
            optional :password_number_required,
              desc: 'Indicates whether passwords require at least one number. Premium and Ultimate only.'
            optional :password_symbol_required,
              desc: 'Indicates whether passwords require at least one symbol character. Premium and Ultimate only.'
            optional :password_uppercase_required,
              desc: 'Indicates whether passwords require at least one uppercase letter. Premium and Ultimate only.'
            optional :project_secrets_limit,
              desc: 'Maximum number of secrets allowed per project in Secrets Manager. Default: 100. To disable the ' \
                'limit, set to `0`. Ultimate only. ' \
                '[Introduced](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/219436) in GitLab 18.9.'
            optional :scan_execution_policies_action_limit,
              desc: 'Maximum number of `actions` per scan execution policy. Default: 0. Maximum: 20'
            optional :scan_execution_policies_schedule_limit,
              desc: 'Maximum number of `type: schedule` rules per scan execution policy. Default: 0. Maximum: 20'
            optional :secret_push_protection_available,
              desc: 'Allow projects to enable secret push protection. This does not enable secret push protection. ' \
                'Ultimate only.'
            optional :security_approval_policies_limit,
              desc: 'Maximum number of active merge request approval policies per security policy project. Default: ' \
                '5. Maximum: 20'
            optional :security_mr_report_cache_lifetime_minutes,
              desc: 'Number of minutes to cache security reports on merge requests (10-60). Default: 10. Premium and ' \
                'Ultimate only. [Introduced](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/223399) in GitLab ' \
                '18.10.'
            optional :shared_runners_minutes,
              desc: 'Set the maximum number of compute minutes that a group can use on instance runners per month. ' \
                'Premium and Ultimate only.'
            optional :unconfirmed_users_delete_after_days,
              desc: 'Specifies how many days after account creation to delete users who have not confirmed their ' \
                'email. Only applicable if `delete_unconfirmed_users` is set to `true`. Must be `1` or greater. ' \
                'Default is `7`. GitLab Self-Managed, Premium and Ultimate only.'
            # rubocop:enable API/ParameterType
          end
        end

        class_methods do
          extend ::Gitlab::Utils::Override

          override :optional_attributes
          def optional_attributes
            super + EE::ApplicationSettingsHelper.possible_licensed_attributes
          end
        end
      end
    end
  end
end
