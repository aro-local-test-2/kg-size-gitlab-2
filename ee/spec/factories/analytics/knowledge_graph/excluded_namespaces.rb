# frozen_string_literal: true

FactoryBot.define do
  factory :knowledge_graph_excluded_namespace, class: '::Analytics::KnowledgeGraph::ExcludedNamespace' do
    namespace { association(:group) }
  end
end
