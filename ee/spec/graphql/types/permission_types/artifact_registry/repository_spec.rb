# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::PermissionTypes::ArtifactRegistry::Repository, feature_category: :artifact_registry do
  let(:actions) { ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS }
  let(:declaring_type) { 'ArtifactRegistryRepositoryDetails' }
  let(:allowed_actions) { %w[read_repository read_artifact] }
  let(:verdict_scope) { :repository }
  let(:verdict_read) { :repository }
  let(:expected_graphql_name) { 'ArtifactRegistryRepositoryPermissions' }
  let(:extra_action) { 'purge_repository' }
  let(:missing_action) { 'delete_artifact' }

  it_behaves_like 'an artifact registry permission type'
end
