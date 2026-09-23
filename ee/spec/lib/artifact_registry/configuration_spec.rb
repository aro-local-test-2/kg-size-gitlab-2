# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Configuration, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  before do
    stub_config(artifact_registry: artifact_registry_config)
  end

  describe '.api_url' do
    context 'when the setting carries a path the predicate refuses' do
      let(:artifact_registry_config) { { api_url: 'https://artifact-registry.example.com/api/v1' } }

      it 'returns the value verbatim, leaving every judgement to .configured?' do
        expect(described_class.api_url).to eq('https://artifact-registry.example.com/api/v1')
      end
    end

    context 'when the instance never set the key' do
      let(:artifact_registry_config) { {} }

      it { expect(described_class.api_url).to be_nil }
    end
  end

  describe '.service_token_secret_file' do
    context 'when the stanza configures one' do
      let(:artifact_registry_config) do
        { api_url: 'https://artifact-registry.example.com', service_token: { secret_file: '/etc/secret' } }
      end

      it { expect(described_class.service_token_secret_file).to eq('/etc/secret') }
    end

    context 'when the stanza carries no service_token block' do
      let(:artifact_registry_config) { { api_url: 'https://artifact-registry.example.com' } }

      it 'returns nil rather than raising, so the credential path fails closed' do
        expect(described_class.service_token_secret_file).to be_nil
      end
    end

    context 'when the instance never set the stanza' do
      let(:artifact_registry_config) { {} }

      it { expect(described_class.service_token_secret_file).to be_nil }
    end
  end

  # The single place the accepted and rejected value classes are stated.
  describe '.configured? and .client_base_url' do
    let(:artifact_registry_config) { { api_url: api_url } }

    context 'with a value naming a bare http(s) origin' do
      where(:api_url, :expected_client_base_url) do
        'https://artifact-registry.example.com'         | 'https://artifact-registry.example.com'
        'https://artifact-registry.example.com/'        | 'https://artifact-registry.example.com'
        'http://artifact-registry.example.com:8080'     | 'http://artifact-registry.example.com:8080'
        'https://artifact-registry.example.com:443'     | 'https://artifact-registry.example.com:443'
        'http://localhost:8080'                         | 'http://localhost:8080'
      end

      with_them do
        it 'holds, reduces the setting to its origin, and constructs a client', :aggregate_failures do
          expect(described_class.configured?).to be true
          expect(described_class.client_base_url).to eq(expected_client_base_url)
          expect { ::ArtifactRegistry::Client.new(base_url: api_url) }.not_to raise_error
        end
      end
    end

    context 'with a value naming no usable credential-free origin' do
      where(:case_name, :api_url) do
        'the value is nil'                     | nil
        'the value is empty'                   | ''
        'the value is only whitespace'         | '   '
        'the value carries whitespace'         | 'https://artifact registry.example.com'
        'the value is surrounded by whitespace' | ' https://artifact-registry.example.com '
        'http names no host'                   | 'http://'
        'https names no host'                  | 'https://'
        'the value parses but resolves no host' | 'https:///v1'
        'the value names an empty ipv6 literal' | 'http://[]'
        'the value names no scheme'            | 'artifact-registry.example.com'
        'the value names only an authority'    | '//artifact-registry.example.com'
        'the value names a scheme no client speaks' | 'ftp://artifact-registry.example.com'
        'the value embeds a user and password' | 'https://user:pass@artifact-registry.example.com'
        'the value embeds a user'              | 'https://user@artifact-registry.example.com'
        'the value carries a path'             | 'https://artifact-registry.example.com/api/v1'
        'the value carries a path under a port' | 'https://artifact-registry.example.com:443/api/v1'
        'the value carries a query'            | 'https://artifact-registry.example.com?token=x'
        'the value carries a fragment'         | 'https://artifact-registry.example.com#frag'
        'the scheme is upper-case, which Addressable leaves unnormalized' | 'HTTPS://artifact-registry.example.com'
      end

      with_them do
        it 'does not hold, composes no browser-facing URL, and constructs no client',
          :aggregate_failures do
          expect(described_class.configured?).to be false
          expect(described_class.client_base_url).to be_nil
          expect { ::ArtifactRegistry::Client.new(base_url: api_url) }
            .to raise_error(::ArtifactRegistry::Client::ConfigurationError)
        end
      end
    end
  end
end
