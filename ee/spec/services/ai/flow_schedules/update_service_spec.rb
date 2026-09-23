# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedules::UpdateService, feature_category: :code_suggestions do
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: maintainer) }
  let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let_it_be_with_reload(:flow_schedule) do
    create(:ai_flow_schedule, flow_trigger: flow_trigger, cron: '0 9 * * 1', description: 'Old')
  end

  let(:current_user) { maintainer }
  let(:params) { { description: 'New', cron: '30 21 * * *' } }
  let(:service) { described_class.new(flow_schedule: flow_schedule, current_user: current_user) }

  subject(:execute) { service.execute(params) }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    stub_ee_application_setting(duo_features_enabled: true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_core_features_enabled: true)
  end

  describe '#execute' do
    it 'updates the flow schedule' do
      expect(execute).to be_success
      expect(execute.payload[:flow_schedule]).to have_attributes(
        description: 'New',
        cron: '30 21 * * *'
      )
    end

    it 'recalculates next_run_at when the cron changes' do
      expect { execute }.to change { flow_schedule.reload.next_run_at }
    end

    context 'when the update does not touch the cron' do
      let(:params) { { description: 'New' } }

      it 'preserves next_run_at' do
        expect { execute }.not_to change { flow_schedule.reload.next_run_at }
      end
    end

    context 'when the user cannot manage flow schedules' do
      let(:current_user) { create(:user, developer_of: project) }

      it 'returns a forbidden error and changes nothing' do
        expect { execute }.not_to change { flow_schedule.reload.attributes }

        expect(execute).to be_error
        expect(execute.http_status).to eq(:forbidden)
        expect(execute.message).to eq('You are not authorized to manage flow schedules')
      end
    end

    context 'when params are invalid' do
      let(:params) { { cron: 'not a cron' } }

      it 'returns the validation error and changes nothing' do
        expect { execute }.not_to change { flow_schedule.reload.cron }

        expect(execute).to be_error
        expect(execute.message).to include('Cron syntax is invalid')
      end
    end
  end
end
