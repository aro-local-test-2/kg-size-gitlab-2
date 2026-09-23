# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::PermissionTypes::ArtifactRegistry::Namespace, feature_category: :artifact_registry do
  let(:actions) { ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS }
  let(:declaring_type) { 'ArtifactRegistryRepositoryConnection' }
  let(:allowed_actions) { %w[read_repository create_repository] }
  let(:verdict_scope) { :namespace }
  let(:verdict_read) { :repositories }
  let(:expected_graphql_name) { 'ArtifactRegistryNamespacePermissions' }
  let(:extra_action) { 'read_artifact' }
  let(:missing_action) { 'create_repository' }

  it_behaves_like 'an artifact registry permission type'
end
