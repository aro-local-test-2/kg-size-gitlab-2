# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project.mergeRequest.riskAssessment', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:current_user) { create(:user, developer_of: project) }

  let(:fields) do
    <<~QUERY
      riskAssessment {
        status
        risk
        confidence
        riskTier
        confidenceTier
        domainTags
        missingSignals {
          signal
          label
        }
        rationale
        assessedAt
        stale
        duoWorkflowId
        contributingSignals {
          signal
          label
          contribution
          detail
        }
      }
    QUERY
  end

  let(:query) do
    graphql_query_for(
      :project,
      { full_path: project.full_path },
      query_graphql_field(:merge_request, { iid: merge_request.iid.to_s }, fields)
    )
  end

  let(:risk_assessment_response) do
    graphql_data_at(:project, :merge_request, :risk_assessment)
  end

  before do
    allow_next_found_instance_of(Project) do |instance|
      allow(instance).to receive(:risk_classification_dap_available?).and_return(true)
    end
  end

  context 'when the merge request has no risk assessment' do
    it 'returns null' do
      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response).to be_nil
    end
  end

  context 'when the merge request has a persisted risk assessment' do
    let!(:risk_assessment) do
      create(:merge_requests_risk_assessment,
        merge_request: merge_request,
        score: 42,
        confidence: 80,
        domain_tags: %w[authentication],
        missing_signals: %w[test_coverage],
        rationale: 'Touches session handling without new test coverage.',
        assessed_at: Time.current,
        signal_breakdown: [
          { 'signal' => 'touches_auth', 'contribution' => 25.0, 'detail' => 'Modifies lib/auth.rb' }
        ]
      )
    end

    it 'resolves the persisted fields' do
      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response).to match a_hash_including(
        'status' => 'PENDING',
        'risk' => 42,
        'confidence' => 80,
        'domainTags' => %w[authentication],
        'rationale' => 'Touches session handling without new test coverage.',
        'missingSignals' => [
          a_hash_including(
            'signal' => 'test_coverage',
            'label' => 'Test coverage'
          )
        ],
        'contributingSignals' => [
          a_hash_including(
            'signal' => 'touches_auth',
            'contribution' => 25.0,
            'detail' => 'Modifies lib/auth.rb'
          )
        ]
      )
    end

    it 'resolves a signal_breakdown label from the registered signal class' do
      risk_assessment.update!(
        signal_breakdown: [
          { 'signal' => 'test_coverage.uncovered_lines', 'contribution' => 10.0 }
        ]
      )

      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response['contributingSignals']).to match([
        a_hash_including('signal' => 'test_coverage.uncovered_lines', 'label' => 'Uncovered changed lines')
      ])
    end

    it 'resolves a signal_breakdown label as null for a claim, which has no signal class' do
      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response['contributingSignals']).to match([
        a_hash_including('signal' => 'touches_auth', 'label' => nil)
      ])
    end

    it 'resolves a missing_signals label as null for a claim, which has no signal class' do
      risk_assessment.update!(missing_signals: %w[touches_auth])

      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response['missingSignals']).to match([
        a_hash_including('signal' => 'touches_auth', 'label' => nil)
      ])
    end

    it 'resolves riskTier from the score via the threshold bounds' do
      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response['riskTier']).to eq('MEDIUM')
    end

    it 'resolves confidenceTier from the confidence via the threshold bounds' do
      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response['confidenceTier']).to eq('CRITICAL')
    end

    context 'when the classification has not completed' do
      it 'resolves riskTier as null, since there is no score to derive it from' do
        risk_assessment.update!(score: nil)

        post_graphql(query, current_user: current_user)

        expect(risk_assessment_response['riskTier']).to be_nil
      end

      it 'resolves confidenceTier as null, since there is no confidence to derive it from' do
        risk_assessment.update!(confidence: nil)

        post_graphql(query, current_user: current_user)

        expect(risk_assessment_response['confidenceTier']).to be_nil
      end
    end

    it 'resolves duoWorkflowId as null when no session produced the classification' do
      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response['duoWorkflowId']).to be_nil
    end

    context 'when a Duo workflow session produced the classification' do
      it 'resolves duoWorkflowId to that session\'s ID' do
        workflow = create(:duo_workflows_workflow, project: project, user: current_user)
        risk_assessment.update!(duo_workflow: workflow)

        post_graphql(query, current_user: current_user)

        expect(risk_assessment_response['duoWorkflowId']).to eq(workflow.id)
      end
    end

    context 'when the merge request diff has not changed since assessment' do
      it 'resolves stale as false' do
        risk_assessment.update!(diff_sha: merge_request.diff_head_sha)

        post_graphql(query, current_user: current_user)

        expect(risk_assessment_response['stale']).to be(false)
      end
    end

    context 'when the merge request diff has changed since assessment' do
      it 'resolves stale as true' do
        post_graphql(query, current_user: current_user)

        expect(risk_assessment_response['stale']).to be(true)
      end
    end
  end

  context 'when the risk_classification/v1 flow is not available' do
    before do
      allow_next_found_instance_of(Project) do |instance|
        allow(instance).to receive(:risk_classification_dap_available?).and_return(false)
      end
    end

    let_it_be(:risk_assessment) { create(:merge_requests_risk_assessment, merge_request: merge_request) }

    it 'returns null' do
      post_graphql(query, current_user: current_user)

      expect(risk_assessment_response).to be_nil
    end
  end

  describe 'granular PAT authorization' do
    let(:user) { current_user }
    let(:boundary_object) { project }

    let_it_be(:risk_assessment) do
      create(:merge_requests_risk_assessment,
        merge_request: merge_request,
        signal_breakdown: [{ 'signal' => 'touches_auth', 'contribution' => 25.0 }],
        missing_signals: %w[touches_auth]
      )
    end

    context 'when querying the RiskAssessmentType child type' do
      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_merge_request] do
        let(:query) do
          graphql_query_for(:merge_request, { id: global_id_of(merge_request) }, 'riskAssessment { risk }')
        end

        let(:request) { post_graphql(query, current_user: user, token: { personal_access_token: pat }) }
        let(:skipped_data_path) { %i[merge_request risk_assessment] }
      end
    end

    context 'when querying the ContributingSignalType child type' do
      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_merge_request] do
        let(:query) do
          graphql_query_for(
            :merge_request, { id: global_id_of(merge_request) },
            'riskAssessment { contributingSignals { signal } }')
        end

        let(:request) { post_graphql(query, current_user: user, token: { personal_access_token: pat }) }
        let(:skipped_data_path) { %i[merge_request risk_assessment contributing_signals] }
      end
    end

    context 'when querying the MissingSignalType child type' do
      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_merge_request] do
        let(:query) do
          graphql_query_for(
            :merge_request, { id: global_id_of(merge_request) },
            'riskAssessment { missingSignals { signal } }')
        end

        let(:request) { post_graphql(query, current_user: user, token: { personal_access_token: pat }) }
        let(:skipped_data_path) { %i[merge_request risk_assessment missing_signals] }
      end
    end
  end

  describe 'N+1 queries for a merge_requests connection' do
    let_it_be(:catalog_item) { create(:ai_catalog_item, :risk_classification_v1) }

    let(:query) do
      graphql_query_for(
        :project,
        { full_path: project.full_path },
        query_graphql_field(:merge_requests, {}, 'nodes { iid riskAssessment { risk } }')
      )
    end

    before do
      # Exercise the real risk_classification_dap_available? check instead of the file-level stub above,
      # since this checks that enabled_flow_catalog_item_ids doesn't re-query per merge request.
      allow_next_found_instance_of(Project) do |instance|
        allow(instance).to receive(:risk_classification_dap_available?).and_call_original
      end

      stub_feature_flags(duo_mr_risk_classification: true)
      project.project_setting.update!(duo_foundational_flows_enabled: true)
      create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: catalog_item)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    end

    def create_merge_requests_with_risk_assessments(count)
      create_list(:merge_request, count, :unique_branches, source_project: project).each do |mr|
        create(:merge_requests_risk_assessment, merge_request: mr)
      end
    end

    it 'does not scale with the number of merge requests' do
      create_merge_requests_with_risk_assessments(1)

      post_graphql(query, current_user: current_user) # warm up to prevent undeterministic counts
      control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_graphql(query, current_user: current_user) }

      create_merge_requests_with_risk_assessments(3)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)
    end
  end
end
