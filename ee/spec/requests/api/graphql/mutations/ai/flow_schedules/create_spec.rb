# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::FlowSchedules::Create, feature_category: :code_suggestions do
  include GraphqlHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project, :in_group, maintainers: maintainer) }
  let_it_be(:trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let(:current_user) { maintainer }
  let(:mutation) { graphql_mutation(:ai_flow_schedule_create, params) }
  let(:cron) { '0 21 * * *' }
  let(:params) do
    {
      flow_trigger_id: trigger.to_global_id,
      description: 'Nightly schedule',
      cron: cron,
      cron_timezone: 'UTC'
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

    it 'does not create a flow schedule' do
      expect { execute }.not_to change { Ai::FlowSchedule.count }
    end
  end

  context 'when user is a developer' do
    let(:current_user) { create(:user).tap { |user| project.add_developer(user) } }

    it_behaves_like 'an authorization failure'
  end

  context 'when the flow trigger does not exist' do
    let(:params) do
      super().merge(flow_trigger_id: Gitlab::GlobalId.build(model_name: 'Ai::FlowTrigger', id: non_existing_record_id))
    end

    it_behaves_like 'an authorization failure'
  end

  context 'when graphql params are invalid' do
    let(:params) { super().except(:description) }

    it 'returns the validation error' do
      execute

      expect(graphql_errors.first['message']).to include('description (Expected value to not be null)')
    end
  end

  context 'when model params are invalid' do
    let(:cron) { 'not a cron' }

    it 'returns the validation error' do
      execute

      expect(graphql_data_at(:ai_flow_schedule_create, :errors).first).to include('Cron syntax is invalid')
      expect(graphql_data_at(:ai_flow_schedule_create, :ai_flow_schedule)).to be_nil
    end
  end

  context 'when the plan limit is exceeded' do
    before do
      create(:plan_limits, :default_plan, ai_flow_schedules: 1)
      create(:ai_flow_schedule, flow_trigger: trigger)
    end

    it 'returns the limit error' do
      execute

      expect(graphql_data_at(:ai_flow_schedule_create, :errors).first)
        .to include('Maximum number of ai flow schedules (1) exceeded')
      expect(graphql_data_at(:ai_flow_schedule_create, :ai_flow_schedule)).to be_nil
    end
  end

  it 'creates a flow schedule with expected data' do
    expect { execute }.to change { Ai::FlowSchedule.count }.by(1)

    schedule = Ai::FlowSchedule.last
    expect(schedule).to have_attributes(
      description: 'Nightly schedule',
      cron: cron,
      cron_timezone: 'UTC',
      active: true,
      project_id: project.id,
      ai_flow_trigger_id: trigger.id
    )
  end

  it 'returns the new schedule' do
    execute

    expect(graphql_data_at(:ai_flow_schedule_create, :ai_flow_schedule)).to match a_hash_including(
      'description' => 'Nightly schedule',
      'cron' => cron,
      'cronTimezone' => 'UTC',
      'active' => true,
      'flowTrigger' => a_hash_including('id' => trigger.to_global_id.to_s),
      'project' => a_hash_including('id' => project.to_global_id.to_s)
    )
    expect(graphql_data_at(:ai_flow_schedule_create, :ai_flow_schedule, :next_run_at)).to be_present
  end

  context 'when the ai_flow_schedules feature flag is disabled' do
    before do
      stub_feature_flags(ai_flow_schedules: false)
    end

    it 'does not create a flow schedule' do
      expect { execute }.not_to change { Ai::FlowSchedule.count }
    end

    it 'returns an error' do
      execute

      expect(graphql_data_at(:ai_flow_schedule_create, :errors))
        .to contain_exactly('Flow schedules are not available')
      expect(graphql_data_at(:ai_flow_schedule_create, :ai_flow_schedule)).to be_nil
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :create_ai_flow_schedule do
    let(:user) { maintainer }
    let(:boundary_object) { project }
    let(:mutation) { graphql_mutation(:ai_flow_schedule_create, params, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
