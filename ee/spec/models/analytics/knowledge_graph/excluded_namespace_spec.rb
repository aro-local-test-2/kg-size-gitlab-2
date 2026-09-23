# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Analytics::KnowledgeGraph::ExcludedNamespace, feature_category: :knowledge_graph do
  let_it_be(:namespace) { create(:group) }

  describe 'relations' do
    it { is_expected.to belong_to(:namespace).inverse_of(:knowledge_graph_excluded_namespace) }
  end

  describe 'primary key' do
    it 'is root_namespace_id' do
      expect(described_class.primary_key).to eq('root_namespace_id')
    end
  end

  describe 'validations' do
    it 'allows top-level groups to be excluded' do
      expect(described_class.new(namespace: namespace)).to be_valid
    end

    it 'does not allow subgroups to be excluded' do
      excluded_namespace = described_class.new(namespace: create(:group, parent: namespace))

      expect(excluded_namespace).to be_invalid
      expect(excluded_namespace.errors[:base]).to include('Only top-level groups can be excluded')
    end

    it 'does not allow personal namespaces to be excluded' do
      excluded_namespace = described_class.new(root_namespace_id: create(:user_namespace).id)

      expect(excluded_namespace).to be_invalid
      expect(excluded_namespace.errors[:base]).to include('Only top-level groups can be excluded')
    end
  end

  describe '.for_root_namespace_id' do
    let_it_be(:excluded_namespace) { create(:knowledge_graph_excluded_namespace, namespace: namespace) }
    let_it_be(:another_excluded_namespace) { create(:knowledge_graph_excluded_namespace) }

    it 'returns records for the specified namespace' do
      expect(described_class.for_root_namespace_id(namespace.id)).to contain_exactly(excluded_namespace)
    end
  end

  describe '.find_or_initialize_for' do
    it 'finds an existing exclusion' do
      excluded_namespace = create(:knowledge_graph_excluded_namespace, namespace: namespace)

      expect(described_class.find_or_initialize_for(namespace)).to eq(excluded_namespace)
    end

    it 'initializes a new exclusion' do
      excluded_namespace = described_class.find_or_initialize_for(namespace)

      expect(excluded_namespace).to be_new_record
      expect(excluded_namespace.namespace).to eq(namespace)
    end
  end

  describe '.remove_for' do
    it 'removes the exclusion' do
      create(:knowledge_graph_excluded_namespace, namespace: namespace)

      expect { described_class.remove_for(namespace) }.to change { described_class.count }.by(-1)
    end
  end

  describe 'foreign key' do
    it 'deletes the exclusion when the namespace is deleted' do
      excluded_namespace = create(:knowledge_graph_excluded_namespace, namespace: namespace)

      Group.where(id: namespace.id).delete_all

      expect(described_class.find_by(root_namespace_id: excluded_namespace.root_namespace_id)).to be_nil
    end
  end
end
