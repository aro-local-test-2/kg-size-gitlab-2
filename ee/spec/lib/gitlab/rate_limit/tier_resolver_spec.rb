# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RateLimit::TierResolver, :saas_gitlab_com_subscriptions, :request_store,
  :use_clean_rails_memory_store_caching, feature_category: :rate_limiting do
  describe '.tier_for' do
    let_it_be(:group) { create(:group) }
    let_it_be(:user) { create(:user) }

    before_all do
      create(:gitlab_subscription, :ultimate, namespace: group)
      create(:group_member, :developer, group: group, user: user)
    end

    it 'reads the tier of a user requester' do
      expect(described_class.tier_for('user', user.id)).to eq('ultimate')
    end

    # ClassifiedRequest stringifies the requester id before it reaches here.
    it 'reads the tier of a user requester given a stringified id' do
      expect(described_class.tier_for('user', user.id.to_s)).to eq('ultimate')
    end

    it 'returns free for a user requester with no candidate namespace' do
      expect(described_class.tier_for('user', create(:user).id)).to eq('free')
    end

    it 'returns nothing for an unauthenticated request, which carries no requester type' do
      expect(described_class.tier_for(nil, nil)).to be_nil
    end

    it 'resolves a service account through its provisioning namespace' do
      service_account = create(:user, :service_account)
      service_account.update!(provisioned_by_group: group)

      expect(described_class.tier_for('user', service_account.id)).to eq('ultimate')
    end

    it 'returns nothing for a deploy token, which resolves through its namespace' do
      expect(described_class.tier_for('deploy_token', create(:deploy_token).id)).to be_nil
    end
  end

  describe '.namespace_tier_for' do
    let_it_be(:group) { create(:group) }

    it 'reads the tier of the root namespace' do
      create(:gitlab_subscription, :premium, namespace: group)

      expect(described_class.namespace_tier_for(group.id)).to eq('premium')
    end

    # TargetNamespace hands the id over as a String.
    it 'reads the tier given a stringified root namespace id' do
      create(:gitlab_subscription, :premium, namespace: group)

      expect(described_class.namespace_tier_for(group.id.to_s)).to eq('premium')
    end

    it 'returns free for a namespace with no subscription' do
      expect(described_class.namespace_tier_for(group.id)).to eq('free')
    end
  end
end
