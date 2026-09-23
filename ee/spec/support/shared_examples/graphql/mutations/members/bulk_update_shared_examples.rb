# frozen_string_literal: true

RSpec.shared_examples 'promotion management for members bulk update' do
  let(:fields) do
    <<-FIELDS
      errors
      queuedMemberApprovals {
        nodes {
          status
          newAccessLevel {
            integerValue
            humanAccess
          }
          oldAccessLevel {
            integerValue
            humanAccess
          }
        }
        count
      }
      #{response_member_field} {
        accessLevel {
          integerValue
          stringValue
          humanAccess
        }
      }
    FIELDS
  end

  let(:mutation) { graphql_mutation(mutation_name, input_params, fields) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }
  let(:promoted_access_level) { Gitlab::Access::DEVELOPER }
  let(:input_params) do
    {
      source_id_key => source.to_global_id.to_s,
      'user_ids' => users.map(&:to_global_id).map(&:to_s),
      'access_level' => 'DEVELOPER'
    }
  end

  let_it_be(:users, freeze: false) { create_list(:user, 2) }
  let_it_be(:license, freeze: false) { create(:license, plan: License::ULTIMATE_PLAN) }

  before do
    users.each do |user|
      source.add_guest(user)
    end

    source.add_owner(current_user)
    stub_application_setting(enable_member_promotion_management: true)
    allow(License).to receive(:current).and_return(license)
  end

  RSpec.shared_examples 'updates all members' do
    it do
      post_graphql_mutation(mutation, current_user: current_user)
      new_access_levels = mutation_response[response_member_field].map do |member|
        member['accessLevel']['integerValue']
      end

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(new_access_levels).to all(be promoted_access_level)
    end
  end

  context 'when member_promotion_management is disabled' do
    before do
      stub_application_setting(enable_member_promotion_management: false)
    end

    it_behaves_like 'updates all members'
  end

  context 'when on SaaS', :saas do
    it_behaves_like 'updates all members'
  end

  context 'when on SM' do
    it 'queues non billable users promotions to billable roles' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['queuedMemberApprovals']["count"]).to eq(2)

      queued_members = mutation_response['queuedMemberApprovals']['nodes']
      queued_new_access_levels = queued_members.map do |member_approval|
        member_approval['newAccessLevel']['integerValue']
      end

      queued_old_access_levels = queued_members.map do |member_approval|
        member_approval['oldAccessLevel']['integerValue']
      end

      statuses = queued_members.pluck('status')
      expect(statuses).to all(eq('pending'))
      expect(queued_new_access_levels).to all(be promoted_access_level)
      expect(queued_old_access_levels).to all(be Gitlab::Access::GUEST)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response[response_member_field]).to be_empty
    end

    context 'when users are already billable' do
      let(:promoted_access_level) { Gitlab::Access::MAINTAINER }

      before do
        input_params['access_level'] = 'MAINTAINER'

        users.each do |user|
          source.add_developer(user)
        end
      end

      it_behaves_like 'updates all members'
    end
  end
end

RSpec.shared_examples 'seat type enforcement for members bulk update' do
  let_it_be(:permitted_user) { create(:user) }
  let_it_be(:rejected_user) { create(:user) }

  let(:fields) do
    <<-FIELDS
      errors
      #{response_member_field} {
        id
      }
    FIELDS
  end

  let(:user_ids) { [rejected_user.to_global_id.to_s] }

  let(:input_params) do
    {
      source_id_key => source.to_global_id.to_s,
      'user_ids' => user_ids,
      'access_level' => 'DEVELOPER'
    }
  end

  let(:mutation) { graphql_mutation(mutation_name, input_params, fields) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  let(:permitted_member) { source.members.with_user(permitted_user).first }
  let(:rejected_member) { source.members.with_user(rejected_user).first }

  before do
    source.add_guest(permitted_user)
    source.add_guest(rejected_user)
    source.add_owner(current_user)

    create(:gitlab_subscription_seat_assignment,
      namespace: source.root_ancestor, user: permitted_user, seat_type: :base)
    create(:gitlab_subscription_seat_assignment,
      namespace: source.root_ancestor, user: rejected_user, seat_type: :free)
  end

  context 'when the seat_assignment_model feature flag is disabled' do
    before do
      stub_feature_flags(seat_assignment_model: false)
    end

    it 'ignores the seat type and updates the member' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { rejected_member.reload.access_level }.to(Gitlab::Access::DEVELOPER)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
    end
  end

  context 'when the seat type does not permit the role' do
    it 'does not update the member and returns an error' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .not_to change { rejected_member.reload.access_level }

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors'])
        .to contain_exactly('Access level is not permitted for the seat type')
      expect(mutation_response[response_member_field].pluck('id'))
        .to contain_exactly(rejected_member.to_global_id.to_s)
    end
  end

  context 'when all members in the batch are permitted' do
    let_it_be(:other_permitted_user) { create(:user) }

    let(:other_permitted_member) { source.members.with_user(other_permitted_user).first }
    let(:user_ids) { [permitted_user.to_global_id.to_s, other_permitted_user.to_global_id.to_s] }

    before do
      source.add_guest(other_permitted_user)

      create(:gitlab_subscription_seat_assignment,
        namespace: source.root_ancestor, user: other_permitted_user, seat_type: :base)
    end

    it 'updates every member' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { permitted_member.reload.access_level }.to(Gitlab::Access::DEVELOPER)
        .and change { other_permitted_member.reload.access_level }.to(Gitlab::Access::DEVELOPER)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
    end
  end

  context 'when a member in the batch is not permitted' do
    let(:user_ids) { [permitted_user.to_global_id.to_s, rejected_user.to_global_id.to_s] }

    it 'does not update any member and returns an error' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to not_change { permitted_member.reload.access_level }
        .and not_change { rejected_member.reload.access_level }

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors'])
        .to contain_exactly('Access level is not permitted for the seat type')
      expect(mutation_response[response_member_field].pluck('id'))
        .to contain_exactly(rejected_member.to_global_id.to_s)
    end
  end
end
