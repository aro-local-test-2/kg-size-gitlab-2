# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryRemoteSettings'], feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  let(:ctx) { { skip_type_authorization: [:read_artifact_registry] } }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryRemoteSettings') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the readable settings fields, and no credential value' do
    is_expected.to have_graphql_fields(
      :url, :cache_validity_hours, :metadata_cache_validity_hours, :snapshot_metadata_always_revalidate,
      :has_credentials, :credentials_cleared, :last_health_status, :last_health_checked_at
    )
  end

  describe 'field types' do
    where(:field_name, :type_name) do
      'url'                              | 'String'
      'cacheValidityHours'               | 'Int'
      'metadataCacheValidityHours'       | 'Int'
      'snapshotMetadataAlwaysRevalidate' | 'Boolean'
      'hasCredentials'                   | 'Boolean'
      'credentialsCleared'               | 'Boolean'
      'lastHealthStatus'                 | 'ArtifactRegistryHealthStatus'
      'lastHealthCheckedAt'              | 'Time'
    end

    with_them do
      it 'renders the field as the declared type, nullable' do
        field = described_class.fields[field_name]

        expect(field.type.unwrap.graphql_name).to eq(type_name)
        expect(field.type).to be_nullable
      end
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end

  describe '#last_health_status' do
    let(:enum) { described_class.fields['lastHealthStatus'].type.unwrap }

    where(:artifact_registry_value, :graphql_value) do
      'unknown'   | 'UNKNOWN'
      'healthy'   | 'HEALTHY'
      'unhealthy' | 'UNHEALTHY'
    end

    with_them do
      it 'passes the recorded verdict through' do
        expect(resolved_status('last_health_status' => artifact_registry_value)).to eq(graphql_value)
      end
    end

    it 'reports UNKNOWN for a status Artifact Registry added ahead of this enum' do
      expect(resolved_status('last_health_status' => 'degraded')).to eq('UNKNOWN')
    end

    it 'reports UNKNOWN when no probe has recorded a status' do
      expect(resolved_status({})).to eq('UNKNOWN')
    end

    def resolved_status(settings)
      enum.coerce_isolated_result(resolve_field(:last_health_status, settings, ctx: ctx))
    end
  end

  describe '#last_health_checked_at' do
    it 'parses the ISO8601 timestamp Artifact Registry stores' do
      expect(resolved_time('last_health_checked_at' => '2026-07-01T10:00:00Z'))
        .to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
    end

    it 'reports no timestamp for a value it cannot parse, rather than failing the query' do
      expect(resolved_time('last_health_checked_at' => 'not-a-timestamp')).to be_nil
    end

    it 'reports no timestamp before the first probe' do
      expect(resolved_time({})).to be_nil
    end

    def resolved_time(settings)
      resolve_field(:last_health_checked_at, settings, ctx: ctx)
    end
  end
end
