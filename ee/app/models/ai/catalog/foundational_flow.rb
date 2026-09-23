# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      include ActiveRecord::FixedItemsModel::Model
      include GlobalID::Identification
      include Gitlab::Utils::StrongMemoize
      include Ai::Catalog::FoundationalFlow::Attributes
      include Ai::Catalog::FoundationalFlow::Items

      register_flow(CodeReview::Definition)
      register_flow(RiskClassification::Definition)
      register_flow(SastFpDetection::Definition)
      register_flow(ResolveSastVulnerability::Definition)
      register_flow(Developer::Definition)
      register_flow(FixPipeline::Definition)
      register_flow(ConvertToGlCi::Definition)
      register_flow(RecommendReviewers::Definition)
      register_flow(SecretsFpDetection::Definition)
      register_flow(ResolveDependencyBump::Definition)
      register_flow(SecurityReview::Definition)
      register_flow(BusinessContextSecurityGuidelines::Definition)
      register_flow(Workplan::Definition)
      register_flow(ReadinessScore::Definition)
      register_flow(SlackAssistant::Definition)

      def self.find_by_reference(reference)
        find_by(foundational_flow_reference: reference)
      end

      def self.[](key)
        find_by(foundational_flow_reference: key) || find_by(display_name: key)
      end

      def self.beta?(foundational_flow_reference)
        flow = find_by(foundational_flow_reference: foundational_flow_reference)
        !!flow&.beta?
      end

      def self.ultimate_only?(foundational_flow_reference)
        flow = find_by(foundational_flow_reference: foundational_flow_reference)
        !!flow&.ultimate_only?
      end

      def self.code_review
        find_by!(foundational_flow_reference: 'code_review/v1')
      end

      def self.available_for_group(group)
        all.select { |flow| flow.available_for?(group) }
      end

      def available_for?(namespace)
        return false if beta? && !namespace.duo_beta_flows_enabled?
        return false if ultimate_only? && !namespace.licensed_feature_available?(:ai_features)

        !blocked_by_feature_flag?(namespace)
      end

      def beta?
        feature_maturity == 'beta'
      end

      def ultimate_only?
        Gitlab::Utils.to_boolean(ultimate_only)
      end

      def blocked_by_feature_flag?(group)
        return false if feature_flag.blank?

        # rubocop:disable Gitlab/FeatureFlagKeyDynamic -- Need to check the flag defined by flow dynamically.
        ::Feature.disabled?(feature_flag.to_sym, group)
        # rubocop:enable Gitlab/FeatureFlagKeyDynamic
      end

      def agent_privileges=(value)
        super(Array(value).map { |v| Integer(v) })
      end

      def pre_approved_agent_privileges=(value)
        super(value.nil? ? nil : Array(value).map { |v| Integer(v) })
      end

      # A flow that does not narrow its pre-approved set runs unattended, so every
      # granted privilege is pre-approved: pausing for an approval nobody can give
      # would just hang the flow.
      def pre_approved_agent_privileges
        super || agent_privileges
      end

      def resolve_noteable_for(project:, goal:)
        noteable_resolver&.call(project: project, goal: goal)
      end

      def resolve_source_pipeline_for(project:, goal:)
        source_pipeline_resolver&.call(project: project, goal: goal)
      end

      def validate_goal(container:, goal:)
        result = goal_validator_resolver&.call(container: container, goal: goal)
        return result if result.nil? || result.is_a?(ServiceResponse)

        raise ArgumentError, "goal_validator_resolver must return a ServiceResponse or nil, got #{result.class}"
      end

      # A flow that declares the resource types it accepts rejects a nil resource
      # too: every such flow reads the resource to build its goal.
      def supports_resource?(resource)
        return true if supported_resource_types.nil?

        supported_resource_types.any? { |type| resource.is_a?(type) }
      end

      def resolve_additional_context_for(resource:)
        with_supported_resource(resource, default: []) do
          context = additional_context_resolver&.call(resource: resource) || {}

          context.map do |category, fields|
            ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: category, fields: fields)
          end
        end
      end

      def resolve_ai_feature(current_user:)
        ai_feature_resolver&.call(current_user: current_user) || ai_feature
      end

      def run_before_start(resource:)
        with_supported_resource(resource) do
          before_start&.call(resource: resource)
        end
      end

      def run_after_start(resource:)
        with_supported_resource(resource) do
          after_start&.call(resource: resource)
        end
      end

      def resolve_flow_version_for(container:, user:)
        resolved_reference, resolved_version =
          flow_version_resolver&.call(container: container, user: user) || [foundational_flow_reference, flow_version]

        flow_config_id, flow_config_schema_version = resolved_reference.split('/', 2)

        {
          flow_config_id: flow_config_id,
          flow_config_schema_version: flow_config_schema_version,
          flow_version: resolved_version
        }
      end

      def translated_display_name
        # rubocop:disable Gettext/StaticIdentifier -- Translations available in `fixed_items`.
        s_("FoundationalFlow|#{display_name}") if display_name
        # rubocop:enable Gettext/StaticIdentifier
      end

      def translated_description
        # rubocop:disable Gettext/StaticIdentifier -- Translations available in `fixed_items`.
        s_("FoundationalFlow|#{description}") if description
        # rubocop:enable Gettext/StaticIdentifier
      end

      def catalog_item
        return if foundational_flow_reference.nil?

        Ai::Catalog::Item.with_foundational_flow_reference(foundational_flow_reference).first
      end
      strong_memoize_attr :catalog_item

      private

      def with_supported_resource(resource, default: nil)
        return default unless supports_resource?(resource)

        yield
      end
    end
  end
end
