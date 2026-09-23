# frozen_string_literal: true

require 'spec_helper'
require Rails.root.join('gems/gitlab-policy-store/spec/support/shared_examples/policy_repository_shared_examples')

# rubocop:disable Rails/SaveBang -- repository is the policy store port, not ActiveRecord; it has no create!
RSpec.describe Govern::PolicyStore::ActiveRecordPolicyRepository, feature_category: :security_policy_management do
  subject(:repository) { described_class.new }

  let_it_be(:group) { create(:group) }
  let_it_be(:other_organization) { create(:organization) }

  let(:organization_id) { group.organization_id }
  let(:broken_rule) do
    { 'type' => 'custom', 'value' => "package governance\n\nviolation contains {\"msg\": \"x\" if {" }
  end

  # The overrides belong in the block, not alongside it: a `let` inside the shared
  # example defines it on the nested group and would otherwise shadow ours.
  it_behaves_like 'a policy repository' do
    let(:namespace_id) { group.id }
    let(:other_organization_id) { other_organization.id }
    let(:trigger_type) { 'deployment_requested' }
    let(:other_trigger_type) { 'deployment_promoted' }
  end

  # Pins the ordering: both adapters must reject in the port, before ActiveRecord's own
  # phrasing can win, because callers surface these messages verbatim.
  describe 'validation message parity with the in-memory adapter' do
    let(:in_memory_repository) { ::Gitlab::PolicyStore::Adapters::InMemoryPolicyRepository.new }
    let(:valid_attributes) do
      { organization_id: organization_id, name: 'Parity policy', trigger_type: 'deployment_requested' }
    end

    def creation_message_from(repository, attributes)
      repository.create(attributes)

      nil
    rescue ::Gitlab::PolicyStore::ValidationError => error
      error.message
    end

    def update_message_from(repository, attributes)
      created = repository.create(valid_attributes)
      repository.update(created.id, attributes)

      nil
    rescue ::Gitlab::PolicyStore::ValidationError => error
      error.message
    end

    {
      'a name over the length limit' => { name: 'a' * 256 },
      'a description over the length limit' => { description: 'a' * 4097 },
      'a name of only whitespace' => { name: '   ' },
      'a nulled trigger type' => { trigger_type: nil },
      'a nulled rules array' => { rules: nil },
      'a mode outside the vocabulary' => { mode: 'bogus' },
      'a lifecycle_state outside the vocabulary' => { lifecycle_state: 'bogus' },
      'a trigger_type outside the vocabulary' => { trigger_type: 'bogus' }
    }.each do |rejected_case, invalid_attribute|
      it "rejects #{rejected_case} on create with the same message", :aggregate_failures do
        attributes = valid_attributes.merge(invalid_attribute)
        message = creation_message_from(repository, attributes)

        expect(message).to be_present
        expect(message).to eq(creation_message_from(in_memory_repository, attributes))
      end

      it "rejects #{rejected_case} on update with the same message", :aggregate_failures do
        message = update_message_from(repository, invalid_attribute)

        expect(message).to be_present
        expect(message).to eq(update_message_from(in_memory_repository, invalid_attribute))
      end
    end
  end

  describe '#create' do
    let(:create_attributes) do
      { organization_id: organization_id, namespace_id: group.id, name: 'Adapter policy',
        trigger_type: 'deployment_requested' }
    end

    it 'raises ValidationError when the organization does not own the namespace' do
      expect { repository.create(create_attributes.merge(organization_id: other_organization.id)) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /must match the owning namespace's organization/)
    end

    it 'raises ValidationError when validations fail' do
      repository.create(create_attributes)

      expect { repository.create(create_attributes) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /Name has already been taken/)
    end

    it 'raises ValidationError for unknown enum values' do
      expect { repository.create(create_attributes.merge(trigger_type: 'bogus')) }
        .to raise_error(Gitlab::PolicyStore::ValidationError,
          /trigger_type must be one of: deployment_requested, environment_advanced, deployment_promoted.*bogus/)
    end

    it 'returns copies of structured data, not references into the record' do
      policy = repository.create(create_attributes.merge(actions: [{ 'type' => 'require_approval' }]))
      policy.actions.first['injected'] = true

      expect(repository.find(policy.id).actions.first).not_to have_key('injected')
    end

    it 'persists scope_dimensions in the jsonb column, recoverable across a fresh find' do
      created = repository.create(create_attributes.merge(policy_scope: { compliance_frameworks: [{ id: 5 }] }))

      expect(repository.find(created.id).scope_dimensions).to eq(['compliance_frameworks'])
    end

    it 'translates the duplicate-name race the unique index loses to' do
      repository.create(create_attributes)
      allow_next_instance_of(Govern::Policy) do |policy|
        allow(policy).to receive(:valid?).and_return(true)
      end

      expect { repository.create(create_attributes) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, 'Name has already been taken')
    end

    it 'inserts no row when a rule does not parse', :aggregate_failures do
      expect { repository.create(create_attributes.merge(rules: [broken_rule])) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /\Arules\[0\] is invalid/)

      expect(Govern::Policy.where(name: 'Adapter policy')).to be_empty
    end

    it 'raises EngineError when the merged module does not parse', :aggregate_failures do
      allow_next_instance_of(Gitlab::PolicyStore::RuleProgramMerger) do |merger|
        allow(merger).to receive(:merge).and_return("package governance\n\nviolation contains {\n")
      end
      rules = [{ 'type' => 'environment', 'value' => { 'tiers' => ['production'] } }]

      expect { repository.create(create_attributes.merge(rules: rules)) }
        .to raise_error(Gitlab::PolicyStore::EngineError, /\Apolicy_merged_program is invalid/)

      expect(Govern::Policy.where(name: 'Adapter policy')).to be_empty
    end
  end

  describe '#list' do
    it 'clamps an oversized offset before it reaches the query, rather than scanning past it' do
      requested_offset = described_class::MAX_OFFSET + 12_345

      recorder = ActiveRecord::QueryRecorder.new do
        repository.list(organization_id: organization_id, offset: requested_offset)
      end

      expect(recorder.log.join).to include("OFFSET #{described_class::MAX_OFFSET} ")
      expect(recorder.log.join).not_to include("OFFSET #{requested_offset} ")
    end
  end

  describe '#update' do
    let(:policy) do
      repository.create(organization_id: organization_id, namespace_id: group.id,
        name: 'Update policy', trigger_type: 'deployment_requested')
    end

    it 'raises ValidationError for unknown enum values' do
      expect { repository.update(policy.id, { mode: 'bogus' }) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /mode must be one of: audit, warn, enforce.*bogus/)
    end

    it 'raises NotFound when the policy is deleted between the read and the lock' do
      id = policy.id
      allow_next_found_instance_of(Govern::Policy) do |record|
        allow(record).to receive(:with_lock).and_raise(ActiveRecord::RecordNotFound)
      end

      expect { repository.update(id, { name: 'Renamed' }) }
        .to raise_error(Gitlab::PolicyStore::NotFound, "Policy with id #{id} was not found")
    end

    # Create compiles from the caller's Hash and the rename recompiles from jsonb, so only
    # the round trip proves the two agree on more than the name.
    it 'recompiles a scope authored with symbol values without changing what it matches' do
      created = repository.create(organization_id: organization_id, name: 'Original name',
        trigger_type: 'deployment_requested',
        policy_scope: { match_mode: :any, groups: { including: [{ id: 10 }] } })

      updated = repository.update(created.id, name: 'Renamed policy')

      expect(updated.scope_rego).to include('Renamed policy')
      expect(updated.scope_rego.gsub('Renamed policy', 'Original name')).to eq(created.scope_rego)
    end

    it 'recomputes scope_dimensions when an update recompiles the scope' do
      created = repository.create(organization_id: organization_id, name: 'Originally scoped',
        trigger_type: 'deployment_requested', policy_scope: { compliance_frameworks: [{ id: 5 }] })

      updated = repository.update(created.id, policy_scope: { groups: { including: [{ id: 3 }] } })

      expect(updated.scope_dimensions).to eq(['groups'])
    end

    it 'generates a program on rename for a policy stored without one' do
      record = create(:govern_policy, namespace: group, scope_rego: nil, name: 'Original name')

      updated = repository.update(record.id, name: 'Renamed policy')

      expect(updated.scope_rego).to include('Renamed policy')
    end

    it 'leaves the row and its version untouched when a replacement rule does not parse', :aggregate_failures do
      expect { repository.update(policy.id, rules: [broken_rule]) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /\Arules\[0\] is invalid/)

      expect(Govern::Policy.find(policy.id)).to have_attributes(version: policy.version, rules: policy.rules)
    end
  end
end
# rubocop:enable Rails/SaveBang
