# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::Tools::CleanupCheckReport, :geo, feature_category: :geo_replication do
  include ::EE::GeoHelpers

  let(:resolvable_error) do
    instance_double(Geo::Tools::KnownError,
      name: 'url_blocked',
      title: 'Download URL blocked',
      severity: 'warning',
      match_pattern: 'URL is blocked',
      affected_count_label: '2+',
      resolvable: true,
      docs: 'https://docs.gitlab.com/resolvable',
      to_h: { name: 'url_blocked' })
  end

  let(:manual_error) do
    instance_double(Geo::Tools::KnownError,
      name: 'orphaned_uploads',
      title: 'Orphaned uploads',
      severity: 'critical',
      match_pattern: nil,
      affected_count_label: '3',
      resolvable: false,
      docs: 'https://docs.gitlab.com/manual',
      to_h: { name: 'orphaned_uploads' })
  end

  before do
    stub_secondary_node
  end

  describe '#to_s' do
    it 'renders the header, one numbered entry per error, and the dry-run trailer' do
      report = described_class.new(proc { [resolvable_error, manual_error] })

      expect(report.to_s).to eq(<<~TEXT.chomp)

        1. Download URL blocked (warning)
           2+ records matching 'URL is blocked'
           -> Run: sudo gitlab-rake "geo:tools:resolve[url_blocked]" (dry run by default)

        2. Orphaned uploads (critical)
           3 records affected (structural check)
           -> Manual intervention required. Docs: https://docs.gitlab.com/manual

        Add DRY_RUN=false to a resolve task to actually apply it.
      TEXT
    end

    it 'names the scanned-for error and reports no issues when nothing was detected' do
      report = described_class.new(proc { [] }, scanned_for: 'url_blocked')

      expect(report.to_s).to eq(<<~TEXT.chomp)

        No known issues detected.
        Add DRY_RUN=false to a resolve task to actually apply it.
      TEXT
    end

    it 'labels the primary site' do
      stub_primary_node
      expected_response = [
        "Geo Cleanup Check -- Primary Site",
        '=' * 40,
        "Scanning for known issues..."
      ]
      report = described_class.new(proc { [] })
      expect(report.text_header).to match_array(expected_response)
    end
  end

  describe '#to_h' do
    it 'returns the scanning site and each error serialized via KnownError#to_h' do
      report = described_class.new(proc { [resolvable_error] })

      expect(report.to_h).to eq(scanned_on: 'secondary', detected_errors: [{ name: 'url_blocked' }],
        scanned_for: nil)
    end

    it 'reports the primary site' do
      stub_primary_node

      report = described_class.new(proc { [] })
      expect(report.to_h).to eq(scanned_on: 'primary', detected_errors: [], scanned_for: nil)
    end
  end

  describe '#to_pretty_json' do
    let(:report) { described_class.new(proc { [resolvable_error] }) }

    it 'serializes the hash form' do
      expect(Gitlab::Json::SafeParser.parse(report.to_pretty_json)).to eq(
        'scanned_for' => nil,
        'scanned_on' => 'secondary',
        'detected_errors' => [{ 'name' => 'url_blocked' }]
      )
    end

    it 'pretty-prints the document' do
      expect(report.to_pretty_json).to eq(<<~JSON.chomp)
        {
          "scanned_for": null,
          "scanned_on": "secondary",
          "detected_errors": [
            {
              "name": "url_blocked"
            }
          ]
        }
      JSON
    end
  end
end
