# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::Policy, feature_category: :security_policy_management do
  subject(:policy) { build(:govern_policy) }

  describe 'associations' do
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to belong_to(:namespace).optional }
    it { is_expected.to have_many(:enforcements).inverse_of(:policy) }
    it { is_expected.to have_many(:evaluations).inverse_of(:policy) }
    it { is_expected.to have_many(:violations).inverse_of(:policy) }
  end

  describe 'enums' do
    it 'defines the CD deployment triggers' do
      is_expected.to define_enum_for(:trigger_type)
        .with_values(deployment_requested: 0, environment_advanced: 1, deployment_promoted: 2).with_prefix
    end

    it { is_expected.to define_enum_for(:mode).with_values(audit: 0, warn: 1, enforce: 2).with_prefix }
    it { is_expected.to define_enum_for(:lifecycle_state).with_values(active: 0, disabled: 1) }

    Gitlab::PolicyStore::Ports::PolicyRepository::ENUMERATED_ATTRIBUTES.each do |attribute, vocabulary|
      it "keeps the #{attribute} enum and the policy store vocabulary in step" do
        expect(described_class.public_send(attribute.to_s.pluralize).keys).to eq(vocabulary)
      end
    end
  end

  describe 'validations' do
    let_it_be_with_reload(:persisted_policy) { create(:govern_policy) }

    it { is_expected.to validate_presence_of(:trigger_type) }
    it { is_expected.to validate_numericality_of(:version).only_integer.is_greater_than(0) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:organization_id) }
    it { is_expected.to validate_length_of(:description).is_at_most(4096) }
    it { is_expected.to validate_length_of(:scope_rego).is_at_most(4096) }

    describe 'rules' do
      it 'is valid with a compiled rule' do
        policy.rules = [{ 'type' => 'custom', 'value' => 'package governance', 'rego' => 'package governance' }]

        expect(policy).to be_valid
      end

      it 'is invalid when rules is not an array', :aggregate_failures do
        policy.rules = { 'type' => 'custom' }

        expect(policy).not_to be_valid
        expect(policy.errors[:rules]).to be_present
      end

      it 'is invalid when a rule has no type', :aggregate_failures do
        policy.rules = [{ 'rego' => 'package governance' }]

        expect(policy).not_to be_valid
        expect(policy.errors[:rules]).to be_present
      end

      it 'is invalid when a rule has no rego', :aggregate_failures do
        policy.rules = [{ 'type' => 'custom' }]

        expect(policy).not_to be_valid
        expect(policy.errors[:rules]).to be_present
      end

      it 'is invalid when a rule has a blank rego', :aggregate_failures do
        policy.rules = [{ 'type' => 'custom', 'rego' => '' }]

        expect(policy).not_to be_valid
        expect(policy.errors[:rules]).to be_present
      end

      it 'is invalid when a rule has a non-String rego', :aggregate_failures do
        policy.rules = [{ 'type' => 'custom', 'rego' => 42 }]

        expect(policy).not_to be_valid
        expect(policy.errors[:rules]).to be_present
      end

      it 'is invalid when a rule carries an attribute outside type, value, and rego', :aggregate_failures do
        policy.rules = [{ 'type' => 'custom', 'rego' => 'package governance', 'extra' => 'nope' }]

        expect(policy).not_to be_valid
        expect(policy.errors[:rules]).to be_present
      end
    end

    it { is_expected.to be_valid }

    it 'applies the defaults from the schema' do
      expect(policy).to have_attributes(version: 1, mode: 'warn', lifecycle_state: 'active', rules: [])
    end

    context 'when the organization does not match the owning namespace' do
      subject(:policy) { build(:govern_policy, organization: create(:organization)) }

      it 'is invalid', :aggregate_failures do
        expect(policy).not_to be_valid
        expect(policy.errors[:organization_id]).to include("must match the owning namespace's organization")
      end
    end

    # Assigning an unsaved association writes nil over nil, so neither foreign key is dirty
    # and only new_record? brings the comparison in.
    context 'when a new policy is built with an unsaved organization' do
      subject(:policy) { build(:govern_policy, organization: build(:organization)) }

      it 'is invalid even though neither column changed', :aggregate_failures do
        expect(policy).not_to be_valid
        expect(policy.errors[:organization_id]).to include("must match the owning namespace's organization")
      end
    end

    context 'when a persisted policy moves to a namespace another organization owns' do
      it 'is invalid', :aggregate_failures do
        persisted_policy.namespace = create(:group, organization: create(:organization))

        expect(persisted_policy).not_to be_valid
        expect(persisted_policy.errors[:organization_id])
          .to include("must match the owning namespace's organization")
      end
    end

    context 'when a persisted policy moves to another organization' do
      it 'is invalid', :aggregate_failures do
        persisted_policy.organization = create(:organization)

        expect(persisted_policy).not_to be_valid
        expect(persisted_policy.errors[:organization_id])
          .to include("must match the owning namespace's organization")
      end
    end

    context 'when a persisted policy changes neither its namespace nor its organization' do
      it 'skips the comparison, leaving an already inconsistent row valid' do
        persisted_policy.update_column(:organization_id, create(:organization).id)
        persisted_policy.name = 'Renamed policy'

        expect(persisted_policy).to be_valid
      end
    end

    context 'when the policy has no namespace' do
      subject(:policy) { build(:govern_policy, :without_namespace) }

      it { is_expected.to be_valid }

      it 'rejects a second policy of the same name', :aggregate_failures do
        existing = create(:govern_policy, :without_namespace)
        duplicate = build(:govern_policy, :without_namespace,
          organization: existing.organization, name: existing.name)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include('has already been taken')
      end

      it 'rejects a group-owned policy of the same name in the same organization', :aggregate_failures do
        existing = create(:govern_policy, :without_namespace)
        group = create(:group, organization: existing.organization)
        group_owned = build(:govern_policy, namespace: group, name: existing.name)

        expect(group_owned).not_to be_valid
        expect(group_owned.errors[:name]).to include('has already been taken')
      end
    end

    it 'enforces name uniqueness in the database, so bypassing the validation still fails' do
      existing = create(:govern_policy)
      sibling_group = create(:group, organization: existing.organization)
      duplicate = build(:govern_policy, namespace: sibling_group, name: existing.name)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.for_organization' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:organization_policy) { create(:govern_policy, :without_namespace, organization: organization) }

    it 'returns only the policies of the given organization' do
      create(:govern_policy, :without_namespace, organization: create(:organization))

      expect(described_class.for_organization(organization.id)).to contain_exactly(organization_policy)
    end

    it 'includes disabled policies' do
      disabled = create(:govern_policy, :without_namespace,
        organization: organization, lifecycle_state: :disabled)

      expect(described_class.for_organization(organization.id)).to include(disabled)
    end
  end

  describe '.for_trigger_type' do
    let_it_be(:requested) { create(:govern_policy, trigger_type: :deployment_requested) }

    it 'returns only the policies for the given trigger' do
      create(:govern_policy, trigger_type: :deployment_promoted)

      expect(described_class.for_trigger_type(:deployment_requested)).to contain_exactly(requested)
    end

    it 'includes disabled policies' do
      disabled = create(:govern_policy, trigger_type: :deployment_requested, lifecycle_state: :disabled)

      expect(described_class.for_trigger_type(:deployment_requested)).to include(disabled)
    end
  end

  describe '.for_lifecycle_state' do
    let_it_be(:active) { create(:govern_policy) }

    it 'returns only the policies in the given lifecycle state' do
      create(:govern_policy, lifecycle_state: :disabled)

      expect(described_class.for_lifecycle_state(:active)).to contain_exactly(active)
    end

    it 'excludes policies in a different lifecycle state' do
      disabled = create(:govern_policy, lifecycle_state: :disabled)

      expect(described_class.for_lifecycle_state(:disabled)).to contain_exactly(disabled)
    end

    it 'returns no policies for nil, since nil can never match the NOT NULL column' do
      expect(described_class.for_lifecycle_state(nil)).to be_empty
    end

    it 'returns no policies for a value outside the enum, rather than raising' do
      expect(described_class.for_lifecycle_state('not_a_real_state')).to be_empty
    end
  end

  describe '.evaluation_candidates' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:group) { create(:group, organization: organization) }
    let_it_be(:policy) { create(:govern_policy, namespace: group, trigger_type: :deployment_requested) }

    it 'returns the named namespaces\' active policies for the trigger, oldest first' do
      newer = create(:govern_policy, namespace: group, trigger_type: :deployment_requested)
      create(:govern_policy, namespace: group, trigger_type: :deployment_promoted)
      create(:govern_policy, namespace: group, trigger_type: :deployment_requested, lifecycle_state: :disabled)
      create(:govern_policy, trigger_type: :deployment_requested)

      candidates = described_class.evaluation_candidates(
        organization_id: organization.id, trigger_type: :deployment_requested, namespace_ids: [group.id])

      expect(candidates).to eq([policy, newer])
    end

    it 'includes organization-wide policies together with the named namespaces' do
      without_namespace = create(:govern_policy, :without_namespace,
        organization: organization, trigger_type: :deployment_requested)

      candidates = described_class.evaluation_candidates(
        organization_id: organization.id, trigger_type: :deployment_requested, namespace_ids: [group.id])

      expect(candidates).to contain_exactly(policy, without_namespace)
    end

    # A group-authored policy must never enforce outside its subtree: a caller
    # that does not name the namespace does not receive its policies.
    it 'returns only organization-wide policies when no namespaces are named' do
      without_namespace = create(:govern_policy, :without_namespace,
        organization: organization, trigger_type: :deployment_requested)

      candidates = described_class.evaluation_candidates(
        organization_id: organization.id, trigger_type: :deployment_requested)

      expect(candidates).to contain_exactly(without_namespace)
    end

    it 'excludes namespaces the caller did not name' do
      other_group = create(:group, organization: organization)
      create(:govern_policy, namespace: other_group, trigger_type: :deployment_requested)

      candidates = described_class.evaluation_candidates(
        organization_id: organization.id, trigger_type: :deployment_requested, namespace_ids: [group.id])

      expect(candidates).to eq([policy])
    end

    it 'returns policies for every named namespace, not only the first' do
      other_group = create(:group, organization: organization)
      other_group_policy = create(:govern_policy, namespace: other_group, trigger_type: :deployment_requested)

      candidates = described_class.evaluation_candidates(
        organization_id: organization.id, trigger_type: :deployment_requested,
        namespace_ids: [group.id, other_group.id])

      expect(candidates).to contain_exactly(policy, other_group_policy)
    end

    it 'fetches one past EVALUATION_LIMIT, so the caller can detect truncation' do
      stub_const('Govern::Policy::EVALUATION_LIMIT', 1)
      create(:govern_policy, namespace: group, trigger_type: :deployment_requested)
      create(:govern_policy, namespace: group, trigger_type: :deployment_requested)

      candidates = described_class.evaluation_candidates(
        organization_id: organization.id, trigger_type: :deployment_requested, namespace_ids: [group.id])

      expect(candidates.size).to eq(2)
    end
  end
end
