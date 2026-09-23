# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow, feature_category: :duo_agent_platform do
  include I18nHelper
  using RSpec::Parameterized::TableSyntax

  shared_context 'with clean internal items cache' do
    around do |example|
      described_class.instance_variable_set(:@storage, nil)
      described_class.instance_variable_set(:@raw_items, nil)
      example.run
    ensure
      described_class.instance_variable_set(:@storage, nil)
      described_class.instance_variable_set(:@raw_items, nil)
    end
  end

  let(:code_review_description) do
    <<~DESC.squish
      Streamline code reviews by analyzing code changes and relevant codebase context.
      [How can I use this flow](https://docs.gitlab.com/user/duo_agent_platform/flows/foundational_flows/code_review/#use-the-flow)?
    DESC
  end

  let(:fr_translations) do
    {
      'FoundationalFlow|Code Review' => 'Code Review in French',
      "FoundationalFlow|#{code_review_description}" => 'Code Review description in French'
    }
  end

  describe '.fixed_items' do
    it 'does not translate display_name' do
      with_stubbed_translations(:fr, fr_translations) do
        expect(described_class['code_review/v1'].display_name)
          .to eq('Code Review')
      end
    end

    it 'does not translate description' do
      with_stubbed_translations(:fr, fr_translations) do
        expect(described_class['code_review/v1'].description).to eq(code_review_description)
      end
    end

    # Dormant today (no flow declares coding_environment: none yet) but prevents future
    # inconsistency. RUN_COMMANDS is deliberately absent from this list: an API-only flow
    # may still legitimately shell out to curl, jq or glab without a repository.
    it 'does not grant repository privileges to flows that declare coding_environment: none' do
      repository_privileges = [
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT,
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES
      ]

      offending = described_class.all.select do |flow|
        flow.coding_environment.to_s == 'none' &&
          (Array(flow.agent_privileges) & repository_privileges).any?
      end

      expect(offending).to be_empty,
        "Flows with coding_environment: 'none' get no repository checkout, so they must not " \
          "include USE_GIT or READ_WRITE_FILES in agent_privileges. " \
          "Offending flows: #{offending.map(&:foundational_flow_reference).join(', ')}"
    end
  end

  describe '.register_flow' do
    described_class.find_each do |flow|
      it "registers #{flow.foundational_flow_reference}" do
        accessor = flow.foundational_flow_reference.parameterize(separator: "_")
        expect(described_class.public_send(accessor)).to eq(flow)
      end
    end
  end

  describe 'coding_environment validation' do
    using RSpec::Parameterized::TableSyntax

    subject(:flow) { described_class.new(coding_environment: coding_environment) }

    where(:coding_environment, :valid) do
      'full' | true
      'none' | true
      'non'  | false
      ''     | false
    end

    with_them do
      it 'guards against unrecognised registry values' do
        flow.valid?

        expect(flow.errors[:coding_environment].present?).to eq(!valid)
      end
    end
  end

  describe 'pre_approved_agent_privileges validation' do
    using RSpec::Parameterized::TableSyntax

    subject(:flow) { described_class.new(agent_privileges: [2, 3], pre_approved_agent_privileges: pre_approved) }

    where(:pre_approved, :valid) do
      nil    | true
      []     | true
      [2]    | true
      [2, 3] | true
      [4]    | false
      [3, 4] | false
    end

    with_them do
      it 'rejects pre-approving a privilege the flow was never granted' do
        flow.valid?

        expect(flow.errors[:pre_approved_agent_privileges].present?).to eq(!valid)
      end
    end
  end

  describe '.[]' do
    subject(:definition) { described_class[key] }

    context 'with a valid foundational_flow_reference' do
      let(:key) { 'code_review/v1' }

      it { is_expected.to eq(described_class.find_by(foundational_flow_reference: key)) }
    end

    context 'with a valid display_name (for backward compatibility)' do
      let(:key) { 'Code Review' }

      it { is_expected.to eq(described_class.find_by(display_name: key)) }
    end

    context 'with a invalid key' do
      let(:key) { 'foo' }

      it { is_expected.to be_nil }
    end
  end

  describe '.beta?' do
    subject(:beta?) { described_class.beta?(foundational_flow_reference) }

    context 'when foundational flow is beta' do
      before do
        allow(described_class).to receive(:find_by)
          .with(foundational_flow_reference: 'some_beta_flow/v1')
          .and_return(instance_double(described_class, beta?: true))
      end

      let(:foundational_flow_reference) { 'some_beta_flow/v1' }

      it { is_expected.to be true }
    end

    context 'when foundational flow is GA' do
      let(:foundational_flow_reference) { 'code_review/v1' }

      it { is_expected.to be false }
    end

    context 'when foundational flow does not exist' do
      let(:foundational_flow_reference) { 'non_existent/v1' }

      it { is_expected.to be false }
    end
  end

  describe '.ultimate_only?' do
    subject(:ultimate_only?) { described_class.ultimate_only?(foundational_flow_reference) }

    context 'when foundational flow is ultimate-only' do
      let(:foundational_flow_reference) { 'resolve_sast_vulnerability/v1' }

      it { is_expected.to be true }
    end

    context 'when foundational flow is not ultimate-only' do
      let(:foundational_flow_reference) { 'code_review/v1' }

      it { is_expected.to be false }
    end

    context 'when foundational flow does not exist' do
      let(:foundational_flow_reference) { 'non_existent/v1' }

      it { is_expected.to be false }
    end
  end

  describe '#available_for?' do
    let(:namespace) { build_stubbed(:group) }
    let(:flow) { described_class['developer/v1'] }

    where(:beta, :beta_consent, :ultimate_only, :licensed, :flagged_off, :expected) do
      false | true  | false | true  | false | true
      true  | true  | false | true  | false | true
      true  | false | false | true  | false | false
      false | true  | true  | true  | false | true
      false | true  | true  | false | false | false
      false | true  | false | true  | true  | false
    end

    with_them do
      before do
        allow(namespace).to receive(:duo_beta_flows_enabled?).and_return(beta_consent)
        allow(namespace).to receive(:licensed_feature_available?).with(:ai_features).and_return(licensed)
        allow(flow).to receive_messages(beta?: beta, ultimate_only?: ultimate_only)
        allow(flow).to receive(:blocked_by_feature_flag?).with(namespace).and_return(flagged_off)
      end

      it { expect(flow.available_for?(namespace)).to be(expected) }
    end

    # duo_beta_flows_enabled? is defined on Namespace, so a personal namespace answers
    # rather than raising NoMethodError.
    context 'with a user namespace' do
      let(:namespace) { build_stubbed(:namespace) }

      it 'is true when the namespace is entitled to the flow' do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
        allow(namespace).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)

        expect(flow.available_for?(namespace)).to be(true)
      end
    end
  end

  describe '.available_for_group' do
    subject(:references) { described_class.available_for_group(group).map(&:foundational_flow_reference) }

    let(:group) { build_stubbed(:group) }

    context 'when beta flows are enabled for the group' do
      before do
        allow(group).to receive(:duo_beta_flows_enabled?).and_return(true)
        allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)
      end

      it 'includes beta flows' do
        expect(references).to include('recommend_reviewers/v1', 'security_review/v1')
      end

      it 'always includes GA flows' do
        expect(references).to include('code_review/v1', 'developer/v1')
      end
    end

    context 'when beta flows are not enabled for the group' do
      before do
        allow(group).to receive(:duo_beta_flows_enabled?).and_return(false)
        allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)
      end

      it 'excludes beta flows' do
        expect(references).not_to include('recommend_reviewers/v1', 'security_review/v1')
      end

      it 'always includes GA flows' do
        expect(references).to include('code_review/v1', 'developer/v1')
      end
    end

    context 'with ai_features license (Ultimate)' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
        allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)
      end

      it 'includes ultimate-only flows' do
        expect(references).to include('resolve_sast_vulnerability/v1', 'sast_fp_detection/v1')
      end
    end

    context 'without ai_features license (Free/Premium)' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
        allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(false)
      end

      it 'excludes ultimate-only flows' do
        expect(references).not_to include('resolve_sast_vulnerability/v1', 'sast_fp_detection/v1',
          'secrets_fp_detection/v1')
      end

      it 'includes non-ultimate GA flows' do
        expect(references).to include('code_review/v1', 'developer/v1')
      end
    end

    context 'with a feature-flag-gated flow' do
      include_context 'with clean internal items cache'

      let(:gated_flow_reference) { 'gated_flow/v1' }

      where(:flag_disabled) do
        [true, false]
      end

      with_them do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
          stub_application_setting(instance_level_ai_beta_features_enabled: false)
          allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)
          allow(described_class).to receive(:fixed_items).and_wrap_original do |original|
            original.call + [{
              foundational_flow_reference: gated_flow_reference,
              display_name: s_('FoundationalFlow|Gated Flow'),
              description: s_('FoundationalFlow|A flow behind a feature flag.'),
              feature_maturity: 'ga',
              feature_flag: 'my_gated_flow_flag'
            }]
          end
          allow(Feature).to receive(:disabled?).and_call_original
          allow(Feature).to receive(:disabled?).with(:my_gated_flow_flag, group).and_return(flag_disabled)
        end

        it 'includes the flow only when the feature flag is enabled' do
          expect(references.include?(gated_flow_reference)).to eq(!flag_disabled)
        end
      end
    end

    context 'when a flow has no feature_flag set' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
        allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)
      end

      it 'always includes the flow' do
        expect(references).to include('code_review/v1')
      end
    end
  end

  describe 'recommend_reviewers/v1' do
    subject(:flow) { described_class['recommend_reviewers/v1'] }

    it 'has additional_context_resolver defined' do
      expect(flow.additional_context_resolver).to be_present
    end

    it 'has the RecommendReviewers goal template' do
      expect(flow.goal_templates).to eq(::Ai::Catalog::GoalTemplates::RecommendReviewers)
    end

    it 'accepts merge requests only' do
      expect(flow.supported_resource_types).to eq([::MergeRequest])
    end

    describe 'additional_context_resolver' do
      let_it_be(:project) { create(:project) }

      it 'resolves reviewer data for a merge request' do
        merge_request = create(:merge_request, source_project: project, target_project: project)

        expect(flow.resolve_additional_context_for(resource: merge_request))
          .to contain_exactly(
            hash_including("Category" => "reviewer_data"),
            hash_including("Category" => "agent_platform_recommend_reviewers_context")
          )
      end

      it 'resolves to no context for a resource that is not a merge request' do
        expect(::Ai::DuoWorkflows::RecommendReviewers::ReviewerDataBuilder).not_to receive(:build)
        expect(flow.resolve_additional_context_for(resource: create(:issue, project: project))).to eq([])
      end
    end

    describe 'noteable_resolver' do
      let_it_be(:project) { create(:project) }
      let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

      it 'resolves the merge request matching the iid goal' do
        expect(flow.resolve_noteable_for(project: project, goal: merge_request.iid)).to eq(merge_request)
      end

      it 'resolves to nil when no merge request matches the goal' do
        expect(flow.resolve_noteable_for(project: project, goal: non_existing_record_iid)).to be_nil
      end
    end

    describe 'resolve_flow_version_for' do
      let_it_be(:project) { create(:project) }

      subject(:resolved) { flow.resolve_flow_version_for(container: project, user: nil) }

      context 'when recommend_reviewers_flow_v3 is disabled' do
        before do
          stub_feature_flags(recommend_reviewers_flow_v3: false)
        end

        it 'requests the default version 2.0.0' do
          expect(resolved).to eq(
            flow_config_id: 'recommend_reviewers',
            flow_config_schema_version: 'v1',
            flow_version: '2.0.0'
          )
        end
      end

      context 'when recommend_reviewers_flow_v3 is enabled for the project' do
        before do
          stub_feature_flags(recommend_reviewers_flow_v3: project)
        end

        it 'requests version 3.0.0' do
          expect(resolved).to eq(
            flow_config_id: 'recommend_reviewers',
            flow_config_schema_version: 'v1',
            flow_version: '^3.0.0'
          )
        end
      end
    end
  end

  describe 'fix_pipeline/v1' do
    subject(:flow) { described_class['fix_pipeline/v1'] }

    let_it_be(:project) { create(:project) }

    it 'has supported_events limited to pipeline_hooks' do
      expect(flow.supported_events).to eq([::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
    end

    it 'has a precondition requiring failed pipeline status' do
      expect(flow.precondition).to eq({
        'match' => 'all',
        'rules' => [
          { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'failed' }
        ]
      })
    end

    describe 'resolve_flow_version_for' do
      subject(:resolved) { flow.resolve_flow_version_for(container: project, user: nil) }

      context 'when fix_pipeline_experimental is disabled' do
        before do
          stub_feature_flags(fix_pipeline_experimental: false)
        end

        it 'returns the flow own reference and version' do
          expect(resolved).to eq(
            flow_config_id: 'fix_pipeline',
            flow_config_schema_version: 'v1',
            flow_version: '1.0.4'
          )
        end
      end

      context 'when fix_pipeline_experimental is enabled for the project' do
        before do
          stub_feature_flags(fix_pipeline_experimental: project)
        end

        it 'overrides to fix_pipeline/experimental' do
          expect(resolved).to eq(
            flow_config_id: 'fix_pipeline',
            flow_config_schema_version: 'experimental',
            flow_version: '1.0.0'
          )
        end
      end

      context 'when fix_pipeline_experimental is enabled for the root ancestor' do
        before do
          stub_feature_flags(fix_pipeline_experimental: project.root_ancestor)
        end

        it 'overrides to fix_pipeline/experimental' do
          expect(resolved).to eq(
            flow_config_id: 'fix_pipeline',
            flow_config_schema_version: 'experimental',
            flow_version: '1.0.0'
          )
        end
      end
    end
  end

  describe 'developer/v1' do
    subject(:flow) { described_class['developer/v1'] }

    let(:project) { build_stubbed(:project) }
    let_it_be(:user) { create(:user) }

    describe 'resolve_flow_version_for' do
      subject(:resolved) { flow.resolve_flow_version_for(container: project, user: user) }

      it 'returns the flow own reference and version' do
        expect(resolved).to eq(
          flow_config_id: 'developer',
          flow_config_schema_version: 'v1',
          flow_version: '^3.0.0'
        )
      end

      context 'when duo_developer_orbit is enabled and the orbit killswitch is on' do
        before do
          stub_feature_flags(duo_developer_orbit: user)
          user.user_preference.update!(orbit_settings: { 'enabled' => true })
        end

        it 'returns the flow own reference and version' do
          expect(resolved).to eq(
            flow_config_id: 'developer',
            flow_config_schema_version: 'v1',
            flow_version: '^3.0.0'
          )
        end
      end
    end
  end

  describe 'security_review/v1' do
    subject(:flow) { described_class['security_review/v1'] }

    it 'returns the security review foundational flow', :aggregate_failures do
      expect(flow.foundational_flow_reference).to eq('security_review/v1')
      expect(flow.display_name).to eq('Security Review')
      expect(flow.description).to eq('Review merge request code changes for business logic security vulnerabilities.')
      expect(flow.feature_maturity).to eq('beta')
      expect(flow.ai_feature).to eq('security_review')
      expect(flow.environment).to eq('web')
      expect(flow.ultimate_only).to be true
      expect(flow.suppress_mention_progress_note).to be true
    end

    it 'is beta' do
      expect(described_class.beta?('security_review/v1')).to be true
    end

    it 'is ultimate-only' do
      expect(described_class.ultimate_only?('security_review/v1')).to be true
    end
  end

  describe 'flows that disallow event triggers' do
    where(:foundational_flow_reference) do
      %w[resolve_sast_vulnerability/v1 sast_fp_detection/v1 secrets_fp_detection/v1]
    end

    with_them do
      it 'has supported_events set to an empty array' do
        expect(described_class[foundational_flow_reference].supported_events).to eq([])
      end
    end
  end

  describe 'resolve_dependency_bump/experimental' do
    subject(:flow) { described_class['resolve_dependency_bump/experimental'] }

    it 'supports the mention trigger' do
      expect(flow.triggers).to include(::Ai::FlowTrigger::EVENT_TYPES[:mention])
    end

    it 'has a goal template' do
      expect(flow.goal_templates).to eq(::Ai::Catalog::GoalTemplates::ResolveDependencyBump)
    end

    it 'allows any event type (supported_events is nil)' do
      expect(flow.supported_events).to be_nil
    end
  end

  describe 'business_context_security_guidelines/experimental' do
    subject(:flow) { described_class['business_context_security_guidelines/experimental'] }

    it 'is gated by the sdlc_context_agent_trigger feature flag' do
      expect(flow.feature_flag).to eq('sdlc_context_agent_trigger')
    end

    it 'has no triggers and supports no trigger events' do
      expect(flow.triggers).to be_empty
      expect(flow.supported_events).to eq([])
    end
  end

  describe '.code_review' do
    subject(:code_review) { described_class.code_review }

    it 'returns the code review foundational flow' do
      expect(code_review.foundational_flow_reference).to eq('code_review/v1')
      expect(code_review.display_name).to eq('Code Review')
      expect(code_review.ai_feature).to eq('review_merge_request_dap')
      expect(code_review.feature_maturity).to eq('ga')
    end
  end

  describe '#supports_resource?' do
    let_it_be(:project) { create(:project) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

    context 'when the flow declares no supported_resource_types' do
      subject(:flow) { described_class['convert_to_gl_ci/v1'] }

      it 'accepts any resource, including none' do
        expect(flow.supports_resource?(merge_request)).to be(true)
        expect(flow.supports_resource?(create(:issue, project: project))).to be(true)
        expect(flow.supports_resource?(nil)).to be(true)
      end
    end

    context 'when the flow declares supported_resource_types' do
      subject(:flow) { described_class['recommend_reviewers/v1'] }

      it 'accepts a declared resource type' do
        expect(flow.supports_resource?(merge_request)).to be(true)
      end

      it 'rejects an undeclared resource type and a missing resource' do
        expect(flow.supports_resource?(create(:issue, project: project))).to be(false)
        expect(flow.supports_resource?(nil)).to be(false)
      end
    end

    context 'when the flow declares an empty supported_resource_types' do
      subject(:flow) { described_class.new(supported_resource_types: []) }

      it 'rejects every resource' do
        expect(flow.supports_resource?(merge_request)).to be(false)
        expect(flow.supports_resource?(nil)).to be(false)
      end
    end
  end

  describe 'supported_resource_types declarations' do
    # Guarded here rather than by a model validation: an invalid definition makes
    # load_items! raise on first access and then leave the catalog permanently
    # truncated, taking unrelated flows with it.
    it 'is nil or an array of classes for every flow' do
      invalid = described_class.all.reject do |flow|
        types = flow.supported_resource_types
        types.nil? || (types.is_a?(Array) && types.all?(Class))
      end

      expect(invalid.map(&:foundational_flow_reference)).to be_empty
    end
  end

  describe '#validate_goal' do
    let_it_be(:project) { create(:project) }

    context 'when the flow has no goal_validator_resolver' do
      let(:flow) { described_class['convert_to_gl_ci/v1'] }

      it 'returns nil' do
        expect(flow.validate_goal(container: project, goal: 'any goal')).to be_nil
      end
    end

    context 'when the flow is code review' do
      let(:flow) { described_class['code_review/v1'] }
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }

      it 'returns a success with the normalized goal for an IID goal' do
        response = flow.validate_goal(container: project, goal: merge_request.iid.to_s)

        expect(response).to be_success
        expect(response.payload[:goal]).to eq(merge_request.iid.to_s)
      end

      it 'normalizes a merge request URL goal to the IID' do
        url = Gitlab::Routing.url_helpers.project_merge_request_url(project, merge_request)
        response = flow.validate_goal(container: project, goal: "#{url}/diffs#note_123")

        expect(response).to be_success
        expect(response.payload[:goal]).to eq(merge_request.iid.to_s)
      end

      it 'returns an error when the goal is not a merge request identifier', :aggregate_failures do
        response = flow.validate_goal(container: project, goal: 'Review my merge request')

        expect(response).to be_error
        expect(response.message).to include('must be a merge request IID')
        expect(response.reason).to eq(:invalid_goal)
      end

      it 'returns an error when no merge request matches the IID' do
        expect(flow.validate_goal(container: project, goal: non_existing_record_iid.to_s)).to be_error
      end

      it 'returns an error when the container is not a project', :aggregate_failures do
        response = flow.validate_goal(container: build(:group), goal: merge_request.iid.to_s)

        expect(response).to be_error
        expect(response.message).to include('require a project context')
        expect(response.reason).to eq(:invalid_goal)
      end
    end

    context 'when the resolver returns something other than a ServiceResponse' do
      let(:flow) { described_class['code_review/v1'] }

      it 'raises an ArgumentError' do
        allow(flow).to receive(:goal_validator_resolver).and_return(->(**) { true })

        expect { flow.validate_goal(container: project, goal: '1') }
          .to raise_error(ArgumentError, /must return a ServiceResponse or nil, got TrueClass/)
      end
    end
  end

  describe '#run_before_start' do
    let(:resource) { instance_double(::MergeRequest) }
    let(:calls) { [] }

    context 'when flow declares no callback' do
      it 'is a no-op' do
        expect(described_class.new.run_before_start(resource: resource)).to be_nil
      end
    end

    context 'when flow declares a callback' do
      it 'hands the resource to the callback' do
        flow = described_class.new(before_start: ->(resource:) { calls << resource })

        flow.run_before_start(resource: resource)

        expect(calls).to eq([resource])
      end

      it 'skips a resource type the flow does not declare' do
        flow = described_class.new(
          before_start: ->(resource:) { calls << resource },
          supported_resource_types: [::Issue]
        )

        flow.run_before_start(resource: resource)

        expect(calls).to be_empty
      end
    end
  end

  describe '#run_after_start' do
    let(:resource) { instance_double(::MergeRequest) }
    let(:calls) { [] }

    context 'when flow declares no callback' do
      it 'is a no-op' do
        expect(described_class.new.run_after_start(resource: resource)).to be_nil
      end
    end

    context 'when flow declares a callback' do
      it 'hands the resource to the callback' do
        flow = described_class.new(after_start: ->(resource:) { calls << resource })

        flow.run_after_start(resource: resource)

        expect(calls).to eq([resource])
      end

      it 'skips a resource type the flow does not declare' do
        flow = described_class.new(
          after_start: ->(resource:) { calls << resource },
          supported_resource_types: [::Issue]
        )

        flow.run_after_start(resource: resource)

        expect(calls).to be_empty
      end
    end
  end

  describe '#resolve_noteable_for' do
    let_it_be(:project) { create(:project) }

    context 'when the flow has no noteable_resolver' do
      let(:flow) { described_class['convert_to_gl_ci/v1'] }

      it 'returns nil' do
        expect(flow.resolve_noteable_for(project: project, goal: 'https://gitlab.com/-/pipelines/1')).to be_nil
      end
    end

    context 'when the flow is code review' do
      let(:flow) { described_class['code_review/v1'] }
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }

      it 'returns the merge request matching the iid goal' do
        expect(flow.resolve_noteable_for(project: project, goal: merge_request.iid)).to eq(merge_request)
      end

      it 'returns nil when no merge request matches the goal' do
        expect(flow.resolve_noteable_for(project: project, goal: non_existing_record_iid)).to be_nil
      end
    end

    context 'when the flow has noteable_resolver defined' do
      let(:flow) { described_class['fix_pipeline/v1'] }

      context 'with a valid pipeline URL for a merge request pipeline' do
        let_it_be(:merge_request) { create(:merge_request, source_project: project) }
        let_it_be(:pipeline) do
          create(:ci_pipeline, project: project, merge_request: merge_request)
        end

        let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

        it 'returns the merge request' do
          expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(merge_request)
        end
      end

      context 'when the pipeline is associated with a merged merge request' do
        let_it_be(:merge_request) { create(:merge_request, :merged, source_project: project) }
        let_it_be(:pipeline) do
          create(:ci_pipeline, project: project, merge_request: merge_request)
        end

        let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

        it 'returns nil' do
          expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
        end
      end

      context 'when the pipeline has no associated merge request' do
        let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
        let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

        it 'returns nil' do
          expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
        end
      end

      context 'when a branch pipeline has an open merge request for its branch' do
        let_it_be(:project) { create(:project, :repository) }
        let_it_be(:merge_request) do
          create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master')
        end

        let_it_be(:pipeline) do
          create(:ci_pipeline, project: project, ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
        end

        let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

        it 'returns the merge request for the pipeline ref' do
          expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(merge_request)
        end
      end

      context 'when the merge request for the branch is closed' do
        let_it_be(:project) { create(:project, :repository) }
        let_it_be(:merge_request) do
          create(:merge_request, :closed, source_project: project, source_branch: 'feature', target_branch: 'master')
        end

        let_it_be(:pipeline) do
          create(:ci_pipeline, project: project, ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
        end

        let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

        it 'returns nil' do
          expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
        end
      end

      context 'with a malformed goal URL' do
        it 'returns nil' do
          expect(flow.resolve_noteable_for(project: project, goal: 'not-a-url')).to be_nil
        end
      end

      context 'with a nil goal' do
        it 'returns nil' do
          expect(flow.resolve_noteable_for(project: project, goal: nil)).to be_nil
        end
      end

      context 'when the pipeline belongs to a different project' do
        let_it_be(:other_project) { create(:project) }
        let_it_be(:other_pipeline) { create(:ci_pipeline, project: other_project) }
        let(:goal) { "https://gitlab.com/#{other_project.full_path}/-/pipelines/#{other_pipeline.id}" }

        it 'returns nil because the pipeline is scoped to the given project' do
          expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
        end
      end
    end

    context 'when the flow is workplan' do
      let(:flow) { described_class['workplan/v1'] }
      let_it_be(:work_item) { create(:work_item, project: project) }

      it 'returns the work item matching the URL embedded in the goal' do
        goal = "Plan this: #{Gitlab::UrlBuilder.build(work_item)} thanks"

        expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
      end

      it 'resolves the legacy issues URL form' do
        goal = "See https://gitlab.com/#{project.full_path}/-/issues/#{work_item.iid}"

        expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
      end

      it 'returns nil for a malformed goal' do
        expect(flow.resolve_noteable_for(project: project, goal: 'not-a-url')).to be_nil
      end

      it 'returns nil for a nil goal' do
        expect(flow.resolve_noteable_for(project: project, goal: nil)).to be_nil
      end
    end

    context 'when the flow is readiness_score' do
      let(:flow) { described_class['readiness_score/v1'] }
      let_it_be(:work_item) { create(:work_item, project: project) }

      it 'returns the work item matching the URL embedded in the goal' do
        goal = "Score this: #{Gitlab::UrlBuilder.build(work_item)} thanks"

        expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
      end

      it 'resolves the legacy issues URL form' do
        goal = "See https://gitlab.com/#{project.full_path}/-/issues/#{work_item.iid}"

        expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
      end

      it 'returns nil for a malformed goal' do
        expect(flow.resolve_noteable_for(project: project, goal: 'not-a-url')).to be_nil
      end

      it 'returns nil for a nil goal' do
        expect(flow.resolve_noteable_for(project: project, goal: nil)).to be_nil
      end
    end
  end

  describe '#resolve_source_pipeline_for' do
    let_it_be(:project) { create(:project) }

    context 'when the flow has no source_pipeline_resolver' do
      let(:flow) { described_class['convert_to_gl_ci/v1'] }

      it 'returns nil' do
        expect(flow.resolve_source_pipeline_for(project: project, goal: 'https://gitlab.com/-/pipelines/1')).to be_nil
      end
    end

    context 'when the flow is fix_pipeline' do
      let(:flow) { described_class['fix_pipeline/v1'] }

      context 'with a valid pipeline URL' do
        let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
        let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

        it 'returns the pipeline' do
          expect(flow.resolve_source_pipeline_for(project: project, goal: goal)).to eq(pipeline)
        end
      end

      context 'with a malformed goal URL' do
        it 'returns nil' do
          expect(flow.resolve_source_pipeline_for(project: project, goal: 'not-a-url')).to be_nil
        end
      end

      context 'with a nil goal' do
        it 'returns nil' do
          expect(flow.resolve_source_pipeline_for(project: project, goal: nil)).to be_nil
        end
      end

      context 'when the pipeline belongs to a different project' do
        let_it_be(:other_project) { create(:project) }
        let_it_be(:other_pipeline) { create(:ci_pipeline, project: other_project) }
        let(:goal) { "https://gitlab.com/#{other_project.full_path}/-/pipelines/#{other_pipeline.id}" }

        it 'returns nil because the pipeline is scoped to the given project' do
          expect(flow.resolve_source_pipeline_for(project: project, goal: goal)).to be_nil
        end
      end
    end
  end

  describe '#resolve_additional_context_for' do
    let(:resource) { instance_double(::MergeRequest, id: 42) }
    let(:resolver) { nil }
    let(:flow) { described_class.new(additional_context_resolver: resolver) }

    subject(:additional_context) { flow.resolve_additional_context_for(resource: resource) }

    context 'when the flow has no additional_context_resolver' do
      it 'returns an empty array' do
        expect(additional_context).to eq([])
      end
    end

    context 'when additional_context_resolver is a lambda' do
      let(:resolver) do
        ->(resource:) do
          {
            "resource" => {
              type: "merge_request",
              id: resource.id
            }
          }
        end
      end

      it 'returns the resolved additional context formatted for AIGW' do
        expect(additional_context).to eq([
          {
            "Category" => "resource",
            "Content" => {
              type: "merge_request",
              id: resource.id
            }.to_json
          }
        ])
      end
    end

    context 'when additional_context_resolver is a Module' do
      let(:resolver) do
        Module.new do
          module_function

          def call(resource:)
            {
              "resource" => {
                type: "merge_request",
                id: resource.id
              }
            }
          end
        end
      end

      it 'returns the resolved additional context formatted for AIGW' do
        expect(additional_context).to eq([
          {
            "Category" => "resource",
            "Content" => {
              type: "merge_request",
              id: resource.id
            }.to_json
          }
        ])
      end
    end

    context 'when the flow declares supported_resource_types' do
      let(:resource) { build_stubbed(:merge_request) }
      let(:unsupported) { build_stubbed(:issue) }

      let(:resolver) { ->(resource:) { { "resource" => { id: resource.id } } } }
      let(:flow) do
        described_class.new(additional_context_resolver: resolver, supported_resource_types: [::MergeRequest])
      end

      it 'resolves context for a supported resource' do
        expect(flow.resolve_additional_context_for(resource: resource))
          .to contain_exactly(hash_including("Category" => "resource"))
      end

      it 'returns an empty array for an unsupported resource' do
        expect(flow.resolve_additional_context_for(resource: unsupported)).to eq([])
      end
    end

    context 'with the code_review/v1 flow' do
      let_it_be(:merge_request) { create(:merge_request) }

      let(:review_bot) do
        ::Users::Internal.in_organization(merge_request.project.organization_id).duo_code_review_bot
      end

      subject(:code_review_context) do
        described_class['code_review/v1'].resolve_additional_context_for(resource: resource)
      end

      context 'when the resource is not a merge request' do
        let(:resource) { create(:issue) }

        it 'resolves to no context without looking the bot up' do
          expect(::Users::Internal).not_to receive(:in_organization)

          expect(code_review_context).to eq([])
        end
      end

      context 'when the resource is a merge request' do
        let(:resource) { merge_request }

        before do
          allow(merge_request).to receive(:duo_code_review_last_reviewed_head_sha)
            .with(review_bot).and_return(last_reviewed_head_sha)
        end

        context 'when the bot reviewed the merge request before' do
          let(:last_reviewed_head_sha) { 'abc123' }

          it 'returns the username of the Duo Code Review bot and the last reviewed head sha' do
            expect(code_review_context).to eq([
              {
                "Category" => "code_review_context",
                "Content" => {
                  "duo_code_review_bot_name" => review_bot.username,
                  "last_reviewed_head_sha" => 'abc123'
                }.to_json
              }
            ])
          end
        end

        context 'when the bot did not review the merge request before' do
          let(:last_reviewed_head_sha) { nil }

          it 'omits the last reviewed head sha' do
            expect(code_review_context).to eq([
              {
                "Category" => "code_review_context",
                "Content" => { "duo_code_review_bot_name" => review_bot.username }.to_json
              }
            ])
          end
        end
      end
    end
  end

  describe '#resolve_flow_version_for' do
    let(:container) { build_stubbed(:project) }
    let(:user) { build_stubbed(:user) }
    let(:resolver) { nil }
    let(:flow) do
      described_class.new(
        foundational_flow_reference: 'developer/v1',
        flow_version: '^2.0.0',
        flow_version_resolver: resolver
      )
    end

    subject(:resolved) { flow.resolve_flow_version_for(container: container, user: user) }

    context 'when the flow has no flow_version_resolver' do
      it 'returns the flow own reference and version' do
        expect(resolved).to eq(
          flow_config_id: 'developer',
          flow_config_schema_version: 'v1',
          flow_version: '^2.0.0'
        )
      end
    end

    context 'when the flow_version_resolver returns an override' do
      let(:resolver) { ->(**) { ['developer/experimental', '3.0.0'] } }

      it 'returns the overridden reference and version' do
        expect(resolved).to eq(
          flow_config_id: 'developer',
          flow_config_schema_version: 'experimental',
          flow_version: '3.0.0'
        )
      end
    end

    context 'when the flow_version_resolver declines to override' do
      let(:resolver) { ->(**) {} }

      it 'falls back to the flow own reference and version' do
        expect(resolved).to eq(
          flow_config_id: 'developer',
          flow_config_schema_version: 'v1',
          flow_version: '^2.0.0'
        )
      end
    end
  end

  describe 'workplan/v1' do
    subject(:flow) { described_class['workplan/v1'] }

    it 'returns the workplan foundational flow', :aggregate_failures do
      expect(flow.foundational_flow_reference).to eq('workplan/v1')
      expect(flow.display_name).to eq('Generate Workplan')
      expect(flow.feature_maturity).to eq('experimental')
      expect(flow.environment).to eq('web')
      expect(flow.goal_templates).to eq(::Ai::Catalog::GoalTemplates::Workplan)
      expect(flow.noteable_resolver).to be_present
    end

    it 'grants GitLab read/write privileges and allows starting flows', :aggregate_failures do
      expect(flow.agent_privileges).to eq([
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
      ])
    end

    it 'is gated by the duo_workplan_async_flow feature flag' do
      expect(flow.feature_flag).to eq('duo_workplan_async_flow')
    end

    it 'has no triggers and supports no trigger events', :aggregate_failures do
      expect(flow.triggers).to be_empty
      expect(flow.supported_events).to eq([])
    end
  end

  describe 'readiness_score/v1' do
    subject(:flow) { described_class['readiness_score/v1'] }

    it 'returns the readiness score foundational flow', :aggregate_failures do
      expect(flow).to have_attributes(
        foundational_flow_reference: 'readiness_score/v1',
        display_name: 'Readiness Score',
        feature_maturity: 'experimental',
        environment: 'web',
        goal_templates: ::Ai::Catalog::GoalTemplates::ReadinessScore,
        noteable_resolver: be_present
      )
    end

    it 'reads and writes GitLab only', :aggregate_failures do
      expect(flow.agent_privileges).to eq([
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
      ])
    end

    it 'is gated by the workplan_score feature flag' do
      expect(flow.feature_flag).to eq('workplan_score')
    end

    it 'has no triggers and supports no trigger events', :aggregate_failures do
      expect(flow.triggers).to be_empty
      expect(flow.supported_events).to eq([])
    end
  end

  describe 'slack_assistant/v1' do
    subject(:flow) { described_class['slack_assistant/v1'] }

    it 'pre-approves reads only, so writes and flow starts need approval', :aggregate_failures do
      expect(flow.agent_privileges).to eq([
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
      ])
      expect(flow.pre_approved_agent_privileges).to eq([
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB
      ])
    end

    # The Duo Workflow Service drops an admin's `ask` rules for a flow that
    # cannot reach its user, so this has to be true for those rules to apply.
    it 'can pause to ask its user' do
      expect(flow.allow_agent_to_request_user).to be true
    end
  end

  describe '#beta?' do
    it 'returns true for a beta flow' do
      expect(described_class.new(feature_maturity: 'beta').beta?).to be true
    end

    it 'returns false for a GA flow' do
      expect(described_class.new(feature_maturity: 'ga').beta?).to be false
    end
  end

  describe '#ultimate_only?' do
    it 'returns true for an ultimate-only flow' do
      expect(described_class['resolve_sast_vulnerability/v1'].ultimate_only?).to be true
    end

    it 'returns false for a non-ultimate-only flow' do
      expect(described_class['code_review/v1'].ultimate_only?).to be false
    end
  end

  describe '#agent_privileges' do
    subject(:agent_privileges) { definition.agent_privileges }

    context 'when agent_privileges are not set' do
      let(:definition) { described_class.new(agent_privileges: nil) }

      it 'returns the default value' do
        expect(agent_privileges).to eq([])
      end
    end

    context 'with agent_privileges' do
      let(:definition) { described_class.new(agent_privileges: [1, 2]) }

      it 'returns the agent_privileges' do
        expect(agent_privileges).to match_array([1, 2])
      end
    end
  end

  describe '#pre_approved_agent_privileges' do
    subject(:pre_approved_agent_privileges) { definition.pre_approved_agent_privileges }

    context 'when pre_approved_agent_privileges are not set' do
      let(:definition) { described_class.new(agent_privileges: [1, 2]) }

      it 'pre-approves every granted privilege' do
        expect(pre_approved_agent_privileges).to match_array([1, 2])
      end
    end

    context 'with a narrowed pre_approved_agent_privileges' do
      let(:definition) { described_class.new(agent_privileges: [1, 2], pre_approved_agent_privileges: %w[1]) }

      it 'returns the narrowed set, coerced to integers' do
        expect(pre_approved_agent_privileges).to eq([1])
      end
    end

    context 'with an empty pre_approved_agent_privileges' do
      let(:definition) { described_class.new(agent_privileges: [1, 2], pre_approved_agent_privileges: []) }

      it 'pre-approves nothing rather than falling back to the granted set' do
        expect(pre_approved_agent_privileges).to eq([])
      end
    end
  end

  describe '#catalog_item' do
    subject(:catalog_item) { definition.catalog_item }

    context 'with foundational_flow_reference' do
      let_it_be(:definition) { described_class.new(foundational_flow_reference: 'code_review') }
      let_it_be(:duo_code_review) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'code_review')
      end

      it 'returns the corresponding foundational workflow catalog item' do
        expect(catalog_item).to eq(duo_code_review)
      end
    end

    context 'without foundational_flow_reference' do
      let_it_be(:definition) { described_class.new(foundational_flow_reference: nil) }

      it 'returns nil' do
        expect(catalog_item).to be_nil
      end
    end

    context 'when the corresponding foundational workflow does not exist' do
      let_it_be(:definition) { described_class.new(foundational_flow_reference: 'code_review') }

      it 'returns nil' do
        expect(catalog_item).to be_nil
      end
    end
  end

  describe '#display_name' do
    subject(:display_name) { definition.display_name }

    let(:definition) { described_class['code_review/v1'] }

    it 'does not translate if locale is not English' do
      with_stubbed_translations(:fr, fr_translations) do
        expect(display_name).to eq('Code Review')
      end
    end
  end

  describe '#description' do
    subject(:description) { definition.description }

    let(:definition) { described_class['code_review/v1'] }

    it 'does not translate if locale is not English' do
      with_stubbed_translations(:fr, fr_translations) do
        expect(description).to eq(code_review_description)
      end
    end
  end

  describe '#reference' do
    it 'aliases foundational_flow_reference' do
      flow = described_class.new(foundational_flow_reference: 'code_review/v1')

      expect(flow.reference).to eq('code_review/v1')
    end
  end

  describe '#translated_display_name' do
    subject(:translated_display_name) { definition.translated_display_name }

    let(:definition) { described_class['code_review/v1'] }

    context 'when the locale is English' do
      it 'returns the English display_name' do
        Gitlab::I18n.with_locale(:en) do
          expect(translated_display_name).to eq('Code Review')
        end
      end
    end

    context 'when the locale is not English' do
      it 'returns the translated display_name' do
        with_stubbed_translations(:fr, fr_translations) do
          expect(translated_display_name).to eq('Code Review in French')
        end
      end
    end
  end

  describe '#translated_description' do
    subject(:translated_description) { definition.translated_description }

    let(:definition) { described_class['code_review/v1'] }

    context 'when the locale is English' do
      it 'returns the English description' do
        Gitlab::I18n.with_locale(:en) do
          expect(translated_description).to eq(code_review_description)
        end
      end
    end

    context 'when the locale is not English' do
      it 'returns the translation description' do
        with_stubbed_translations(:fr, fr_translations) do
          expect(translated_description)
            .to eq('Code Review description in French')
        end
      end
    end
  end

  describe '#resolve_ai_feature' do
    subject(:resolved_ai_feature) do
      described_class[foundational_flow_reference].resolve_ai_feature(current_user: current_user)
    end

    let_it_be(:current_user) { build_stubbed(:user) }

    where(:foundational_flow_reference, :ai_feature) do
      'business_context_security_guidelines/experimental'   | 'duo_agent_platform'
      'code_review/v1'                                      | 'review_merge_request_dap'
      'convert_to_gl_ci/v1'                                 | 'duo_agent_platform'
      'developer/v1'                                        | 'duo_developer'
      'fix_pipeline/v1'                                     | 'duo_agent_platform'
      'recommend_reviewers/v1'                              | 'duo_agent_platform'
      'resolve_dependency_bump/experimental'                | 'resolve_dependency_bump'
      'resolve_sast_vulnerability/v1'                       | 'sast_vulnerability_resolution'
      'risk_classification/v1'                              | 'duo_agent_platform'
      'sast_fp_detection/v1'                                | 'sast_vulnerability_fp_detection'
      'secrets_fp_detection/v1'                             | 'secret_vulnerability_fp_detection'
      'security_review/v1'                                  | 'security_review'
      'workplan/v1'                                         | 'duo_agent_platform'
    end

    with_them do
      it 'resolves the expected ai_feature' do
        expect(resolved_ai_feature).to eq(ai_feature)
      end
    end
  end
end
