# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::AiTriage::Eligibility, feature_category: :vulnerability_management do
  let_it_be(:group) { create(:group) }
  let_it_be_with_refind(:project) { create(:project, group: group) }
  let_it_be_with_reload(:vulnerability) { create(:vulnerability, :sast, :high, project: project) }

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  def attach_profile(triggers)
    profile = create(:security_scan_profile, :triage_and_remediation, namespace: group)

    triggers.each do |trigger_type, configuration_values|
      create(:security_scan_profile_trigger,
        scan_profile: profile, trigger_type: trigger_type, configuration_values: configuration_values)
    end

    create(:security_scan_profile_project, scan_profile: profile, project: project)

    profile
  end

  def cwe_identifier(name)
    instance_double(Vulnerabilities::Identifier, cwe?: true, name: name)
  end

  describe '.profile_for' do
    subject(:profile_for) { described_class.profile_for(project, :sast_false_positive) }

    context 'when a matching profile is attached' do
      let!(:profile) { attach_profile(sast_false_positive: nil) }

      it { is_expected.to eq(profile) }

      context 'when the profile is soft-deleted' do
        before do
          profile.destroy!
        end

        it { is_expected.to be_nil }
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(triage_and_remediation_profile: false)
        end

        it { is_expected.to be_nil }
      end

      context 'when the security_scan_profiles licence is absent' do
        before do
          stub_licensed_features(security_scan_profiles: false)
        end

        it { is_expected.to be_nil }
      end
    end

    context 'when the attached profile has a different trigger' do
      before do
        attach_profile(sast_vulnerability_resolution: nil)
      end

      it { is_expected.to be_nil }
    end

    context 'when no profile is attached' do
      it { is_expected.to be_nil }
    end

    context 'with an active request store', :request_store do
      before do
        attach_profile(sast_false_positive: nil)
      end

      it 'looks the profile up once per project and trigger' do
        expect(project).to receive(:security_scan_profile_for).once.and_call_original

        3.times { described_class.profile_for(project, :sast_false_positive) }
      end

      it 'memoizes the absence of a profile' do
        expect(project).to receive(:security_scan_profile_for).once.and_call_original

        2.times { described_class.profile_for(project, :vulnerability_enrichment) }
      end

      it 'builds the effective configuration once per project and trigger' do
        expect(Security::ScanProfiles::Configuration).to receive(:effective_for).once.and_call_original

        3.times { described_class.configuration_for(project, :sast_false_positive) }
      end
    end
  end

  describe '.enabled?' do
    subject { described_class.enabled?(project, :sast_false_positive) }

    context 'when a matching profile is attached' do
      before do
        attach_profile(sast_false_positive: nil)
      end

      it { is_expected.to be(true) }
    end

    context 'when no profile is attached' do
      it { is_expected.to be(false) }
    end
  end

  describe '.configuration_for' do
    subject(:configuration) { described_class.configuration_for(project, :sast_false_positive) }

    context 'when the trigger carries no configuration record' do
      before do
        attach_profile(sast_false_positive: nil)
      end

      it 'returns the preset defaults' do
        expect(configuration).to include(severity_level: 'medium', run_mode: 'auto')
      end
    end

    context 'when the trigger carries a configuration record' do
      before do
        attach_profile(sast_false_positive: { severity_level: 'critical', run_mode: 'manual' })
      end

      it 'returns the stored values merged over the defaults' do
        expect(configuration).to include(severity_level: 'critical', run_mode: 'manual')
      end
    end

    context 'when no profile is attached' do
      it { is_expected.to eq({}) }
    end
  end

  describe '.severity_allowed?' do
    subject(:severity_allowed) { described_class.severity_allowed?(vulnerability, :sast_false_positive) }

    context 'when no profile is attached' do
      before do
        vulnerability.severity = severity
      end

      where(:severity, :result) do
        [
          ['critical', true],
          ['high', true],
          ['medium', false],
          ['low', false],
          ['unknown', false],
          ['info', false]
        ]
      end

      with_them do
        it { is_expected.to be(result) }
      end
    end

    context 'when a profile sets a threshold' do
      before do
        attach_profile(sast_false_positive: { severity_level: threshold })
        vulnerability.severity = severity
      end

      where(:threshold, :severity, :result) do
        [
          ['low', 'critical', true],
          ['low', 'medium', true],
          ['low', 'low', true],
          # SEVERITY_LEVELS ranks `unknown` (2) below `low` (4), so a `low` threshold excludes `unknown`
          ['low', 'unknown', false],
          ['low', 'info', false],
          ['info', 'unknown', true],
          ['info', 'info', true],
          ['medium', 'high', true],
          ['medium', 'low', false],
          ['high', 'high', true],
          ['high', 'medium', false],
          ['critical', 'critical', true],
          ['critical', 'high', false]
        ]
      end

      with_them do
        it { is_expected.to be(result) }
      end
    end

    context 'when the trigger carries only the preset default threshold' do
      before do
        attach_profile(secret_detection_false_positive: nil)
      end

      it 'applies the default threshold rather than the hardcoded gate', :aggregate_failures do
        vulnerability.severity = 'medium'

        expect(described_class.severity_allowed?(vulnerability, :secret_detection_false_positive)).to be(true)

        vulnerability.severity = 'low'

        expect(described_class.severity_allowed?(vulnerability, :secret_detection_false_positive)).to be(false)
      end
    end

    context 'when the vulnerability has no project' do
      before do
        allow(vulnerability).to receive(:project).and_return(nil)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '.cwe_allowed?' do
    subject(:cwe_allowed) { described_class.cwe_allowed?(vulnerability, :sast_false_positive) }

    before do
      allow(vulnerability).to receive(:finding).and_return(finding)
    end

    let(:finding) { instance_double(Vulnerabilities::Finding, identifiers: [cwe_identifier('CWE-79')]) }

    context 'when no profile is attached' do
      it { is_expected.to be(true) }
    end

    context 'when the profile carries no cwe_classes' do
      before do
        attach_profile(sast_false_positive: { severity_level: 'low' })
      end

      it { is_expected.to be(true) }
    end

    context 'when the profile sets cwe_classes' do
      before do
        attach_profile(sast_false_positive: { cwe_classes: %w[CWE-79 CWE-89] })
      end

      context 'when the vulnerability CWE matches one of the classes' do
        it { is_expected.to be(true) }
      end

      context 'when the finding carries multiple CWE identifiers and only a later one matches' do
        let(:finding) { instance_double(Vulnerabilities::Finding, identifiers: [cwe_identifier('CWE-120'), cwe_identifier('CWE-89')]) }

        it { is_expected.to be(true) }
      end

      context 'when the matching class differs only by case' do
        let(:finding) { instance_double(Vulnerabilities::Finding, identifiers: [cwe_identifier('cwe-79')]) }

        it { is_expected.to be(true) }
      end

      context 'when the vulnerability CWE does not match any of the classes' do
        let(:finding) { instance_double(Vulnerabilities::Finding, identifiers: [cwe_identifier('CWE-22')]) }

        it { is_expected.to be(false) }
      end

      context 'when the vulnerability has no finding' do
        let(:finding) { nil }

        it { is_expected.to be(false) }
      end

      context 'when the finding has no CWE identifier' do
        let(:finding) { instance_double(Vulnerabilities::Finding, identifiers: []) }

        it { is_expected.to be(false) }
      end

      context 'with real identifier records' do
        let(:finding) do
          create(:vulnerabilities_finding, project: project, identifiers: [
            create(:vulnerabilities_identifier, project: project,
              external_type: 'cwe', external_id: 'CWE-79', name: 'CWE-79'),
            create(:vulnerabilities_identifier, project: project,
              external_type: 'owasp', external_id: 'A03', name: 'A03:2021-Injection')
          ])
        end

        it { is_expected.to be(true) }

        context 'when a non-CWE identifier is named like a CWE class' do
          let(:finding) do
            create(:vulnerabilities_finding, project: project, identifiers: [
              create(:vulnerabilities_identifier, project: project,
                external_type: 'owasp', external_id: 'A03', name: 'CWE-79')
            ])
          end

          it { is_expected.to be(false) }
        end
      end
    end

    context 'when the vulnerability has no project' do
      before do
        allow(vulnerability).to receive(:project).and_return(nil)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '.auto_run?' do
    subject(:auto_run) { described_class.auto_run?(vulnerability, :sast_false_positive) }

    context 'when no profile is attached' do
      it { is_expected.to be(true) }

      context 'when the severity is below the hardcoded gate' do
        before do
          vulnerability.severity = 'medium'
        end

        it { is_expected.to be(false) }
      end
    end

    context 'when the profile sets run_mode to auto' do
      before do
        attach_profile(sast_false_positive: { run_mode: 'auto', severity_level: 'low' })
      end

      it { is_expected.to be(true) }

      context 'when the severity is below the profile threshold' do
        before do
          vulnerability.severity = 'info'
        end

        it { is_expected.to be(false) }
      end
    end

    context 'when the profile sets run_mode to manual' do
      before do
        attach_profile(sast_false_positive: { run_mode: 'manual', severity_level: 'low' })
      end

      it { is_expected.to be(false) }
    end

    context 'when the profile sets cwe_classes' do
      let(:finding) { instance_double(Vulnerabilities::Finding, identifiers: [cwe_identifier('CWE-79')]) }

      before do
        attach_profile(sast_false_positive: { run_mode: 'auto', severity_level: 'low', cwe_classes: ['CWE-79'] })
        allow(vulnerability).to receive(:finding).and_return(finding)
      end

      context 'when the vulnerability CWE matches' do
        it { is_expected.to be(true) }
      end

      context 'when the vulnerability CWE does not match' do
        let(:finding) { instance_double(Vulnerabilities::Finding, identifiers: [cwe_identifier('CWE-22')]) }

        it { is_expected.to be(false) }
      end
    end

    context 'when the trigger type is sast_vulnerability_resolution' do
      subject(:auto_run) { described_class.auto_run?(vulnerability, :sast_vulnerability_resolution) }

      before do
        attach_profile(sast_vulnerability_resolution: {
          run_mode: 'auto', severity_level: 'low', cwe_classes: ['CWE-79']
        })
        allow(vulnerability).to receive(:finding)
          .and_return(instance_double(Vulnerabilities::Finding, identifiers: [cwe_identifier('CWE-22')]))
      end

      it { is_expected.to be(false) }
    end
  end
end
