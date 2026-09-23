# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::NamespaceEnrollment, feature_category: :secrets_management do
  subject(:enrollment) { build(:secrets_manager_namespace_enrollment) }

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).required }
  end

  describe 'defaults' do
    it 'marks new records as beta' do
      expect(create(:secrets_manager_namespace_enrollment).beta).to be true
    end
  end

  describe 'scopes' do
    describe '.for_namespace' do
      let_it_be(:group) { create(:group) }
      let_it_be(:other_group) { create(:group) }
      let_it_be(:enrollment) { create(:secrets_manager_namespace_enrollment, namespace: group) }
      let_it_be(:other_enrollment) { create(:secrets_manager_namespace_enrollment, namespace: other_group) }

      it 'returns enrollments for the given namespace' do
        expect(described_class.for_namespace(group)).to contain_exactly(enrollment)
      end
    end

    describe '.enabled and .disabled' do
      let_it_be(:enabled_enrollment) { create(:secrets_manager_namespace_enrollment) }
      let_it_be(:disabled_enrollment) { create(:secrets_manager_namespace_enrollment, :disabled) }

      it 'partitions enrollments by opt-out state' do
        expect(described_class.enabled).to contain_exactly(enabled_enrollment)
        expect(described_class.disabled).to contain_exactly(disabled_enrollment)
      end
    end

    describe '.with_add_on_requested' do
      let_it_be(:plain_enrollment) { create(:secrets_manager_namespace_enrollment) }
      let_it_be(:add_on_enrollment) { create(:secrets_manager_namespace_enrollment, :add_on_requested) }

      it 'returns only enrollments with recorded add-on intent' do
        expect(described_class.with_add_on_requested).to contain_exactly(add_on_enrollment)
      end
    end
  end

  describe '#enabled?' do
    it 'is true without a disabled_at timestamp' do
      expect(build(:secrets_manager_namespace_enrollment)).to be_enabled
    end

    it 'is false with a disabled_at timestamp' do
      expect(build(:secrets_manager_namespace_enrollment, :disabled)).not_to be_enabled
    end
  end

  describe '.opted_out?' do
    let_it_be(:group) { create(:group) }
    let(:namespace) { group }

    subject(:opted_out) { described_class.opted_out?(namespace) }

    context 'when the namespace explicitly opted out' do
      before_all do
        create(:secrets_manager_namespace_enrollment, :disabled, namespace: group)
      end

      it { is_expected.to be(true) }

      context 'when specified namespace has an ancestor' do
        let_it_be(:namespace) { create(:group, parent: group) }

        it 'checks the root ancestor' do
          is_expected.to be(true)
        end
      end
    end

    context 'when the namespace is enrolled' do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group)
      end

      it { is_expected.to be(false) }
    end

    context 'when the namespace was never enrolled' do
      it { is_expected.to be(false) }
    end
  end

  describe '.enrolled?' do
    let_it_be(:group) { create(:group) }

    context 'when namespace is enrolled' do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group)
      end

      it 'returns true' do
        expect(described_class.enrolled?(group)).to be true
      end
    end

    context 'when namespace is not enrolled' do
      it 'returns false' do
        expect(described_class.enrolled?(group)).to be false
      end
    end

    context 'when the namespace explicitly opted out' do
      before_all do
        create(:secrets_manager_namespace_enrollment, :disabled, namespace: group)
      end

      it 'returns false' do
        expect(described_class.enrolled?(group)).to be false
      end
    end

    context 'when a different namespace is enrolled' do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: create(:group))
      end

      it 'returns false' do
        expect(described_class.enrolled?(group)).to be false
      end
    end

    it 'checks the root ancestor' do
      subgroup = create(:group, parent: group)
      create(:secrets_manager_namespace_enrollment, namespace: group)

      expect(described_class.enrolled?(subgroup)).to be true
    end
  end

  describe '.add_on_requested?' do
    let_it_be(:group) { create(:group) }

    context 'when the namespace recorded add-on intent' do
      before_all do
        create(:secrets_manager_namespace_enrollment, :add_on_requested, namespace: group)
      end

      it 'returns true' do
        expect(described_class.add_on_requested?(group)).to be true
      end

      it 'checks the root ancestor' do
        subgroup = create(:group, parent: group)

        expect(described_class.add_on_requested?(subgroup)).to be true
      end
    end

    context 'when the namespace is enrolled without add-on intent' do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group)
      end

      it 'returns false' do
        expect(described_class.add_on_requested?(group)).to be false
      end
    end

    context 'when the enrollment with add-on intent is disabled' do
      before_all do
        create(:secrets_manager_namespace_enrollment, :disabled, :add_on_requested, namespace: group)
      end

      it 'returns false' do
        expect(described_class.add_on_requested?(group)).to be false
      end
    end

    context 'when the namespace was never enrolled' do
      it 'returns false' do
        expect(described_class.add_on_requested?(group)).to be false
      end
    end
  end

  describe '.beta_enrolled?' do
    let_it_be(:group) { create(:group) }

    context 'when the namespace has a beta enrollment' do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group, beta: true)
      end

      it 'returns true' do
        expect(described_class.beta_enrolled?(group)).to be true
      end

      it 'checks the root ancestor' do
        subgroup = create(:group, parent: group)

        expect(described_class.beta_enrolled?(subgroup)).to be true
      end
    end

    context 'when the enrollment is not beta' do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group, beta: false)
      end

      it 'returns false' do
        expect(described_class.beta_enrolled?(group)).to be false
      end
    end

    context 'when the beta enrollment opted out' do
      before_all do
        create(:secrets_manager_namespace_enrollment, :disabled, namespace: group, beta: true)
      end

      it 'returns false' do
        expect(described_class.beta_enrolled?(group)).to be false
      end
    end

    context 'when namespace is not enrolled' do
      it 'returns false' do
        expect(described_class.beta_enrolled?(group)).to be false
      end
    end
  end

  describe '.licensed_saas_root_group?' do
    let_it_be(:group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: group) }

    context 'when on GitLab.com', :saas do
      before do
        stub_licensed_features(native_secrets_management: true)
      end

      it 'returns true for a licensed root group' do
        expect(described_class.licensed_saas_root_group?(group)).to be true
      end

      it 'ignores the namespace enrollment feature flag' do
        stub_feature_flags(secrets_manager_namespace_enrollment: false)

        expect(described_class.licensed_saas_root_group?(group)).to be true
      end

      it 'returns false for a subgroup' do
        expect(described_class.licensed_saas_root_group?(subgroup)).to be false
      end

      it 'returns false for a user namespace' do
        expect(described_class.licensed_saas_root_group?(create(:user_namespace))).to be false
      end

      it 'returns false without the Secrets Manager license' do
        stub_licensed_features(native_secrets_management: false)

        expect(described_class.licensed_saas_root_group?(group)).to be false
      end
    end

    context 'when not on GitLab.com' do
      it 'returns false' do
        stub_licensed_features(native_secrets_management: true)

        expect(described_class.licensed_saas_root_group?(group)).to be false
      end
    end
  end

  describe '.enrollment_allowed?' do
    let_it_be(:group) { create(:group) }

    context 'when on GitLab.com', :saas do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      it 'returns true for a root namespace' do
        expect(described_class.enrollment_allowed?(group)).to be true
      end

      context 'when namespace is not root' do
        let_it_be(:subgroup) { create(:group, parent: group) }

        it 'returns false' do
          expect(described_class.enrollment_allowed?(subgroup)).to be false
        end
      end

      context 'when namespace is a user namespace' do
        let_it_be(:user_namespace) { create(:user_namespace) }

        it 'returns false' do
          expect(described_class.enrollment_allowed?(user_namespace)).to be false
        end
      end

      context 'when the namespace_enrollment feature flag is enabled only on the root_ancestor' do
        let_it_be(:subgroup) { create(:group, parent: group) }

        before do
          stub_feature_flags(secrets_manager_namespace_enrollment: false)
          stub_feature_flags(secrets_manager_namespace_enrollment: group)
        end

        it 'still returns false for non-root namespaces' do
          expect(described_class.enrollment_allowed?(subgroup)).to be false
        end
      end

      context 'when feature flag is disabled' do
        before do
          stub_feature_flags(secrets_manager_namespace_enrollment: false)
        end

        it 'returns false' do
          expect(described_class.enrollment_allowed?(group)).to be false
        end
      end

      context 'when license is not available' do
        before do
          stub_licensed_features(native_secrets_management: false)
        end

        it 'returns false' do
          expect(described_class.enrollment_allowed?(group)).to be false
        end
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      it 'returns false' do
        expect(described_class.enrollment_allowed?(group)).to be false
      end
    end
  end

  describe 'uniqueness constraint' do
    let_it_be(:group) { create(:group) }

    it 'prevents duplicate enrollments via the unique DB index' do
      create(:secrets_manager_namespace_enrollment, namespace: group)

      expect { create(:secrets_manager_namespace_enrollment, namespace: group) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
