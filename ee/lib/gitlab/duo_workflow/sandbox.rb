# frozen_string_literal: true

require 'shellwords'

module Gitlab
  module DuoWorkflow
    # Service responsible for configuring SRT (Secure Runtime) sandbox for Duo Workflow execution
    # This class configures network firewall and filesystem restrictions for DAP ambient sessions.
    class Sandbox
      # Protected directory for platform-internal files (e.g. srt-settings.json).
      # Uses /var/tmp (world-writable, sticky bit) so any user - root or non-root -
      # can create the directory without elevated privileges. This avoids permission
      # errors on hardened images that run as a non-root UID.
      # The agent is explicitly denied write access via SRT's denyWrite rule.
      SANDBOX_SYSTEM_DIR = "/var/tmp/.gitlab-sandbox"

      # nono filesystem policy, translating SRT's `filesystem` block. Traps:
      #
      # - Not --allow-cwd: it grants the CWD read-only, leaving .git/ unwritable.
      # - Grant leaf paths only. Landlock cannot enforce a deny nested under an
      #   allowed parent, so nono refuses to start if a grant contains one of its
      #   deny rules - which rules out $HOME and $HOME/.config.
      # - $HOME and $CI_PROJECT_DIR must stay unescaped; the job shell expands
      #   them before `env -i` drops them.
      # - The .tmp files are the Runner's git-config include targets under
      #   FF_GIT_URLS_WITHOUT_TOKENS; an unreadable one is fatal to every git call.
      # - git's exec path: fetch/push exec git-remote-http out of it.
      NONO_FS_GRANTS = [
        '--allow .',
        '--allow /tmp',
        '--read-file "$HOME/.gitconfig"',
        '--read-file "$HOME/.gitignore_global"',
        '--read "$HOME/.config/git"',
        '--read "$HOME/.config/glab-cli"',
        '--read-file "${CI_PROJECT_DIR:-$PWD}.tmp/.gitlab-runner.ext.conf"',
        '--read-file "${CI_PROJECT_DIR:-$PWD}.tmp/.glr.gconf"',
        '--read "$HOME/.gitlab"',
        '--read "$HOME/.agents"',
        '--read "$(git --exec-path 2>/dev/null || echo /usr/libexec/git-core)"'
      ].freeze

      def initialize(current_user:, duo_workflow_service_url:, duo_config:, project: nil, unmask_env_variables: [])
        @current_user = current_user
        @duo_workflow_service_url = duo_workflow_service_url
        @duo_config = duo_config
        @project = project
        @unmask_env_variables = unmask_env_variables
      end

      # Wraps a command with the configured sandbox.
      #
      # Routes to nono (Landlock) when :duo_workflow_nono_sandbox is enabled for
      # the project; otherwise uses the existing SRT/bubblewrap path (default).
      #
      # @param command [String] The command to wrap
      # @return [Array<String>] Array with shell commands
      def wrap_command(command)
        if Feature.enabled?(:duo_workflow_nono_sandbox, @project)
          wrap_command_nono(command)
        else
          wrap_command_srt(command)
        end
      end

      def environment_variables
        {
          NPM_CONFIG_CACHE: "/tmp/.npm-cache",
          GITLAB_LSP_STORAGE_DIR: "/tmp/gitlab-lsp",
          TMPDIR: "/tmp"
        }
      end

      def setup_sandbox_commands
        [
          %(mkdir -p #{SANDBOX_SYSTEM_DIR})
        ]
      end

      private

      # Builds environment variable flags for unshare command
      # Uses variable references (e.g., $VAR) instead of embedding values to avoid logging sensitive data
      # Combines passed variables with sandbox-specific environment variables
      # @return [String] Environment variable flags formatted for unshare command
      def build_env_vars_flags
        all_vars = @unmask_env_variables + environment_variables.keys + %w[PATH GITLAB_WORKFLOW_SANDBOX]
        all_vars.uniq.map { |var| "#{var}=\"$#{var}\"" }.join(' ')
      end

      # Computes effective allowed/denied domains from the inherited + project policy.
      # Reuses combine_settings / parent_settings / minimal_allowlisted_domains so the
      # nono path stays in sync with the SRT path without duplicating logic.
      #
      # Network policy only; the filesystem policy is NONO_FS_GRANTS.
      #
      # :allow_all_unix_sockets has no nono equivalent and is dropped. The drop
      # is very likely a loosening, not a tightening: Landlock's network rules
      # cover TCP bind/connect only, so nothing here restricts Unix sockets, and
      # the setting's restrictive default (false) stops being honoured while this
      # flag is on. Unverified - the unix-socket arm of the sandbox probe corpus
      # has never been run. Hard blocker on default enablement, tracked at
      # https://gitlab.com/gitlab-org/gitlab/-/work_items/624259.
      #
      # @return [Hash] with :allowed and :denied domain arrays
      def computed_domains
        combined = combine_settings(parent_settings)
        {
          allowed: (minimal_allowlisted_domains + combined[:allow_list]).compact.uniq,
          denied: combined[:deny_list].compact.uniq
        }
      end

      # Translates the effective network policy into nono CLI flags.
      # @param domains [Hash] result of computed_domains
      # @return [String] space-joined --allow-domain / --deny-domain flags
      def build_nono_flags(domains)
        allow_flags = domains[:allowed].map { |d| "--allow-domain #{Shellwords.escape(d)}" }
        deny_flags = domains[:denied].map { |d| "--deny-domain #{Shellwords.escape(d)}" }
        (allow_flags + deny_flags).join(' ')
      end

      # @return [String] space-joined filesystem grant flags
      def build_nono_fs_flags
        NONO_FS_GRANTS.join(' ')
      end

      # nono (Landlock-based) sandbox path.
      #
      # Unlike SRT/bubblewrap, nono self-restricts via Landlock (an unprivileged
      # LSM), so there is no user namespace to probe for. nono itself fails closed:
      # if it cannot enforce the policy it errors ("No supported Landlock ABI
      # detected", "Landlock sandbox was not enforced") rather than running the
      # command unsandboxed.
      #
      # This path fails closed throughout, unlike wrap_command_srt. Both
      # conditions below abort the job rather than downgrading to an unsandboxed
      # run:
      #   1. nono is not on PATH.
      #   2. the capability pre-check below fails - a pre-5.13 kernel, Landlock
      #      compiled out, or a grant that contains one of nono's own deny rules
      #      (see NONO_FS_GRANTS), which makes nono refuse to start.
      #
      # nono is opt-in behind :duo_workflow_nono_sandbox, so the flag is itself
      # the opt-out: disabling it restores the SRT path and its fail-open
      # behaviour. That is what makes refusing here affordable.
      #
      # The guarantee is bounded, and the bound matters. It holds against a nono
      # that is absent or cannot enforce the policy. It does NOT hold against a
      # nono that has been substituted: the job is one ordered script, the
      # project's setup_script runs before this block in the same shell, and both
      # `command -v nono` and the `nono run` invocations below resolve through
      # PATH. A project-supplied binary that exits 0 on the pre-check and then
      # execs the command unsandboxed would satisfy every check here. Closing
      # that requires a platform-provided binary at a path the project cannot
      # shadow, plus a floor on the accepted version - neither is possible from
      # Rails alone, and both are hard blockers on default enablement tracked at
      # https://gitlab.com/gitlab-org/gitlab/-/work_items/624259.
      #
      # The pre-check runs the real policy against `true`, mirroring SRT's
      # `srt --settings ... true`, so a policy that cannot be enforced is caught
      # before the executor runs instead of surfacing as an opaque mid-job error.
      # Its combined output is captured and echoed on failure: a missing Landlock
      # ABI and a grant nono refuses both fail this same check but need different
      # fixes, so the trace has to say which happened rather than blame the kernel.
      # The real run stays verbose too, so nono's grant warnings and enforcement
      # summary reach the trace.
      #
      # Both carry the same `env -i` prefix. A pre-check that inherits the job
      # environment is a weaker rehearsal than the run it stands in for: an
      # environment variable nono reads would be present for the pre-check and
      # stripped from the run, so the check could pass while the run fails - the
      # one outcome the check exists to prevent. The grant strings were always
      # identical (the outer shell expands $HOME, $CI_PROJECT_DIR and
      # $(git --exec-path) before `env -i` applies to the nono process), so only
      # nono's own environment differed. One residual difference remains:
      # GITLAB_WORKFLOW_SANDBOX is exported after the pre-check, so the pre-check
      # passes it empty where the run passes "true".
      #
      # Policy: NONO_FS_GRANTS (filesystem) + build_nono_flags (network).
      #
      # @param command [String] The command to wrap
      # @return [Array<String>] Array with shell commands
      def wrap_command_nono(command)
        domains = computed_domains
        # nono only switches egress to default-deny once at least one --allow-domain is
        # passed, so an empty allowlist would leave the network unrestricted.
        #
        # This is decided here, at script-generation time, rather than at runtime like
        # the two checks below, but the outcome is the same: a policy that cannot
        # restrict egress is refused outright.
        return empty_allowlist_commands if domains[:allowed].empty?

        env_vars_flags = build_env_vars_flags
        # Applied to the pre-check and the real run alike, so the rehearsal runs
        # under the same stripped environment the executor gets. Mirrors the SRT
        # path's shared $SANDBOX_UNSHARE prefix.
        env_prefix = %(env -i HOME="$HOME" #{env_vars_flags})
        nono_flags = build_nono_flags(domains)
        nono_policy_flags = "#{build_nono_fs_flags} #{nono_flags}"
        nono_run = %(#{env_prefix} nono run #{nono_policy_flags} -- #{command})
        # Deliberately no --silent and no redirect to /dev/null: on failure this
        # output is the only thing that distinguishes a kernel problem from a
        # refused grant. The assignment's exit status is the command's, so it
        # still drives the `if` directly.
        nono_check = %(nono_precheck_output="$(#{env_prefix} nono run #{nono_policy_flags} -- true 2>&1)")
        [
          %(if command -v nono > /dev/null 2>&1; then),
          %(  echo "nono found, testing Landlock sandbox capabilities..."),
          %(  if #{nono_check}; then),
          %(    echo "nono sandbox test successful, running command under Landlock sandbox: #{command}"),
          %(    export GITLAB_WORKFLOW_SANDBOX=true),
          %(    #{nono_run}),
          %(  else),
          %(    echo "Error: nono found but the sandbox pre-check failed, refusing to run without a sandbox"),
          %(    echo "nono reported: $nono_precheck_output"),
          %(    echo "Likely causes: Landlock unavailable (needs Linux 5.13+), or a grant nono refuses"),
          %(    echo "For more details visit: https://docs.gitlab.com/user/duo_agent_platform/flows/execution/#configure-runners"),
          %(    exit 1),
          %(  fi),
          %(else),
          %(  echo "Error: nono not found on PATH (image must ship it), refusing to run without a sandbox"),
          %(  echo "For more details visit: https://docs.gitlab.com/user/duo_agent_platform/flows/execution/#configure-runners"),
          %(  exit 1),
          %(fi),
          %(echo "Command execution completed with exit code: $?")
        ]
      end

      # Refuses to run when no domain is allowed, rather than handing the agent an
      # unrestricted network.
      # @return [Array<String>] Array with shell commands
      def empty_allowlist_commands
        [
          %(echo "Error: nono sandbox has an empty domain allowlist, refusing to run without egress limits"),
          %(echo "For more details visit: https://docs.gitlab.com/user/duo_agent_platform/flows/execution/#configure-runners"),
          %(exit 1)
        ]
      end

      # Original SRT/bubblewrap sandbox path (default; behaviour unchanged).
      #
      # At runtime the script probes which unshare mode is available and stores
      # the result in $SANDBOX_UNSHARE.  The same prefix is applied to both the
      # SRT capability pre-check and the real run so that a failing unshare is
      # detected early rather than silently skipped.
      #
      # Probe order (first success wins):
      #   1. unshare -m true   - mount namespace only; works as root / CAP_SYS_ADMIN
      #                          (default image, SaaS path - byte-for-byte unchanged)
      #   2. unshare -rm true  - user + mount namespace; works for non-root with
      #                          unprivileged user-namespace support (hardened image,
      #                          UID 1001).  unshare -r maps UID 1001 to root *inside*
      #                          the new user namespace only; it grants no host
      #                          privilege and maps back to UID 1001 on the host.
      #   3. (empty)           - no namespace wrapper; fail-open fallback
      #
      # Probe order rationale: trying -m first means root (SaaS) resolves to -m,
      # preserving the existing SaaS behaviour exactly.  Non-root (hardened image)
      # falls through to -rm because -m fails without CAP_SYS_ADMIN.
      #
      # @param command [String] The command to wrap
      # @return [Array<String>] Array with shell commands
      def wrap_command_srt(command)
        srt_settings_path = "#{SANDBOX_SYSTEM_DIR}/srt-settings.json"
        env_vars_flags = build_env_vars_flags
        [
          %(if which srt > /dev/null; then),
          %(  echo "SRT found, creating config..."),
          %(  echo #{Shellwords.escape(Gitlab::Json.dump(srt_config))} > #{srt_settings_path}),
          %(  echo "Testing SRT sandbox capabilities..."),
          %(  if unshare -m true 2>/dev/null; then),
          %(    SANDBOX_UNSHARE="unshare -m"),
          %(  elif unshare -rm true 2>/dev/null; then),
          %(    SANDBOX_UNSHARE="unshare -rm"),
          %(  else),
          %(    SANDBOX_UNSHARE=""),
          %(  fi),
          %(  if $SANDBOX_UNSHARE srt --settings #{srt_settings_path} true 2>/dev/null; then),
          %(    echo "SRT sandbox test successful, running command: #{command}"),
          %(    export GITLAB_WORKFLOW_SANDBOX=true),
          %(    $SANDBOX_UNSHARE env -i #{env_vars_flags} srt --settings #{srt_settings_path} #{command}),
          %(  else),
          %(    echo "Warning: SRT found but can't create sandbox (insufficient privileges), running command directly"),
          %(    echo "For more details visit: https://docs.gitlab.com/user/duo_agent_platform/flows/execution/#configure-runners"),
          %(    #{command}),
          %(  fi),
          %(else),
          %(  echo "Warning: srt is not installed or not in PATH, running command directly without sandbox"),
          %(  echo "For more details visit: https://docs.gitlab.com/user/duo_agent_platform/flows/execution/#configure-runners"),
          %(  #{command}),
          %(fi),
          %(echo "Command execution completed with exit code: $?")
        ]
      end

      # Returns parent AI settings: namespace-level (SaaS TLG) or instance-level (self-managed).
      # @return [Ai::NamespaceSetting, Ai::Setting]
      def parent_settings
        return @project.root_ancestor.ai_settings if ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)

        # rubocop:disable Gitlab/AvoidUserOrganization -- fallback for project-less workflows; in Cells 1.0 a user belongs to exactly one organization
        organization = @project&.organization || @current_user.organization
        # rubocop:enable Gitlab/AvoidUserOrganization

        return ::Ai::Setting.new unless organization

        ::Ai::Setting.for_organization_read_only(organization)
      end

      # Generates SRT configuration for network and filesystem restrictions
      # @return [Hash] SRT configuration
      def srt_config
        # Combine top-level parent and project settings
        inherited_settings = parent_settings
        combined_settings = combine_settings(inherited_settings)
        effective_allowed = combined_settings[:allow_list]
        effective_denied = combined_settings[:deny_list]
        allow_all_unix_sockets = combined_settings[:allow_all_unix_sockets]

        allowed_domains = (minimal_allowlisted_domains + effective_allowed).compact.uniq
        denied_domains = effective_denied.compact.uniq
        {
          network: {
            allowedDomains: allowed_domains,
            deniedDomains: denied_domains,
            allowAllUnixSockets: !!allow_all_unix_sockets
          },
          filesystem: {
            denyRead: ["~/.ssh"],
            allowWrite: ["./", "/tmp"],
            denyWrite: [SANDBOX_SYSTEM_DIR],
            allowGitConfig: true
          }
        }
      end

      # Combines settings that are inherited from top-level group or instance,
      # with the settings specified in a project's agent-config.yml file:
      #   * A project can always extend the inherited deny list
      #   * A project can only add to the inherited allow-list if the parent has set allow_project_extension
      #   * For allow_all_unix_sockets and include_recommended_allowed:
      #     * With allow_project_extension: project can set either value freely
      #     * Without allow_project_extension: project can only tighten (set false when inherited is true);
      #       loosening (set true when inherited is false) is not permitted
      def combine_settings(inherited_settings)
        # Project-level settings:
        duo_config_allow_all_unix_sockets = load_duo_config_all_unix_sockets
        duo_config_allow_domains, duo_config_deny_domains = load_duo_config_domains
        duo_config_include_recommended = load_duo_config_include_recommended_allowed

        # Inherited settings:
        allow_project_extension = inherited_settings.allow_project_extension
        effective_allowed = inherited_settings.allowed_domains.to_a.dup
        effective_denied = inherited_settings.denied_domains.to_a.dup
        effective_allow_all_unix_sockets = inherited_settings.allow_all_unix_sockets
        effective_include_recommended_allowed = inherited_settings.include_recommended_allowed

        if allow_project_extension
          # Flexible mode: project can extend the allowlist and add to the denylist
          effective_allowed += duo_config_allow_domains
          effective_denied += duo_config_deny_domains

          unless duo_config_include_recommended.nil?
            effective_include_recommended_allowed = duo_config_include_recommended
          end

          unless duo_config_allow_all_unix_sockets.nil?
            effective_allow_all_unix_sockets = duo_config_allow_all_unix_sockets
          end
        else
          # Strict mode: project cannot loosen settings (allowlist and loosening booleans are ignored);
          # project denylist additions are always honored (more restrictive is allowed).
          # Boolean settings can only be overridden by tightening: project can set false when inherited is true.
          effective_denied += duo_config_deny_domains

          effective_include_recommended_allowed =
            tighten(effective_include_recommended_allowed, duo_config_include_recommended)
          effective_allow_all_unix_sockets =
            tighten(effective_allow_all_unix_sockets, duo_config_allow_all_unix_sockets)
        end

        effective_allowed += NetworkPolicyDomains.recommended_allowed_domains if effective_include_recommended_allowed

        effective_allowed = effective_allowed.compact.uniq
        effective_denied = effective_denied.compact.uniq

        {
          allow_list: effective_allowed,
          deny_list: effective_denied,
          allow_all_unix_sockets: effective_allow_all_unix_sockets
        }
      end

      # Returns the project value only if it represents a tightening change (strict mode only).
      # In strict mode, a project can only disable a setting, never enable it.
      # @param inherited_value [Boolean, nil] The inherited boolean value
      # @param project_value [Boolean, nil] The project-level boolean value
      # @return [Boolean, nil] The effective value after applying tightening rules
      def tighten(inherited_value, project_value)
        return inherited_value if project_value.nil?
        return inherited_value if project_value && !inherited_value # would loosen - ignore

        project_value
      end

      # Returns list of required domains allowed for network access
      # @return [Array<String>] Allowed domains
      def minimal_allowlisted_domains
        [
          "host.docker.internal",
          "localhost",
          extract_domain(Gitlab.config.gitlab.url),
          "*.#{extract_domain(Gitlab.config.gitlab.url)}",
          extract_domain(@duo_workflow_service_url)
        ]
      end

      def load_duo_config_all_unix_sockets
        network_policy = @duo_config.network_policy
        return unless network_policy

        network_policy.fetch("allow_all_unix_sockets", nil)
      end

      def load_duo_config_include_recommended_allowed
        network_policy = @duo_config.network_policy
        return unless network_policy

        network_policy.fetch("include_recommended_allowed", nil)
      end

      def load_duo_config_domains
        network_policy = @duo_config.network_policy
        return [[], []] unless network_policy

        allowed_domains = network_policy.fetch("allowed_domains", [])
        denied_domains = network_policy.fetch("denied_domains", [])

        [allowed_domains, denied_domains]
      end

      # Extracts domain from a URL
      # @param url [String] URL to extract domain from
      # @return [String, nil] Extracted domain
      def extract_domain(url)
        return url if url.blank?

        # Try parsing as a full URI first
        uri = URI.parse(url)
        return uri.host if uri.host

        # If no host found, try parsing as just host:port by prepending //
        uri = URI.parse("//#{url}")
        uri.host
      rescue URI::InvalidURIError
        # Fallback: if it contains a colon, assume it's host:port
        url.include?(':') ? url.split(':').first : url
      end
    end
  end
end
