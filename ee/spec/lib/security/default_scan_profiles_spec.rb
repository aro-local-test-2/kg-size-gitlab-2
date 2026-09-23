# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DefaultScanProfiles, feature_category: :security_testing_configuration do
  describe '.find_by_scan_type' do
    it 'returns the matching profile when scan type exists' do
      profile = described_class.find_by_scan_type(:secret_detection)

      expect(profile).to be_a(Security::ScanProfile).and have_attributes(scan_type: 'secret_detection')
    end

    it 'returns nil when scan type does not exist' do
      profile = described_class.find_by_scan_type(:non_existent_type)

      expect(profile).to be_nil
    end
  end

  describe '.find_by_preset_key' do
    it 'returns the default profile declaring the key', :aggregate_failures do
      defaults = described_class.all

      defaults.each do |default|
        expect(described_class.find_by_preset_key(default.preset_key))
          .to have_attributes(preset_key: default.preset_key, scan_type: default.scan_type, name: default.name)
      end
    end

    it 'still resolves the defaults whose key falls back to their scan type', :aggregate_failures do
      %w[secret_detection sast dependency_scanning dependency_scanning_post_processing].each do |scan_type|
        expect(described_class.find_by_preset_key(scan_type)).to have_attributes(scan_type: scan_type)
      end
    end

    it 'returns nil for a blank or unknown key', :aggregate_failures do
      expect(described_class.find_by_preset_key(nil)).to be_nil
      expect(described_class.find_by_preset_key('')).to be_nil
      expect(described_class.find_by_preset_key(:non_existent_key)).to be_nil
    end

    context 'when a scan type has several presets' do
      let(:preset_keys) do
        %w[
          triage_and_remediation_conservative
          triage_and_remediation_standard
          triage_and_remediation_proactive
        ]
      end

      it 'resolves each key to a distinct preset of that scan type', :aggregate_failures do
        presets = preset_keys.map { |preset_key| described_class.find_by_preset_key(preset_key) }

        expect(presets.map(&:preset_key)).to eq(preset_keys)
        expect(presets).to all(have_attributes(scan_type: 'triage_and_remediation'))
        expect(presets.map(&:name)).to contain_exactly(
          'Triage and Remediation (Conservative)',
          'Triage and Remediation (Standard)',
          'Triage and Remediation (Proactive)'
        )
      end
    end
  end

  describe '.virtual_identifier?' do
    it 'is true for a known types', :aggregate_failures do
      expect(described_class.virtual_identifier?('secret_detection')).to be(true)
      expect(described_class.virtual_identifier?('triage_and_remediation')).to be(true)
      expect(described_class.virtual_identifier?('triage_and_remediation_conservative')).to be(true)
    end

    it 'is false for blank, unknown and numeric identifiers', :aggregate_failures do
      expect(described_class.virtual_identifier?(nil)).to be(false)
      expect(described_class.virtual_identifier?('')).to be(false)
      expect(described_class.virtual_identifier?('non_existent_key')).to be(false)
      expect(described_class.virtual_identifier?('5')).to be(false)
    end
  end

  describe '.reserved_name?' do
    let(:default_name) { described_class.find_by_scan_type(:sast).name }

    it 'is true for a default profile name regardless of case' do
      expect(described_class.reserved_name?(default_name.downcase)).to be(true)
    end

    it 'is false for a custom name' do
      expect(described_class.reserved_name?('My SAST profile')).to be(false)
    end

    it 'is false for a blank name' do
      expect(described_class.reserved_name?(nil)).to be(false)
    end
  end
end
