# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Policies::GroupTransferWorker, '#perform', feature_category: :security_policy_management do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:project_a) { create(:project, group: group) }
  let_it_be(:project_b) { create(:project, group: group) }

  let(:group_id) { group.id }
  let(:current_user_id) { user.id }

  subject(:perform) { described_class.new.perform(group_id, current_user_id) }

  before do
    stub_const("#{described_class}::BATCH_SIZE", 1)
  end

  context 'with licensed feature' do
    before do
      stub_licensed_features(security_orchestration_policies: true)
    end

    it 'enqueues contained projects in batches' do
      expect(Security::Policies::GroupProjectTransferWorker)
        .to receive(:bulk_perform_async)
              .with([[project_a.id, current_user_id]]).ordered

      expect(Security::Policies::GroupProjectTransferWorker)
        .to receive(:bulk_perform_async)
              .with([[project_b.id, current_user_id]]).ordered

      perform
    end

    context 'with non-existing group ID' do
      let(:group_id) { non_existing_record_id }

      it 'does not enqueue' do
        expect(Security::Policies::GroupProjectTransferWorker).not_to receive(:bulk_perform_async)

        perform
      end
    end
  end

  context 'without licensed feature' do
    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it 'does not enqueue' do
      expect(Security::Policies::GroupProjectTransferWorker).not_to receive(:bulk_perform_async)

      perform
    end
  end

  context 'without licensed feature but with the dependency firewall enforced' do
    before do
      stub_saas_features(dependency_firewall: true)
      stub_licensed_features(security_orchestration_policies: false, dependency_firewall: true)
      group.namespace_settings.update!(dependency_firewall_enabled: true)
    end

    it 'enforces the dependency firewall for the group' do
      expect(::Security::PolicyAvailability.any_available?(group)).to be(true)
    end

    it 'does not enqueue, because this gate only opens for security_orchestration_policies' do
      expect(Security::Policies::GroupProjectTransferWorker).not_to receive(:bulk_perform_async)

      perform
    end

    context 'when security policies are also licensed' do
      before do
        stub_licensed_features(security_orchestration_policies: true, dependency_firewall: true)
      end

      it 'enqueues contained projects' do
        expect(Security::Policies::GroupProjectTransferWorker).to receive(:bulk_perform_async).twice

        perform
      end
    end
  end
end
