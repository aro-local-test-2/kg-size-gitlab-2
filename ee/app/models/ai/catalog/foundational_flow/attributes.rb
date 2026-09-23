# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      module Attributes
        extend ActiveSupport::Concern

        DEFAULT_FLOW_VERSION = '1.0.0'
        FEATURE_MATURITIES = %w[experimental beta ga].freeze
        ENVIRONMENTS = Ai::DuoWorkflows::Workflow.environments.keys.freeze
        CODING_ENVIRONMENTS = ::Ai::Catalog::CodingEnvironment::VALUES.keys.freeze

        included do
          auto_generate_ids!

          # Unique versioned identifier (e.g. "fix_pipeline/v1") used to look up the flow
          # and select its Flow Registry config in Duo Workflow Service.
          attribute :foundational_flow_reference, :string

          # User-facing name shown in the UI.
          attribute :display_name, :string

          # Name of the AI unit primitive/feature this flow is gated and tracked against.
          attribute :ai_feature, :string,
            default: "duo_agent_platform"

          # Privileges granted to a running workflow.
          attribute :agent_privileges,
            default: []

          # Subset of `agent_privileges` the flow may use without asking anyone. A
          # privilege that is granted but not pre-approved makes the flow pause and
          # request approval, so only a flow whose surface can actually collect that
          # decision should narrow this. nil means "pre-approve everything granted",
          # which is what a flow running without a human in the loop needs.
          attribute :pre_approved_agent_privileges

          # Whether the agent can pause execution to request human/user input.
          attribute :allow_agent_to_request_user, :boolean,
            default: false

          # Execution environment: "web", "ambient", or "cli".
          attribute :environment, :string,
            default: "ambient"

          # Maturity level ("experimental", "beta", "ga"); drives beta-only availability gating.
          attribute :feature_maturity, :string

          # Brief user-facing description of what the flow does.
          attribute :description, :string

          # Event types (e.g. mention, assign) that auto-create flow triggers for a consumer.
          attribute :triggers,
            default: []

          # A nil value means the flow has no event restrictions (any event is allowed). An empty array means the
          # flow explicitly supports no trigger events.
          attribute :supported_events

          # Resource classes (e.g. `MergeRequest`) a trigger may start this flow for. A nil value means
          # any resource, including none at all, is allowed. An empty array means no resource is accepted.
          attribute :supported_resource_types

          # JSON-schema-like filter checked before a trigger fires (e.g. only run
          # fix_pipeline on failed pipelines).
          attribute :precondition,
            default: {}

          # Filename of the flow's icon, resolved against the GitLab SVGs assets.
          attribute :avatar, :string

          # Restricts availability to groups with an Ultimate license.
          attribute :ultimate_only, :boolean,
            default: false

          # CI report artifacts the workload job should declare. When present,
          # StartWorkflowService forwards this to WorkloadDefinition#artifacts_reports
          # so the runner uploads the files after the job completes.
          # Example: { "sast" => ["gl-sast-report.json"] }
          attribute :report_artifacts,
            default: {}

          # Name of a GitLab feature flag that gates this flow at the group level.
          # nil means the flow is available to everyone who meets the other criteria.
          attribute :feature_flag, :string

          # Flows that manage their own discussion threads can opt out of the generic
          # progress note that is otherwise posted when the flow is triggered by an
          # @mention. Defaults to false so existing flows are unaffected.
          attribute :suppress_mention_progress_note, :boolean,
            default: false

          # Broader form of the above: flows that report their own progress opt out
          # of the generic progress note on every trigger event, not just @mention.
          # Defaults to false so existing flows are unaffected.
          attribute :suppress_progress_note, :boolean,
            default: false

          # Flows whose mention-triggered replies must be internal notes on
          # non-private projects (e.g. a security assessment). Private projects
          # keep the threaded-reply UX -- see
          # EE::Notes::PostProcessService#force_internal_reply?. Defaults to
          # false so existing flows are unaffected.
          attribute :force_internal_mention_replies, :boolean,
            default: false

          # Flows that post their own "session started" note (e.g. Code Review's
          # progress note) can opt out of the generic agent-session-started system
          # note that CreateWorkflowService otherwise posts on the noteable.
          # Defaults to false so existing flows are unaffected.
          attribute :suppress_agent_session_note, :boolean,
            default: false

          attribute :reuse_open_merge_request, :boolean,
            default: false

          # Class implementing .resolve to build the workflow's goal string per trigger event type.
          attribute :goal_templates

          # Lambda resolving the GitLab resource (e.g. a merge request) a workflow
          # session should be linked to. Called with keyword arguments `project:`
          # (a `Project`) and `goal:` (a `String`, or `nil`).
          # Returns the `Noteable` object to where system notes will be added.
          attribute :noteable_resolver

          # Lambda resolving the CI pipeline a workflow session should be linked to
          # as its source (link_type: :source). Called with keyword arguments
          # `project:` (a `Project`) and `goal:` (a `String`, or `nil`).
          # Returns the `Ci::Pipeline` the flow was initiated against, or `nil`.
          attribute :source_pipeline_resolver

          # Lambda resolving the additional context a workflow sends to AIGW.
          # Called with keyword arguments `resource:` (any GitLab resource, e.g. a `MergeRequest`).
          # Returns a `Hash[category => content]` to be sent to AIGW.
          attribute :additional_context_resolver

          # What kind of coding environment the flow needs when its workload starts.
          # See `Ai::Catalog::CodingEnvironment` for the accepted values and for how this
          # is resolved against a catalog flow's own `flow_config` declaration.
          attribute :coding_environment, :string,
            default: 'full'

          # Flow Registry config version used to start the workflow.
          attribute :flow_version, :string,
            default: DEFAULT_FLOW_VERSION

          # Lambda validating and normalizing the `goal` an API caller supplies when
          # starting the flow. Called with keyword arguments `container:` (a `Project`
          # or `Namespace`) and `goal:` (a `String`, or `nil`).
          # Returns a `ServiceResponse`: success with the normalized goal in
          # `payload[:goal]`, or an error with a user-facing message.
          attribute :goal_validator_resolver

          # Lambda resolving a runtime override of the flow's reference and version
          # (e.g. to route to an experimental Flow Registry config behind a feature
          # flag). Called with keyword arguments `container:` (a `Namespace` or
          # `Project`) and `user:` (a `User`, or `nil`).
          # Returns a `[foundational_flow_reference, flow_version]` Array, or `nil`
          # to use the flow's own `foundational_flow_reference` and `flow_version`.
          attribute :flow_version_resolver

          # Lambda resolving a runtime override of the flow's `ai_feature`.
          # Called with keyword argument `current_user:` (a `User`, or `nil`).
          # Returns the `ai_feature` `String` to use, or `nil` to fall back to
          # the flow's own `ai_feature` attribute.
          attribute :ai_feature_resolver

          # Lambda run before the flow starts, for side effects the flow needs in
          # place by then (e.g. a placeholder record a widget reads). Called with
          # `resource:`. To refuse a run, use `goal_validator_resolver` instead.
          attribute :before_start

          # Lambda run once the flow has started, for side effects that only make
          # sense after dispatch. Called with `resource:`. Nothing here can stop a
          # run: by the time it fires, the flow is away.
          attribute :after_start

          validates :display_name,
            :foundational_flow_reference,
            :ai_feature,
            :description,
            presence: true

          validates :coding_environment,
            inclusion: { in: CODING_ENVIRONMENTS }

          validates :environment,
            inclusion: { in: ENVIRONMENTS }

          validates :feature_maturity,
            presence: true,
            inclusion: { in: FEATURE_MATURITIES }

          validate :pre_approved_agent_privileges_granted

          validates :noteable_resolver, 'ai/catalog/resolver': { keywords: [:project, :goal] }
          validates :source_pipeline_resolver, 'ai/catalog/resolver': { keywords: [:project, :goal] }
          validates :additional_context_resolver, 'ai/catalog/resolver': { keywords: [:resource] }
          validates :flow_version_resolver, 'ai/catalog/resolver': { keywords: [:container, :user] }
          validates :goal_validator_resolver, 'ai/catalog/resolver': { keywords: [:container, :goal] }
          validates :ai_feature_resolver, 'ai/catalog/resolver': { keywords: [:current_user] }
          validates :before_start, 'ai/catalog/resolver': { keywords: [:resource] }
          validates :after_start, 'ai/catalog/resolver': { keywords: [:resource] }

          alias_method :reference, :foundational_flow_reference
        end

        private

        # Pre-approving an ungranted privilege would otherwise surface as a workflow
        # that fails to start, and only for flows someone happens to run. Failing
        # when the registry is first read surfaces the typo instead.
        def pre_approved_agent_privileges_granted
          extra = pre_approved_agent_privileges - agent_privileges
          return if extra.empty?

          errors.add(
            :pre_approved_agent_privileges,
            "contains privileges not in agent_privileges: #{extra.join(', ')}"
          )
        end
      end
    end
  end
end
