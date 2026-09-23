# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryRemoteSettingsInput'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryRemoteSettingsInput') }

  it 'declares the writable settings fields and no read-only counterpart' do
    is_expected.to have_graphql_arguments(
      :url, :cache_validity_hours, :metadata_cache_validity_hours, :snapshot_metadata_always_revalidate,
      :credentials
    )
  end

  describe '#prepare' do
    subject(:prepared) { described_class.coerce_isolated_input(attributes).prepare }

    context 'when no field was supplied' do
      let(:attributes) { {} }

      it 'refuses the empty object rather than forwarding a zero patch' do
        expect { prepared }.to raise_error(GraphQL::ExecutionError, 'settings must carry at least one field')
      end
    end

    context 'when a subset of the writable fields was supplied' do
      let(:attributes) { { 'cacheValidityHours' => 24 } }

      it 'carries only that field, leaving every omitted one absent' do
        expect(prepared).to eq({ cache_validity_hours: 24 })
      end
    end

    context 'when every writable field was supplied' do
      let(:attributes) do
        {
          'url' => 'https://upstream.test',
          'cacheValidityHours' => 24,
          'metadataCacheValidityHours' => 1,
          'snapshotMetadataAlwaysRevalidate' => true
        }
      end

      it 'carries each one under its Artifact Registry name' do
        expect(prepared).to eq({
          url: 'https://upstream.test',
          cache_validity_hours: 24,
          metadata_cache_validity_hours: 1,
          snapshot_metadata_always_revalidate: true
        })
      end
    end

    context 'with the credential writes' do
      context 'when credentials were omitted' do
        let(:attributes) { { 'url' => 'https://upstream.test' } }

        it 'omits the key' do
          expect(prepared).not_to have_key(:credentials)
        end
      end

      context 'when a credential pair was supplied' do
        let(:attributes) { { 'credentials' => { 'username' => 'robot', 'password' => 'secret' } } }

        it 'unwraps the nested input to a plain Hash' do
          expect(prepared).to eq({ credentials: { username: 'robot', password: 'secret' } })
        end
      end

      context 'when a bearer token was supplied' do
        let(:attributes) { { 'credentials' => { 'authToken' => 'token' } } }

        it 'maps the token under the Artifact Registry name' do
          expect(prepared).to eq({ credentials: { auth_token: 'token' } })
        end
      end

      context 'when credentials were explicitly null' do
        let(:attributes) { { 'credentials' => nil } }

        it 'keeps the key with a nil value' do
          expect(prepared).to eq({ credentials: nil })
        end
      end
    end
  end
end
