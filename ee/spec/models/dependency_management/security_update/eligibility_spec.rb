# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::Eligibility, feature_category: :dependency_management do
  describe '.remediable?' do
    subject(:remediable) { described_class.remediable?(vulnerability) }

    let(:vulnerability) { instance_double(Vulnerability, solution: solution) }

    context 'when the solution is present and describes a fix' do
      let(:solution) { 'Upgrade rails to 6.1.7.10 or above.' }

      it { is_expected.to be(true) }
    end

    context 'when the solution is nil' do
      let(:solution) { nil }

      it { is_expected.to be(false) }
    end

    context 'when the solution is blank' do
      let(:solution) { '   ' }

      it { is_expected.to be(false) }
    end

    context 'when the solution is the templated "no solution" message' do
      let(:solution) { 'Unfortunately, there is no solution available yet.' }

      it { is_expected.to be(false) }
    end

    context 'when the "no solution" message has no comma' do
      let(:solution) { 'Unfortunately there is no solution available.' }

      it { is_expected.to be(false) }
    end
  end

  describe '.remediation_profile' do
    subject(:remediation_profile) { described_class.remediation_profile(project) }

    let_it_be(:project) { create(:project) }
    let(:profile) { instance_double(Security::ScanProfile) }

    context 'when the project is nil' do
      let(:project) { nil }

      it { is_expected.to be_nil }
    end

    context 'when the project is present' do
      before do
        allow(project).to receive(:security_scan_profile_for)
          .with(%i[dependency_scanning_post_processing triage_and_remediation], :sbom_ingested)
          .and_return(profiles)
      end

      context 'when a matching profile exists' do
        let(:profiles) { [profile] }

        it { is_expected.to eq(profile) }
      end

      context 'when no matching profile exists' do
        let(:profiles) { [] }

        it { is_expected.to be_nil }
      end

      context 'when the lookup returns nil' do
        let(:profiles) { nil }

        it { is_expected.to be_nil }
      end
    end

    context 'with persisted scan profiles' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project) { create(:project, group: group) }

      let_it_be(:triage_profile) do
        create(:security_scan_profile, :triage_and_remediation, namespace: group)
      end

      let_it_be(:triage_profile_project) do
        create(:security_scan_profile_project, scan_profile: triage_profile, project: project)
      end

      before do
        stub_licensed_features(security_scan_profiles: true)
      end

      context 'when only a triage-and-remediation profile is wired to the sbom-ingested trigger' do
        let_it_be(:triage_trigger) do
          create(:security_scan_profile_trigger, :sbom_ingested, scan_profile: triage_profile)
        end

        it { is_expected.to eq(triage_profile) }
      end

      context 'when both profile types are wired to the sbom-ingested trigger' do
        let_it_be(:triage_trigger) do
          create(:security_scan_profile_trigger, :sbom_ingested, scan_profile: triage_profile)
        end

        let_it_be(:post_processing_profile) do
          create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group)
        end

        let_it_be(:post_processing_profile_project) do
          create(:security_scan_profile_project, scan_profile: post_processing_profile, project: project)
        end

        let_it_be(:post_processing_trigger) do
          create(:security_scan_profile_trigger, :sbom_ingested, scan_profile: post_processing_profile)
        end

        it 'returns the oldest matching profile' do
          expect(remediation_profile).to eq([triage_profile, post_processing_profile].min_by(&:id))
        end
      end

      context 'when the triage-and-remediation profile has no sbom-ingested trigger' do
        let_it_be(:triage_trigger) do
          create(:security_scan_profile_trigger, scan_profile: triage_profile, trigger_type: :vulnerability_enrichment)
        end

        it { is_expected.to be_nil }
      end
    end
  end

  describe '.remediation_configuration' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:profile) { create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group) }
    let_it_be(:scan_profile_project) { create(:security_scan_profile_project, scan_profile: profile, project: project) }
    let_it_be(:trigger) do
      create(:security_scan_profile_trigger, :sbom_ingested, scan_profile: profile,
        configuration_values: { auto_remediation: { cooldown: 3 } })
    end

    subject(:remediation_configuration) { described_class.remediation_configuration(project) }

    before do
      stub_licensed_features(security_scan_profiles: true)
    end

    it 'returns the configuration resolved from the sbom-ingested trigger' do
      expect(remediation_configuration.dig(:auto_remediation, :cooldown)).to eq(3)
    end

    context 'with a triage-and-remediation profile' do
      let_it_be(:triage_project) { create(:project, group: group) }
      let_it_be(:triage_profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }
      let_it_be(:triage_profile_project) do
        create(:security_scan_profile_project, scan_profile: triage_profile, project: triage_project)
      end

      let_it_be(:triage_trigger) do
        create(:security_scan_profile_trigger, :sbom_ingested, scan_profile: triage_profile,
          configuration_values: { auto_remediation: { cooldown: 5, upgrade_policy: 'minor' } })
      end

      subject(:remediation_configuration) { described_class.remediation_configuration(triage_project) }

      it 'returns the configuration resolved from the sbom-ingested trigger', :aggregate_failures do
        expect(remediation_configuration.dig(:auto_remediation, :cooldown)).to eq(5)
        expect(remediation_configuration.dig(:auto_remediation, :upgrade_policy)).to eq('minor')
      end
    end
  end
end
