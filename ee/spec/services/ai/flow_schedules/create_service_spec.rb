# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedules::CreateService, feature_category: :code_suggestions do
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: maintainer) }
  let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let(:current_user) { maintainer }
  let(:params) do
    {
      description: 'Nightly schedule',
      cron: '0 21 * * *',
      cron_timezone: 'UTC',
      active: true
    }
  end

  let(:service) { described_class.new(flow_trigger: flow_trigger, current_user: current_user) }

  subject(:execute) { service.execute(params) }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    stub_ee_application_setting(duo_features_enabled: true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_core_features_enabled: true)
  end

  describe '#execute' do
    it 'creates a flow schedule in the trigger project' do
      expect { execute }.to change { Ai::FlowSchedule.count }.by(1)

      expect(execute).to be_success

      schedule = execute.payload[:flow_schedule]
      expect(schedule).to have_attributes(
        description: 'Nightly schedule',
        cron: '0 21 * * *',
        cron_timezone: 'UTC',
        active: true,
        project_id: project.id,
        ai_flow_trigger_id: flow_trigger.id
      )
      expect(schedule.next_run_at).to be_present
    end

    context 'when the ai_flow_schedules feature flag is disabled for the project' do
      before do
        stub_feature_flags(ai_flow_schedules: false)
      end

      it 'returns a forbidden error and creates nothing' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_error
        expect(execute.http_status).to eq(:forbidden)
        expect(execute.message).to eq('Flow schedules are not available')
      end
    end

    context 'when the user cannot manage flow schedules' do
      let(:current_user) { create(:user, developer_of: project) }

      it 'returns a forbidden error and creates nothing' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_error
        expect(execute.http_status).to eq(:forbidden)
        expect(execute.message).to eq('You are not authorized to manage flow schedules')
      end
    end

    context 'when params are invalid' do
      let(:params) { super().merge(cron: 'not a cron') }

      it 'returns the validation error and creates nothing' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_error
        expect(execute.message).to include('Cron syntax is invalid')
      end
    end

    context 'when the plan limit is reached' do
      before do
        create(:plan_limits, :default_plan, ai_flow_schedules: 1)
        create(:ai_flow_schedule, flow_trigger: flow_trigger)
      end

      it 'returns the limit error and creates nothing' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_error
        expect(execute.message).to include('Maximum number of ai flow schedules (1) exceeded')
      end
    end
  end
end
