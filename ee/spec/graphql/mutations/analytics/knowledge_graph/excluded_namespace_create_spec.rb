# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Analytics::KnowledgeGraph::ExcludedNamespaceCreate, :enable_admin_mode,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:group) { create(:group) }

  let(:mutation) { described_class.new(object: nil, context: query_context(user: admin), field: nil) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_feature_flags(knowledge_graph: true)
    stub_licensed_features(orbit: true)
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  describe '#resolve' do
    context 'when the group does not exist' do
      it 'raises a resource not available error' do
        expect { mutation.resolve(group_path: non_existing_record_id.to_s) }
          .to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the group is a subgroup' do
      it 'returns the validation error' do
        subgroup = create(:group, parent: group)

        expect(mutation.resolve(group_path: subgroup.full_path)).to eq(
          group: nil,
          errors: ['Only top-level groups can be excluded']
        )
      end
    end

    context 'when another request creates the exclusion concurrently' do
      it 'returns the group without errors' do
        exclusion = build(:knowledge_graph_excluded_namespace, namespace: group)
        allow(Analytics::KnowledgeGraph::ExcludedNamespace).to receive(:find_or_initialize_for).and_return(exclusion)
        allow(exclusion).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

        expect(mutation.resolve(group_path: group.full_path)).to eq(group: group, errors: [])
      end
    end
  end
end
