# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedules::DestroyService, feature_category: :code_suggestions do
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: maintainer) }
  let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let!(:flow_schedule) { create(:ai_flow_schedule, flow_trigger: flow_trigger) }

  let(:current_user) { maintainer }
  let(:service) { described_class.new(flow_schedule: flow_schedule, current_user: current_user) }

  subject(:execute) { service.execute }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    stub_ee_application_setting(duo_features_enabled: true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_core_features_enabled: true)
  end

  describe '#execute' do
    it 'destroys the flow schedule' do
      expect { execute }.to change { Ai::FlowSchedule.count }.by(-1)

      expect(execute).to be_success
      expect(execute.payload[:flow_schedule]).to eq(flow_schedule)
    end

    context 'when the user cannot manage flow schedules' do
      let(:current_user) { create(:user, developer_of: project) }

      it 'returns a forbidden error and destroys nothing' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_error
        expect(execute.http_status).to eq(:forbidden)
        expect(execute.message).to eq('You are not authorized to manage flow schedules')
      end
    end

    context 'when destroy fails' do
      before do
        allow(flow_schedule).to receive(:destroy).and_return(false)
        flow_schedule.errors.add(:base, 'cannot be removed')
      end

      it 'returns the error message' do
        expect(execute).to be_error
        expect(execute.message).to include('cannot be removed')
      end
    end
  end
end
