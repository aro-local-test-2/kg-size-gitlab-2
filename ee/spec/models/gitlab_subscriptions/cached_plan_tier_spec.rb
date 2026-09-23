# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::CachedPlanTier, :saas_gitlab_com_subscriptions, :request_store,
  :use_clean_rails_memory_store_caching, feature_category: :rate_limiting do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  def uid_for(plan_name)
    ::GitlabSubscriptions::SystemDefined::Plan.uids_for_names([plan_name]).first
  end

  def clear_caches
    Rails.cache.clear
    ::Gitlab::SafeRequestStore.clear!
  end

  describe '.for_root_namespace_id' do
    let_it_be_with_reload(:subscription) { create(:gitlab_subscription, :free, namespace: group) }

    def tier_for(plan_name)
      subscription.update_column(:hosted_plan_name_uid, uid_for(plan_name))
      clear_caches

      described_class.for_root_namespace_id(group.id)
    end

    # Plan.tier_for owns the name mapping; this proves the uid reaches it.
    it 'reads the tier of the plan the subscription names', :aggregate_failures do
      expect(tier_for('premium')).to eq('premium')
      expect(tier_for('ultimate')).to eq('ultimate')
    end

    it 'returns free for a namespace with no subscription row' do
      expect(described_class.for_root_namespace_id(create(:group).id)).to eq('free')
    end

    it 'returns free for a namespace whose subscription carries no plan name uid' do
      expect(described_class.for_root_namespace_id(group.id)).to eq('free')
    end

    it 'returns free for a namespace that does not exist' do
      expect(described_class.for_root_namespace_id(non_existing_record_id)).to eq('free')
    end

    # An unsaved namespace has empty traversal_ids, so the caller folds to nil. Without
    # the guard every one of them would share the idless key.
    it 'returns free for a nil id without caching' do
      expect(Rails.cache).not_to receive(:fetch)

      expect(described_class.for_root_namespace_id(nil)).to eq('free')
    end

    # The argument has to be a root id; a caller that forgets to fold gets free
    # rather than the root's tier, which is silent, so pin it.
    it 'returns free for a subgroup id, since subscriptions only exist on roots' do
      subscription.update_column(:hosted_plan_name_uid, uid_for('ultimate'))
      subgroup = create(:group, parent: group)
      clear_caches

      expect(described_class.for_root_namespace_id(subgroup.id)).to eq('free')
    end

    it 'caches for ten minutes under a key named for the namespace, guarding the expiry stampede' do
      expect(Rails.cache).to receive(:fetch).with(
        "plan_tier:namespace:#{group.id}", expires_in: 10.minutes, race_condition_ttl: 10.seconds
      ).and_call_original

      described_class.for_root_namespace_id(group.id)
    end

    it 'reads the subscription once, then serves the request store' do
      subscription.update_column(:hosted_plan_name_uid, uid_for('premium'))
      clear_caches

      expect { described_class.for_root_namespace_id(group.id) }.to match_query_count(1)
      expect { described_class.for_root_namespace_id(group.id) }.to match_query_count(0)
    end

    # Without this, the example above would pass on the request store alone and
    # prove nothing about the ten-minute Rails.cache entry.
    it 'serves a later request from Rails.cache, not just the request store', :aggregate_failures do
      subscription.update_column(:hosted_plan_name_uid, uid_for('premium'))
      clear_caches
      described_class.for_root_namespace_id(group.id)

      ::Gitlab::SafeRequestStore.clear!

      expect { described_class.for_root_namespace_id(group.id) }.to match_query_count(0)
      expect(described_class.for_root_namespace_id(group.id)).to eq('premium')
    end

    it 'loads no namespace record' do
      recorder = ActiveRecord::QueryRecorder.new { described_class.for_root_namespace_id(group.id) }

      expect(recorder.log.grep(/FROM "namespaces"/)).to be_empty
    end
  end

  describe '.for_user_id' do
    it 'returns free for a requester with no candidate namespace' do
      expect(described_class.for_user_id(user.id)).to eq('free')
    end

    it 'reads the tier of a group the requester is a member of' do
      create(:gitlab_subscription, :premium, namespace: group)
      create(:group_member, :guest, group: group, user: user)

      expect(described_class.for_user_id(user.id)).to eq('premium')
    end

    it 'reduces a subgroup membership to its root ancestor' do
      create(:gitlab_subscription, :ultimate, namespace: group)
      create(:group_member, :developer, group: create(:group, parent: group), user: user)

      expect(described_class.for_user_id(user.id)).to eq('ultimate')
    end

    it 'reduces a project membership to the root namespace' do
      create(:gitlab_subscription, :premium, namespace: group)
      create(:project_member, :developer, project: create(:project, group: group), user: user)

      expect(described_class.for_user_id(user.id)).to eq('premium')
    end

    it 'takes the highest tier when the candidates disagree' do
      premium_group = create(:group)
      create(:gitlab_subscription, :premium, namespace: premium_group)
      create(:gitlab_subscription, :ultimate, namespace: group)
      create(:group_member, :developer, group: premium_group, user: user)
      create(:group_member, :developer, group: group, user: user)

      expect(described_class.for_user_id(user.id)).to eq('ultimate')
    end

    it 'reads the root plan and ignores a subscription attached to the subgroup itself' do
      subgroup = create(:group, parent: group)
      create(:gitlab_subscription, :premium, namespace: group)
      create(:gitlab_subscription, :ultimate, namespace: subgroup)
      create(:group_member, :developer, group: subgroup, user: user)

      expect(described_class.for_user_id(user.id)).to eq('premium')
    end

    # The per-branch examples each populate one branch only, so nothing yet proves
    # the union merges candidates across branches of different kinds.
    it 'takes the highest tier across a membership and a provisioning column' do
      enterprise_user = create(:user)
      premium_group = create(:group)
      create(:gitlab_subscription, :premium, namespace: premium_group)
      create(:gitlab_subscription, :ultimate, namespace: group)
      create(:group_member, :developer, group: premium_group, user: enterprise_user)
      enterprise_user.update!(provisioned_by_group: group)

      expect(described_class.for_user_id(enterprise_user.id)).to eq('ultimate')
    end

    it 'resolves a project bot through the membership it was created with' do
      bot = create(:user, :project_bot)
      create(:gitlab_subscription, :ultimate, namespace: group)
      create(:project_member, :maintainer, project: create(:project, group: group), user: bot)

      expect(described_class.for_user_id(bot.id)).to eq('ultimate')
    end

    it 'ignores a candidate whose subscription carries no plan name uid' do
      uidless_group = create(:group)
      create(:gitlab_subscription, :free, namespace: uidless_group)
      create(:gitlab_subscription, :ultimate, namespace: group)
      create(:group_member, :developer, group: uidless_group, user: user)
      create(:group_member, :developer, group: group, user: user)

      expect(described_class.for_user_id(user.id)).to eq('ultimate')
    end

    it 'ignores the requester personal namespace' do
      requester = create(:user, :with_namespace)
      create(:gitlab_subscription, :ultimate, namespace: requester.namespace)

      expect(described_class.for_user_id(requester.id)).to eq('free')
    end

    context 'when the membership is not an effective one' do
      before do
        create(:gitlab_subscription, :ultimate, namespace: group)
      end

      it 'ignores an access request' do
        create(:group_member, :developer, group: group, user: user, requested_at: Time.current)

        expect(described_class.for_user_id(user.id)).to eq('free')
      end

      it 'ignores a member awaiting seat approval' do
        create(:group_member, :developer, :awaiting, group: group, user: user)

        expect(described_class.for_user_id(user.id)).to eq('free')
      end

      it 'ignores a minimal access member' do
        create(:group_member, :minimal_access, group: group, user: user)

        expect(described_class.for_user_id(user.id)).to eq('free')
      end
    end

    context 'with a service account, which is provisioned without a membership' do
      let_it_be_with_reload(:service_account) { create(:user, :service_account) }

      it 'resolves through provisioned_by_group_id' do
        create(:gitlab_subscription, :premium, namespace: group)
        service_account.update!(provisioned_by_group: create(:group, parent: group))

        expect(described_class.for_user_id(service_account.id)).to eq('premium')
      end

      it 'resolves through provisioned_by_project_id' do
        create(:gitlab_subscription, :ultimate, namespace: group)
        service_account.update!(provisioned_by_project: create(:project, group: group))

        expect(described_class.for_user_id(service_account.id)).to eq('ultimate')
      end
    end

    it 'resolves in one query, then serves the request store' do
      create(:gitlab_subscription, :premium, namespace: group)
      create(:group_member, :developer, group: group, user: user)
      clear_caches

      expect { described_class.for_user_id(user.id) }.to match_query_count(1)
      expect { described_class.for_user_id(user.id) }.to match_query_count(0)
    end

    it 'serves a later request from Rails.cache, not just the request store', :aggregate_failures do
      create(:gitlab_subscription, :premium, namespace: group)
      create(:group_member, :developer, group: group, user: user)
      clear_caches
      described_class.for_user_id(user.id)

      ::Gitlab::SafeRequestStore.clear!

      expect { described_class.for_user_id(user.id) }.to match_query_count(0)
      expect(described_class.for_user_id(user.id)).to eq('premium')
    end

    it 'loads no user record and inserts no subscription row the way actual_plan would' do
      create(:group_member, :developer, group: group, user: user)
      clear_caches

      recorder = ActiveRecord::QueryRecorder.new { described_class.for_user_id(user.id) }

      expect(recorder.log.grep(/FROM "users"/)).to be_empty
      expect(recorder.log.grep(/INSERT INTO "gitlab_subscriptions"/)).to be_empty
    end

    it 'caches for ten minutes under a key named for the user, guarding the expiry stampede' do
      expect(Rails.cache).to receive(:fetch).with(
        "plan_tier:user:#{user.id}", expires_in: 10.minutes, race_condition_ttl: 10.seconds
      ).and_call_original

      described_class.for_user_id(user.id)
    end

    it 'returns free for a nil id without caching' do
      expect(Rails.cache).not_to receive(:fetch)

      expect(described_class.for_user_id(nil)).to eq('free')
    end
  end
end
