# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Analytics::KnowledgeGraph::ExcludedNamespaceDestroy, :enable_admin_mode,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }

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
  end
end
