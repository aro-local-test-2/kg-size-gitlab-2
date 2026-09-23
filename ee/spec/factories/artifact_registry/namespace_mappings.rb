# frozen_string_literal: true

FactoryBot.define do
  factory :artifact_registry_namespace_mapping, class: 'ArtifactRegistry::NamespaceMapping' do
    organization { association(:common_organization) }
    # UUIDv7, matching what Artifact Registry mints for every primary key.
    # A v4 here is an id AR would never produce.
    ar_namespace_id { Gitlab::Utils.uuid_v7 }
  end
end
