# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::AcceptsRemoteSettings, feature_category: :artifact_registry do
  [
    ::Mutations::ArtifactRegistry::Repositories::Create,
    ::Mutations::ArtifactRegistry::Repositories::Update
  ].each do |mutation_class|
    context "with #{mutation_class}" do
      subject(:argument) { mutation_class.arguments['settings'] }

      it 'declares the settings argument as an optional remote settings input', :aggregate_failures do
        expect(argument).to be_present
        expect(argument.type).to eq(::Types::ArtifactRegistry::RemoteSettingsInputType)
      end
    end
  end
end
