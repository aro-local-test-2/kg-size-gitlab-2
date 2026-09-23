# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AdminEmailsWorker, feature_category: :team_planning do
  context "recipients" do
    let(:group) { create(:group) }
    let(:project) { create(:project) }

    before do
      2.times do
        user = create(:user)
        group.add_member(user, Gitlab::Access::DEVELOPER)
        project.add_member(user, Gitlab::Access::DEVELOPER)
      end

      unsubscribed_user = create(:user, admin_email_unsubscribed_at: 5.days.ago)
      group.add_member(unsubscribed_user, Gitlab::Access::DEVELOPER)
      project.add_member(unsubscribed_user, Gitlab::Access::DEVELOPER)

      blocked_user = create(:user, state: :blocked)
      group.add_member(blocked_user, Gitlab::Access::DEVELOPER)
      project.add_member(blocked_user, Gitlab::Access::DEVELOPER)
      ActionMailer::Base.deliveries = []
    end

    shared_examples "excludes bots except service accounts with a custom email address" do
      let!(:project_bot) { create(:user, :project_bot, guest_of: bot_sources) }
      let!(:service_account_with_generated_email) { create(:user, :service_account, guest_of: bot_sources) }
      let!(:service_account_with_custom_email) do
        create(:user, :service_account, email: 'service-account@example.com', guest_of: bot_sources)
      end

      it "does not send emails to bots, except service accounts with a custom email address", :aggregate_failures do
        perform_enqueued_jobs do
          subject.perform(recipient_id, 'subject', 'body')

          delivered_to = ActionMailer::Base.deliveries.flat_map(&:to)
          expect(delivered_to).not_to include(project_bot.email)
          expect(delivered_to).not_to include(service_account_with_generated_email.email)
          expect(delivered_to).to include(service_account_with_custom_email.email)
        end
      end
    end

    context "sending emails to members of a group only" do
      let(:recipient_id) { "group-#{group.id}" }
      let(:bot_sources) { group }

      it "sends email to subscribed users" do
        perform_enqueued_jobs do
          subject.perform(recipient_id, 'subject', 'body')

          expect(ActionMailer::Base.deliveries.count).to eq(2)
        end
      end

      it_behaves_like "excludes bots except service accounts with a custom email address"
    end

    context "sending emails to members of a project only" do
      let(:recipient_id) { "project-#{project.id}" }
      let(:bot_sources) { project }

      it "sends email to subscribed users" do
        perform_enqueued_jobs do
          subject.perform(recipient_id, 'subject', 'body')

          expect(ActionMailer::Base.deliveries.count).to eq(3)
        end
      end

      it_behaves_like "excludes bots except service accounts with a custom email address"
    end

    context "sending emails to users directly" do
      let(:recipient_id) { "all" }
      let(:bot_sources) { [group, project] }

      it "sends email to subscribed users" do
        perform_enqueued_jobs do
          subject.perform(recipient_id, 'subject', 'body')

          expect(ActionMailer::Base.deliveries.count).to eq(3)
        end
      end

      it_behaves_like "excludes bots except service accounts with a custom email address"
    end
  end
end
