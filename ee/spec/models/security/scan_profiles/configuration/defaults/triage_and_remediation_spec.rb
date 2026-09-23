# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::Configuration::Defaults::TriageAndRemediation,
  feature_category: :security_testing_configuration do
  let(:trigger_types) do
    %i[
      vulnerability_enrichment
      sast_vulnerability_resolution
      sast_false_positive
      secret_detection_false_positive
      sbom_ingested
    ]
  end

  def stored_values(preset)
    preset.to_h do |trigger_type, values|
      [trigger_type, Security::ScanProfiles::Configuration.strip_defaults(
        values,
        Security::ScanProfiles::Configuration.defaults_for(:triage_and_remediation, trigger_type)
      )]
    end
  end

  describe 'PRESETS' do
    it 'exposes the three presets, each covering every trigger type', :aggregate_failures do
      expect(described_class::PRESETS).to be_frozen
      expect(described_class::PRESETS).to eq(
        conservative: described_class::CONSERVATIVE,
        standard: described_class::STANDARD,
        proactive: described_class::PROACTIVE
      )
      expect(described_class::PRESETS.values.map(&:keys)).to all(match_array(trigger_types))
    end
  end

  describe 'STANDARD' do
    it 'declares the registered defaults, so nothing is stored for it', :aggregate_failures do
      expect(described_class::STANDARD).to be_frozen
      expect(described_class::STANDARD).to eq(
        vulnerability_enrichment: { severity_level: 'medium', run_mode: 'auto' },
        sast_vulnerability_resolution: {
          severity_level: 'medium', run_mode: 'auto', open_merge_requests_limit: 15
        },
        sast_false_positive: { severity_level: 'medium', run_mode: 'auto' },
        secret_detection_false_positive: { severity_level: 'medium', run_mode: 'auto' },
        sbom_ingested: Security::ScanProfiles::Configuration::Defaults::DependencyScanningPostProcessing::VALUES
      )
      expect(stored_values(described_class::STANDARD).values).to all(be_empty)
    end
  end

  describe 'CONSERVATIVE' do
    it 'stores only the values that differ from the defaults', :aggregate_failures do
      expect(described_class::CONSERVATIVE).to be_frozen
      expect(stored_values(described_class::CONSERVATIVE)).to eq(
        vulnerability_enrichment: { severity_level: 'high' },
        sast_vulnerability_resolution: {
          severity_level: 'high', run_mode: 'manual', open_merge_requests_limit: 5
        },
        sast_false_positive: { severity_level: 'high', run_mode: 'manual' },
        secret_detection_false_positive: { severity_level: 'high', run_mode: 'manual' },
        sbom_ingested: { auto_remediation: { open_merge_requests_limit: 5 } }
      )
    end
  end

  describe 'PROACTIVE' do
    it 'stores only the values that differ from the defaults', :aggregate_failures do
      expect(described_class::PROACTIVE).to be_frozen
      expect(stored_values(described_class::PROACTIVE)).to eq(
        vulnerability_enrichment: { severity_level: 'info' },
        sast_vulnerability_resolution: { severity_level: 'info', open_merge_requests_limit: nil },
        sast_false_positive: { severity_level: 'info' },
        secret_detection_false_positive: { severity_level: 'info' },
        sbom_ingested: { auto_remediation: { severity_level: 'info', upgrade_policy: 'major' } }
      )
    end
  end

  describe 'the stored configurations' do
    let(:scan_profile) { Security::ScanProfile.new(scan_type: :triage_and_remediation) }

    let(:stored_configurations) do
      described_class::PRESETS.values.flat_map { |preset| stored_values(preset).to_a }
        .reject { |_trigger_type, values| values.empty? }
    end

    it 'satisfies the JSON schema registered for their trigger type', :aggregate_failures do
      # The parents are unpersisted, so the record also carries unrelated `optional: false` errors.
      rejected = stored_configurations.filter_map do |trigger_type, values|
        configuration = Security::ScanProfiles::Configuration.new(
          scan_profile: scan_profile, configuration: values, trigger_type: trigger_type
        )
        configuration.valid?
        schema_errors = configuration.errors[:configuration]

        [trigger_type, values, schema_errors] if schema_errors.any?
      end

      expect(stored_configurations.size).to eq(10)
      expect(rejected).to be_empty
    end
  end
end
