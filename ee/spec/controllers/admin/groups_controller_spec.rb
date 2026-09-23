# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::GroupsController, feature_category: :continuous_integration do
  let_it_be(:admin) { create(:admin) }
  let_it_be_with_reload(:group) { create(:group) }

  before do
    sign_in(admin)
  end

  describe 'GET #index' do
    subject(:get_index) { get :index }

    it_behaves_like 'pushes saas feature', :group_project_permanent_deletion_confirmation
    it_behaves_like 'pushes dedicated feature', :group_project_permanent_deletion_confirmation
  end

  describe 'POST #reset_runner_minutes', feature_category: :hosted_runners do
    subject(:post_reset_runners_minutes) { post :reset_runners_minutes, params: { id: group } }

    before do
      allow_next_instance_of(Ci::Minutes::ResetUsageService) do |instance|
        allow(instance).to receive(:execute).and_return(clear_runners_minutes_service_result)
      end
    end

    context 'when the reset is successful' do
      let(:clear_runners_minutes_service_result) { true }

      it 'redirects to group path' do
        post_reset_runners_minutes

        expect(response).to redirect_to(admin_group_path(group))
        expect(controller).to set_flash[:notice]
      end
    end
  end

  describe 'POST #create' do
    subject(:post_request) { post :create, params: { group: params } }

    context 'when repository size limit is provided' do
      let(:params) { { path: 'test', name: 'test', repository_size_limit: '5000' } }

      it 'creates a group with a correct repository limit' do
        expect { post_request }.to change { Group.count }.by(1)

        expect(Group.last.repository_size_limit).to eq(5000.megabytes)
      end
    end
  end

  describe 'PUT #update' do
    it 'converts the user entered MiB value into bytes' do
      put :update, params: { id: group, group: { repository_size_limit: '5000' } }

      expect(controller).to set_flash[:notice].to 'Group was successfully updated.'
      expect(response).to redirect_to(admin_group_path(group))
      expect(group.reload.repository_size_limit).to eq(5000.megabytes)
    end

    context 'with subscription plan params', :saas do
      let_it_be(:premium_plan) { create(:premium_plan) }
      let_it_be(:ultimate_plan) { create(:ultimate_plan) }

      it 'updates the plan through hosted_plan_name_uid' do
        subscription = create(:gitlab_subscription, namespace: group, hosted_plan: ultimate_plan)

        put :update, params: {
          id: group,
          group: {
            gitlab_subscription_attributes: {
              hosted_plan_name_uid: premium_plan.plan_name_uid_before_type_cast
            }
          }
        }

        expect(subscription.reload.hosted_plan).to eq(premium_plan)
      end
    end
  end
end
