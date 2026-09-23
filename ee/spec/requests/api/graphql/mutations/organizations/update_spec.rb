# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Organizations::Update, feature_category: :security_policy_management do
  include GraphqlHelpers

  include_context 'with the policy store experiment active'

  let_it_be_with_reload(:organization) { create(:organization) }
  let_it_be(:owner) { create(:user, owner_of: organization) }

  let(:current_user) { owner }
  let(:params) do
    {
      id: organization.to_global_id.to_s,
      policy_store_experiment_enabled: true
    }
  end

  let(:mutation) { graphql_mutation(:organization_update, params) }

  subject(:update_organization) { post_graphql_mutation(mutation, current_user: current_user) }

  def experiment_enabled?
    ::Organizations::OrganizationSetting.for(organization.id).policy_store_experiment_enabled
  end

  it 'opts the organization in to the Policy Store experiment' do
    update_organization

    expect(graphql_mutation_response(:organization_update)['errors']).to be_empty
    expect(experiment_enabled?).to be(true)
  end

  context 'when opting back out' do
    before do
      opt_organization_into_policy_store!(organization)
    end

    let(:params) { super().merge(policy_store_experiment_enabled: false) }

    it 'clears the setting' do
      update_organization

      expect(experiment_enabled?).to be(false)
    end
  end

  context 'when the experiment is not available to the organization' do
    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it 'returns an error without changing the setting when opting in' do
      update_organization

      expect(graphql_mutation_response(:organization_update)['errors'])
        .to contain_exactly('Policy Store experiment is not available for this organization')
      expect(experiment_enabled?).to be_nil
    end

    context 'when opting out' do
      before do
        opt_organization_into_policy_store!(organization)
      end

      let(:params) { super().merge(policy_store_experiment_enabled: false) }

      # A lapsed license or disabled flag must never strand an organization at
      # enabled, so opting out stays possible while the gates are closed.
      it 'clears the setting' do
        update_organization

        expect(graphql_mutation_response(:organization_update)['errors']).to be_empty
        expect(experiment_enabled?).to be(false)
      end
    end
  end

  context 'when the user is not an owner' do
    let(:current_user) do
      create(:user).tap { |user| create(:organization_user, organization: organization, user: user) }
    end

    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not change the setting' do
      update_organization

      expect(experiment_enabled?).to be_nil
    end
  end
end
