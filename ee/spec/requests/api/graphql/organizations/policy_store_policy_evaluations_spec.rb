# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization policyStore policyEvaluations', feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with the policy store experiment active'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_owner) { create(:organization_user, :owner, organization: organization).user }
  let_it_be(:organization_member) { create(:organization_user, organization: organization).user }

  let_it_be(:policy) { create(:govern_policy, :without_namespace, organization: organization) }
  let_it_be(:other_policy) { create(:govern_policy, :without_namespace, organization: organization) }

  let_it_be(:audit_allow_evaluation) do
    create(:govern_policy_evaluation, policy: policy, mode: :audit, verdict: :allow, evaluated_at: 3.days.ago)
  end

  let_it_be(:enforce_deny_evaluation) do
    create(:govern_policy_evaluation, policy: other_policy, mode: :enforce, verdict: :deny, evaluated_at: 1.day.ago)
  end

  let_it_be(:violation) do
    create(:govern_policy_violation, evaluation: enforce_deny_evaluation, details: { 'reason' => 'window closed' })
  end

  let_it_be(:other_organization_evaluation) { create(:govern_policy_evaluation) }

  let(:current_user) { organization_owner }
  let(:filters) { {} }
  let(:pagination) { {} }

  let(:query) do
    <<~QUERY
      query organizationPolicyStorePolicyEvaluations(
        $id: OrganizationsOrganizationID!, $policyId: Int, $mode: GovernPolicyEvaluationMode,
        $verdict: GovernPolicyEvaluationVerdict, $evaluatedAfter: Time, $evaluatedBefore: Time,
        $first: Int, $after: String
      ) {
        organization(id: $id) {
          policyStore {
            policyEvaluations(
              policyId: $policyId, mode: $mode, verdict: $verdict,
              evaluatedAfter: $evaluatedAfter, evaluatedBefore: $evaluatedBefore,
              first: $first, after: $after
            ) {
              pageInfo { hasNextPage endCursor }
              nodes {
                id
                policyId
                triggerType
                mode
                verdict
                policyVersion
                evaluatedAt
                projectId
                environmentId
                userId
                violations { id details createdAt }
              }
            }
          }
        }
      }
    QUERY
  end

  before do
    opt_organization_into_policy_store!(organization)
  end

  subject(:request) do
    post_graphql(
      query,
      current_user: current_user,
      variables: { id: organization.to_global_id.to_s }.merge(filters).merge(pagination)
    )
  end

  def policy_store
    graphql_data.dig('organization', 'policyStore')
  end

  def run_query
    post_graphql(query, current_user: current_user, variables: { id: organization.to_global_id.to_s })
  end

  def evaluations
    policy_store&.dig('policyEvaluations', 'nodes')
  end

  it 'returns the evaluations of the organization, newest first, with their violations' do
    request

    expect(evaluations).to match(
      [
        {
          'id' => enforce_deny_evaluation.to_global_id.to_s,
          'policyId' => other_policy.id,
          'triggerType' => 'DEPLOYMENT_REQUESTED',
          'mode' => 'ENFORCE',
          'verdict' => 'DENY',
          'policyVersion' => 1,
          'evaluatedAt' => enforce_deny_evaluation.evaluated_at.iso8601,
          'projectId' => nil,
          'environmentId' => nil,
          'userId' => nil,
          'violations' => [
            {
              'id' => violation.to_global_id.to_s,
              'details' => { 'reason' => 'window closed' },
              'createdAt' => violation.created_at.iso8601
            }
          ]
        },
        a_hash_including(
          'id' => audit_allow_evaluation.to_global_id.to_s,
          'mode' => 'AUDIT',
          'verdict' => 'ALLOW',
          'violations' => []
        )
      ]
    )
  end

  it 'avoids N+1 queries for violations' do
    run_query

    control = ActiveRecord::QueryRecorder.new { run_query }

    evaluation = create(:govern_policy_evaluation, policy: policy, evaluated_at: 2.days.ago)
    create(:govern_policy_violation, evaluation: evaluation)

    expect { run_query }.not_to exceed_query_limit(control)
  end

  describe 'filters' do
    context 'with a policyId filter' do
      let(:filters) { { policyId: policy.id } }

      it 'returns only the evaluations of the policy' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => audit_allow_evaluation.to_global_id.to_s)
        )
      end
    end

    context 'with a mode filter' do
      let(:filters) { { mode: 'ENFORCE' } }

      it 'returns only the evaluations that ran in the mode' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => enforce_deny_evaluation.to_global_id.to_s)
        )
      end
    end

    context 'with a verdict filter' do
      let(:filters) { { verdict: 'ALLOW' } }

      it 'returns only the evaluations that produced the verdict' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => audit_allow_evaluation.to_global_id.to_s)
        )
      end
    end

    context 'with a time range filter' do
      let(:filters) { { evaluatedAfter: 2.days.ago.iso8601, evaluatedBefore: Time.current.iso8601 } }

      it 'returns only the evaluations inside the range' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => enforce_deny_evaluation.to_global_id.to_s)
        )
      end
    end
  end

  describe 'pagination' do
    let(:pagination) { { first: 1 } }

    it 'paginates newest first with a usable cursor' do
      request

      expect(evaluations).to contain_exactly(
        a_hash_including('id' => enforce_deny_evaluation.to_global_id.to_s)
      )

      page_info = policy_store.dig('policyEvaluations', 'pageInfo')
      expect(page_info['hasNextPage']).to be(true)

      post_graphql(
        query,
        current_user: current_user,
        variables: { id: organization.to_global_id.to_s, first: 1, after: page_info['endCursor'] }
      )

      expect(evaluations).to contain_exactly(
        a_hash_including('id' => audit_allow_evaluation.to_global_id.to_s)
      )
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_govern_policy, :read_organization] do
    let_it_be(:granular_organization) { create(:organization) }
    let_it_be(:granular_policy) { create(:govern_policy, :without_namespace, organization: granular_organization) }

    # Without an evaluation the granted case would pass vacuously on an empty list.
    let_it_be(:granular_evaluation) { create(:govern_policy_evaluation, policy: granular_policy) }

    let(:user) { create(:organization_user, :owner, organization: granular_organization).user }
    let(:boundary_object) { :instance }
    let(:query) do
      <<~QUERY
        query organizationPolicyStorePolicyEvaluations($id: OrganizationsOrganizationID!) {
          organization(id: $id) {
            policyStore {
              policyEvaluations { nodes { verdict } }
            }
          }
        }
      QUERY
    end

    let(:request) do
      post_graphql(query, variables: { id: granular_organization.to_global_id.to_s },
        token: { personal_access_token: pat })
    end

    before do
      opt_organization_into_policy_store!(granular_organization)
    end
  end

  context 'when the user is an organization member without the owner role' do
    let(:current_user) { organization_member }

    it 'returns null evaluations while the catalogs stay reachable' do
      request

      expect(policy_store).to be_present
      expect(policy_store['policyEvaluations']).to be_nil
      expect_graphql_errors_to_be_empty
    end
  end

  describe 'count' do
    let(:query) do
      <<~QUERY
        query organizationPolicyStorePolicyEvaluations(
          $id: OrganizationsOrganizationID!, $policyId: Int, $verdict: GovernPolicyEvaluationVerdict,
          $evaluatedAfter: Time, $limit: Int
        ) {
          organization(id: $id) {
            policyStore {
              policyEvaluations(
                policyId: $policyId, verdict: $verdict, evaluatedAfter: $evaluatedAfter, first: 0
              ) {
                count(limit: $limit)
              }
            }
          }
        }
      QUERY
    end

    def count
      policy_store&.dig('policyEvaluations', 'count')
    end

    it 'counts every evaluation of the organization without fetching them' do
      request

      expect(count).to eq(2)
    end

    it 'counts only the evaluations the filters select' do
      post_graphql(
        query,
        current_user: current_user,
        variables: { id: organization.to_global_id.to_s, policyId: policy.id, verdict: 'ALLOW' }
      )

      expect(count).to eq(1)
    end

    it 'counts only the evaluations inside the given window' do
      post_graphql(
        query,
        current_user: current_user,
        variables: { id: organization.to_global_id.to_s, evaluatedAfter: 2.days.ago.iso8601 }
      )

      expect(count).to eq(1)
    end

    it 'counts the whole filtered relation, not the requested page' do
      post_graphql(
        query.sub('first: 0', 'first: 1'),
        current_user: current_user,
        variables: { id: organization.to_global_id.to_s }
      )

      expect(count).to eq(2)
    end

    context 'when the user cannot read the policies' do
      let(:current_user) { organization_member }

      it 'returns no connection to count rather than the number' do
        request

        expect(policy_store).to be_present
        expect(policy_store['policyEvaluations']).to be_nil
        expect_graphql_errors_to_be_empty
      end
    end

    # A bounded count returns limit + 1, which is what lets the UI render a
    # lower bound instead of paying for an exact count on a huge organization.
    context 'with more evaluations than the limit' do
      let_it_be(:third_evaluation) { create(:govern_policy_evaluation, policy: policy) }

      it 'counts them all when no limit is given' do
        request

        expect(count).to eq(3)
      end

      it 'stops counting at the given limit' do
        post_graphql(
          query,
          current_user: current_user,
          variables: { id: organization.to_global_id.to_s, limit: 1 }
        )

        expect(count).to eq(2)
      end
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it 'returns a null policyStore, so the flag works as a kill switch on its own' do
      request

      expect(policy_store).to be_nil
    end
  end
end
