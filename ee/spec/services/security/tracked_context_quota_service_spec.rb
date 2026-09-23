# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TrackedContextQuotaService, feature_category: :vulnerability_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:project) { create(:project, group: group, organization: organization) }

  subject(:service) { described_class.new(organization) }

  before do
    # Enforcement is gated by the :security_tracked_context_quota_enforcement
    # feature flag. Enable it by default so the usage/limit behaviour is
    # exercised; individual contexts below disable it where relevant.
    stub_feature_flags(security_tracked_context_quota_enforcement: true)
  end

  def set_quota(value)
    setting = ::Organizations::OrganizationSetting.for(organization.id)
    setting.update!(security_tracked_context_quota: value)
  end

  # Creates `count` tracked contexts spread across distinct projects in the
  # organization, so we exercise the organization-level quota without tripping
  # the per-project MAX_TRACKED_REFS_PER_PROJECT limit.
  #
  # Persisted with `validate: false` so seeding deliberately over-quota usage
  # is not blocked by the organization-quota validation that the stacked
  # validation MR (#598088) adds to Security::ProjectTrackedContext.
  def create_tracked_contexts(count)
    Array.new(count) do
      ctx_project = create(:project, group: group, organization: organization)
      context = build(:security_project_tracked_context, :tracked, project: ctx_project)
      context.save!(validate: false)
      context
    end
  end

  describe '#quota_available?' do
    context 'when enforcement is disabled for the actor' do
      before do
        stub_feature_flags(security_tracked_context_quota_enforcement: false)
      end

      it 'returns true regardless of usage' do
        set_quota(1)
        create_tracked_contexts(5)

        expect(service.quota_available?(project)).to be(true)
      end
    end

    context 'when enforcement is enabled for the actor' do
      context 'with an explicit quota' do
        before do
          set_quota(3)
        end

        it 'returns true when usage is under the limit' do
          create_tracked_contexts(2)

          expect(service.quota_available?(project)).to be(true)
        end

        it 'returns false when usage is at the limit' do
          create_tracked_contexts(3)

          expect(service.quota_available?(project)).to be(false)
        end

        it 'returns false when usage is over the limit' do
          create_tracked_contexts(4)

          expect(service.quota_available?(project)).to be(false)
        end
      end

      context 'when the quota limit is nil (no SaaS default, e.g. self-managed)' do
        before do
          allow(service).to receive(:quota_limit).and_return(nil)
        end

        it 'returns true (no enforcement)' do
          create_tracked_contexts(5)

          expect(service.quota_available?(project)).to be(true)
        end
      end
    end
  end

  describe '#current_usage' do
    it 'counts only tracked contexts within the organization' do
      create_tracked_contexts(2)
      create(:security_project_tracked_context, :untracked, project: project)

      expect(service.current_usage).to eq(2)
    end

    it 'does not count tracked contexts from other organizations' do
      other_organization = create(:organization)
      other_group = create(:group, organization: other_organization)
      other_project = create(:project, group: other_group, organization: other_organization)
      create(:security_project_tracked_context, :tracked, project: other_project)

      create_tracked_contexts(1)

      expect(service.current_usage).to eq(1)
    end

    it 'returns 0 when the organization has no root namespaces' do
      empty_organization = create(:organization)

      expect(described_class.new(empty_organization).current_usage).to eq(0)
    end

    it 'counts tracked contexts in personal-namespace projects in the organization' do
      user_namespace = create(:user_namespace, organization: organization)
      personal_project = create(:project, namespace: user_namespace, organization: organization)
      create(:security_project_tracked_context, :tracked, project: personal_project)

      create_tracked_contexts(1)

      expect(service.current_usage).to eq(2)
    end

    it 'does not count contexts in non-tracked states' do
      create(:security_project_tracked_context, :untracked, project: project)
      create(:security_project_tracked_context, :archiving, project: project)
      create(:security_project_tracked_context, :deleting, project: project)

      expect(service.current_usage).to eq(0)
    end
  end

  describe '#quota_limit' do
    it 'returns the explicit quota when set' do
      set_quota(7)

      expect(service.quota_limit).to eq(7)
    end

    context 'on SaaS without an explicit quota' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        allow(::Gitlab::CurrentSettings).to receive(:default_security_tracked_context_quota).and_return(2)
      end

      it 'falls back to the SaaS-wide default' do
        expect(service.quota_limit).to eq(2)
      end
    end

    context 'when not on SaaS and no explicit quota' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'returns nil (no enforcement)' do
        expect(service.quota_limit).to be_nil
      end
    end
  end

  describe '#remaining_quota' do
    it 'returns the difference between limit and usage' do
      set_quota(5)
      create_tracked_contexts(2)

      expect(service.remaining_quota).to eq(3)
    end

    it 'does not go below zero when over the limit' do
      set_quota(2)
      create_tracked_contexts(4)

      expect(service.remaining_quota).to eq(0)
    end

    it 'returns nil when the limit is nil' do
      allow(service).to receive(:quota_limit).and_return(nil)

      expect(service.remaining_quota).to be_nil
    end
  end

  describe '#quota_explicitly_set?' do
    it 'returns true when an explicit quota is set' do
      set_quota(4)

      expect(service.quota_explicitly_set?).to be(true)
    end

    it 'returns false when no explicit quota is set' do
      expect(service.quota_explicitly_set?).to be(false)
    end
  end

  describe '#quota_enforcement_enabled?' do
    it 'is true when the feature flag is enabled for the actor' do
      stub_feature_flags(security_tracked_context_quota_enforcement: project)

      expect(service.quota_enforcement_enabled?(project)).to be(true)
    end

    it 'is false when the feature flag is disabled for the actor' do
      stub_feature_flags(security_tracked_context_quota_enforcement: false)

      expect(service.quota_enforcement_enabled?(project)).to be(false)
    end

    it 'can be toggled independently of VAC tracking' do
      stub_feature_flags(
        security_tracked_context_quota_enforcement: false,
        vulnerabilities_across_contexts: true
      )

      expect(service.quota_enforcement_enabled?(project)).to be(false)
    end
  end

  describe '#quota_exceeded_error_message' do
    it 'returns a message including the quota limit' do
      set_quota(10)

      expect(service.quota_exceeded_error_message).to include('10')
    end

    it 'returns an empty string when the quota limit is nil' do
      allow(service).to receive(:quota_limit).and_return(nil)

      expect(service.quota_exceeded_error_message).to eq('')
    end
  end

  describe '#quota_info' do
    it 'returns a hash with the quota details' do
      set_quota(5)
      create_tracked_contexts(2)

      expect(service.quota_info).to eq(
        limit: 5,
        usage: 2,
        remaining: 3,
        explicitly_set: true
      )
    end
  end
end
