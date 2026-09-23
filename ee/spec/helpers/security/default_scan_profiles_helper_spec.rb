# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DefaultScanProfilesHelper, feature_category: :security_testing_configuration do
  describe '.default_scan_profiles' do
    it 'returns an array of default scan profiles' do
      profiles = described_class.default_scan_profiles

      expect(profiles).to be_an(Array)
      expect(profiles).to all(be_a(Security::ScanProfile))
    end

    it 'includes all expected scan profiles' do
      profiles = described_class.default_scan_profiles

      expect(profiles.map(&:scan_type)).to match_array(
        %w[
          secret_detection sast dependency_scanning dependency_scanning_post_processing
          triage_and_remediation triage_and_remediation triage_and_remediation
        ]
      )
    end
  end

  shared_examples 'a default scan profile' do |scan_type:, name:, description:, trigger_types:|
    it "creates a #{scan_type} scan profile" do
      expect(profile).to be_a(Security::ScanProfile).and have_attributes(scan_type: scan_type)
    end

    it 'sets the correct attributes' do
      expect(profile).to have_attributes(
        name: name,
        gitlab_recommended: true,
        scan_type: scan_type,
        description: description
      )
    end

    it 'configures the correct trigger types' do
      expect(profile.scan_profile_triggers.size).to eq(trigger_types.size)
      expect(profile.scan_profile_triggers.map(&:trigger_type)).to match_array(trigger_types)
    end
  end

  describe '.build_secret_detection_scan_profile' do
    subject(:profile) { described_class.build_secret_detection_scan_profile }

    it_behaves_like 'a default scan profile',
      scan_type: 'secret_detection',
      name: 'Secret Detection (default)',
      description: "Protect your repository from leaked secrets like API keys, tokens, and passwords. " \
        "This profile uses industry-standard rules optimized to minimize false positives. " \
        "When enabled, secrets are detected in real time during git push events and blocked " \
        "before they're committed.",
      trigger_types: %w[git_push_event default_branch_pipeline merge_request_pipeline]
  end

  describe '.build_sast_scan_profile' do
    subject(:profile) { described_class.build_sast_scan_profile }

    it_behaves_like 'a default scan profile',
      scan_type: 'sast',
      name: 'SAST (default)',
      description: "Identify security vulnerabilities in your source code before they reach production. " \
        "This profile scans for issues like SQL injection, cross-site scripting, hardcoded credentials, and " \
        "insecure data handling. It uses GitLab's curated ruleset, continuously updated to detect real issues " \
        "while minimizing false positives.",
      trigger_types: %w[default_branch_pipeline merge_request_pipeline]
  end

  describe '.build_dependency_scanning_scan_profile' do
    subject(:profile) { described_class.build_dependency_scanning_scan_profile }

    it_behaves_like 'a default scan profile',
      scan_type: 'dependency_scanning',
      name: 'Dependency Scanning (default)',
      description: "Identify known vulnerabilities in your project's open source dependencies before they reach " \
        "production. This profile scans all dependencies — including transitive ones — across merge request and " \
        "branch pipelines, so security issues are caught early and compared against your default branch.",
      trigger_types: %w[default_branch_pipeline merge_request_pipeline]
  end

  describe '.build_dependency_scanning_post_processing_profile' do
    subject(:profile) { described_class.build_dependency_scanning_post_processing_profile }

    it_behaves_like 'a default scan profile',
      scan_type: 'dependency_scanning_post_processing',
      name: 'Dependency Scanning Auto-Remediation (default)',
      description: "Automatically resolve known vulnerabilities in your project's open source dependencies. " \
        "This profile opens merge requests that upgrade affected dependencies to secure versions whenever new " \
        "vulnerabilities are detected, so fixes are proposed for you without manual triage.",
      trigger_types: %w[sbom_ingested]
  end

  describe '.build_triage_and_remediation_profiles' do
    subject(:profiles) { described_class.build_triage_and_remediation_profiles }

    let(:trigger_types) do
      %w[
        vulnerability_enrichment sast_vulnerability_resolution sast_false_positive
        secret_detection_false_positive sbom_ingested
      ]
    end

    def configurations_by_trigger(profile)
      profile.scan_profile_triggers.to_h { |trigger| [trigger.trigger_type, trigger.configuration&.configuration] }
    end

    it 'builds one recommended profile per preset, each with every trigger', :aggregate_failures do
      expect(profiles.map(&:preset_key)).to eq(%w[
        triage_and_remediation_conservative
        triage_and_remediation_standard
        triage_and_remediation_proactive
      ])
      expect(profiles.map(&:name)).to eq([
        'Triage and Remediation (Conservative)',
        'Triage and Remediation (Standard)',
        'Triage and Remediation (Proactive)'
      ])
      expect(profiles).to all(have_attributes(scan_type: 'triage_and_remediation', gitlab_recommended: true))
      expect(profiles.map(&:description)).to all(be_present)
      expect(profiles.map { |profile| profile.scan_profile_triggers.map(&:trigger_type) })
        .to all(match_array(trigger_types))
    end

    it 'attaches configurations carrying only the values that differ from the defaults', :aggregate_failures do
      conservative, standard, proactive = profiles

      expect(configurations_by_trigger(conservative)).to eq(
        'vulnerability_enrichment' => { 'severity_level' => 'high' },
        'sast_vulnerability_resolution' => {
          'severity_level' => 'high', 'run_mode' => 'manual', 'open_merge_requests_limit' => 5
        },
        'sast_false_positive' => { 'severity_level' => 'high', 'run_mode' => 'manual' },
        'secret_detection_false_positive' => { 'severity_level' => 'high', 'run_mode' => 'manual' },
        'sbom_ingested' => { 'auto_remediation' => { 'open_merge_requests_limit' => 5 } }
      )
      expect(configurations_by_trigger(standard)).to eq(
        'vulnerability_enrichment' => nil,
        'sast_vulnerability_resolution' => nil,
        'sast_false_positive' => nil,
        'secret_detection_false_positive' => nil,
        'sbom_ingested' => nil
      )
      expect(configurations_by_trigger(proactive)).to eq(
        'vulnerability_enrichment' => { 'severity_level' => 'info' },
        'sast_vulnerability_resolution' => {
          'severity_level' => 'info', 'open_merge_requests_limit' => nil
        },
        'sast_false_positive' => { 'severity_level' => 'info' },
        'secret_detection_false_positive' => { 'severity_level' => 'info' },
        'sbom_ingested' => {
          'auto_remediation' => { 'severity_level' => 'info', 'upgrade_policy' => 'major' }
        }
      )
    end
  end
end
