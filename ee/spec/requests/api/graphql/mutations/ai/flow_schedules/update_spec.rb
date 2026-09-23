# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::FlowSchedules::Update, feature_category: :code_suggestions do
  include GraphqlHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project, :in_group, maintainers: maintainer) }
  let_it_be(:trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let_it_be_with_reload(:schedule) do
    create(:ai_flow_schedule, flow_trigger: trigger, description: 'Old', cron: '0 9 * * 1')
  end

  let(:current_user) { maintainer }
  let(:mutation) { graphql_mutation(:ai_flow_schedule_update, params) }
  let(:params) do
    {
      id: schedule.to_global_id,
      description: 'New',
      cron: '30 21 * * *',
      active: false
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

    it 'does not modify the schedule' do
      expect { execute }.not_to change { schedule.reload.attributes }
    end
  end

  context 'when user is a developer' do
    let(:current_user) { create(:user).tap { |user| project.add_developer(user) } }

    it_behaves_like 'an authorization failure'
  end

  context 'when the flow schedule does not exist' do
    let(:params) do
      { id: Gitlab::GlobalId.build(model_name: 'Ai::FlowSchedule', id: non_existing_record_id), description: 'New' }
    end

    it_behaves_like 'an authorization failure'
  end

  context 'when model params are invalid' do
    let(:params) { super().merge(cron: 'not a cron') }

    it 'returns the validation error' do
      execute

      expect(graphql_data_at(:ai_flow_schedule_update, :errors).first).to include('Cron syntax is invalid')
      expect(graphql_data_at(:ai_flow_schedule_update, :ai_flow_schedule)).to be_nil
    end
  end

  it 'updates the flow schedule' do
    execute

    expect(schedule.reload).to have_attributes(
      description: 'New',
      cron: '30 21 * * *',
      active: false
    )
  end

  it 'returns the updated schedule' do
    execute

    expect(graphql_data_at(:ai_flow_schedule_update, :ai_flow_schedule)).to match a_hash_including(
      'id' => schedule.to_global_id.to_s,
      'description' => 'New',
      'cron' => '30 21 * * *',
      'active' => false
    )
  end

  context 'when the update does not touch the cron' do
    let(:params) { { id: schedule.to_global_id, description: 'New' } }

    it 'preserves next_run_at' do
      expect { execute }.not_to change { schedule.reload.next_run_at }
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_flow_schedule do
    let(:user) { maintainer }
    let(:boundary_object) { project }
    let(:mutation) { graphql_mutation(:ai_flow_schedule_update, params, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
