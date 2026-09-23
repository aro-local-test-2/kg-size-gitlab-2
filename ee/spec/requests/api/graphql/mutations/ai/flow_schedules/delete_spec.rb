# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::FlowSchedules::Delete, feature_category: :code_suggestions do
  include GraphqlHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project, :in_group, maintainers: maintainer) }
  let_it_be(:trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let!(:schedule) { create(:ai_flow_schedule, flow_trigger: trigger) }

  let(:current_user) { maintainer }
  let(:mutation) { graphql_mutation(:ai_flow_schedule_delete, params) }
  let(:params) do
    {
      id: schedule.to_global_id
    }
  end

  subject(:execute) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    stub_ee_application_setting(duo_features_enabled: true)
    ::Ai::Setting.for_organization(current_organization).update!(duo_core_features_enabled: true)
  end

  shared_examples 'an authorization failure' do
    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not delete the flow schedule' do
      expect { execute }.not_to change { Ai::FlowSchedule.count }
    end
  end

  context 'when user is a developer' do
    let(:current_user) { create(:user).tap { |user| project.add_developer(user) } }

    it_behaves_like 'an authorization failure'
  end

  context 'when the flow schedule does not exist' do
    let(:params) do
      {
        id: Gitlab::GlobalId.build(model_name: 'Ai::FlowSchedule', id: non_existing_record_id)
      }
    end

    it_behaves_like 'an authorization failure'
  end

  context 'when destroy fails' do
    before do
      allow_next_instance_of(::Ai::FlowSchedules::DestroyService) do |instance|
        allow(instance).to receive(:execute)
          .and_return(ServiceResponse.error(message: 'Failed to delete the flow schedule'))
      end
    end

    it 'returns the service error message' do
      execute

      expect(graphql_data_at(:ai_flow_schedule_delete, :errors))
        .to contain_exactly('Failed to delete the flow schedule')
    end
  end

  it 'destroys the flow schedule' do
    expect { execute }.to change { Ai::FlowSchedule.count }.by(-1)
  end

  it 'returns the deleted schedule' do
    execute

    expect(graphql_data_at(:ai_flow_schedule_delete, :ai_flow_schedule)).to match a_hash_including(
      'id' => schedule.to_global_id.to_s,
      'description' => schedule.description
    )
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_ai_flow_schedule do
    let(:user) { maintainer }
    let(:boundary_object) { project }
    let(:mutation) { graphql_mutation(:ai_flow_schedule_delete, params, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
