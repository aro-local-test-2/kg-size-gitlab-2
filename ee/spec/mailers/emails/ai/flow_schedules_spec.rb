# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Emails::Ai::FlowSchedules, feature_category: :code_suggestions do
  include EmailSpec::Matchers

  let(:project) { build_stubbed(:project) }
  let(:recipient) { build_stubbed(:user) }
  let(:flow_trigger) { build_stubbed(:ai_flow_trigger, project: project) }

  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- needs persisted records to exercise real notification_setting lookup
  shared_examples 'delivers to the group-specific notification email' do
    context 'when the recipient has a group-specific notification email' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project) { create(:project, group: group) }
      let_it_be(:recipient) { create(:user) }
      let_it_be(:group_email) { create(:email, :confirmed, user: recipient, email: 'group-notify@example.com').email }

      before_all do
        create(:notification_setting, user: recipient, source: group, notification_email: group_email)
      end

      it 'delivers to the group-specific notification email' do
        expect(email).to be_delivered_to([group_email])
      end
    end
  end
  # rubocop:enable RSpec/FactoryBot/AvoidCreate

  describe '#ai_flow_schedule_deactivated_email' do
    let(:schedule) do
      build_stubbed(:ai_flow_schedule, :deactivated_by_failures,
        flow_trigger: flow_trigger, project: project, description: 'Nightly run')
    end

    subject(:email) { Notify.ai_flow_schedule_deactivated_email(schedule, recipient) }

    it 'sends mail with expected contents', :aggregate_failures do
      expect(email).to have_subject(/Flow schedule deactivated: Nightly run/)
      expect(email).to be_delivered_to([recipient.notification_email_for(project.group)])
      expect(email).to have_body_text(project.full_name)
      expect(email).to have_body_text(
        "has been deactivated after #{Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES} consecutive failures")
      expect(email).to have_body_text('Service account is no longer available')
    end

    context 'when the recipient is an array' do
      subject(:email) { Notify.ai_flow_schedule_deactivated_email(schedule, [recipient]) }

      it 'raises ArgumentError' do
        expect { email.message }.to raise_error(ArgumentError, /recipient must be a single User/)
      end
    end

    it_behaves_like 'delivers to the group-specific notification email'
  end

  describe '#ai_flow_schedule_failure_email' do
    let(:schedule) do
      build_stubbed(:ai_flow_schedule, flow_trigger: flow_trigger, project: project, description: 'Nightly run',
        consecutive_failure_count: 2, last_run_error: 'Something went wrong')
    end

    subject(:email) { Notify.ai_flow_schedule_failure_email(schedule, recipient) }

    it 'sends mail with expected contents', :aggregate_failures do
      expect(email).to have_subject(/Flow schedule failed: Nightly run/)
      expect(email).to be_delivered_to([recipient.notification_email_for(project.group)])
      expect(email).to have_body_text(project.full_name)
      expect(email).to have_body_text('Something went wrong')
      expect(email).to have_body_text("Failure count: 2 of #{Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES}")
    end

    context 'when the recipient is an array' do
      subject(:email) { Notify.ai_flow_schedule_failure_email(schedule, [recipient]) }

      it 'raises ArgumentError' do
        expect { email.message }.to raise_error(ArgumentError, /recipient must be a single User/)
      end
    end

    it_behaves_like 'delivers to the group-specific notification email'
  end
end
