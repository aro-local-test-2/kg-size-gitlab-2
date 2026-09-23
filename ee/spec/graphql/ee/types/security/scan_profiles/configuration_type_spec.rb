# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::ConfigurationType, feature_category: :security_testing_configuration do
  it { expect(described_class.graphql_name).to eq('ScanProfileConfiguration') }

  it 'is a union of the per-scan-type and per-trigger-type configuration types' do
    expect(described_class.possible_types).to contain_exactly(
      Types::Security::ScanProfiles::AutoRemediationConfigurationType,
      Types::Security::ScanProfiles::SastConfigurationType,
      Types::Security::ScanProfiles::SecretDetectionConfigurationType,
      Types::Security::ScanProfiles::SastFalsePositiveConfigurationType,
      Types::Security::ScanProfiles::SastVulnerabilityResolutionConfigurationType,
      Types::Security::ScanProfiles::SecretDetectionFalsePositiveConfigurationType,
      Types::Security::ScanProfiles::VulnerabilityEnrichmentConfigurationType
    )
  end

  it 'maps every remediation trigger type to a configuration type' do
    expect(described_class::TRIAGE_AND_REMEDIATION_TYPES.keys)
      .to match_array(Enums::Security.remediation_scan_profile_trigger_types.keys)
  end

  describe '.resolve_type' do
    let_it_be(:group) { create(:group) }

    context 'for a dependency scanning post-processing trigger' do
      let_it_be(:profile) do
        create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group)
      end

      let_it_be(:trigger) do
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :sbom_ingested,
          configuration_values: { 'auto_remediation' => { 'severity_level' => 'critical' } })
      end

      it 'resolves to the auto-remediation type with the effective auto-remediation config' do
        type, value = described_class.resolve_type(trigger, {})

        expect(type).to eq(Types::Security::ScanProfiles::AutoRemediationConfigurationType)
        expect(value).to include(severity_level: 'critical', cooldown: 7, upgrade_policy: 'minor')
      end

      it 'applies project-specific overrides when a project is supplied via scoped context' do
        project = instance_double(Project, duo_dependency_bump_breaking_changes_available?: true)

        _type, value = described_class.resolve_type(trigger, { scan_profile_project: project })

        expect(value).to include(upgrade_policy: 'major')
      end
    end

    context 'for a secret detection trigger' do
      let_it_be(:profile) do
        create(:security_scan_profile, namespace: group, scan_type: :secret_detection)
      end

      let_it_be(:trigger) do
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :default_branch_pipeline,
          configuration_values: { 'historic_scan' => true })
      end

      it 'resolves to the secret detection type with the effective config' do
        type, value = described_class.resolve_type(trigger, {})

        expect(type).to eq(Types::Security::ScanProfiles::SecretDetectionConfigurationType)
        expect(value).to include(historic_scan: true)
      end
    end

    context 'for a triage and remediation profile' do
      let_it_be(:profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }

      def trigger_for(trigger_type, configuration_values = nil)
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: trigger_type,
          configuration_values: configuration_values)
      end

      where(:trigger_type, :expected_type) do
        [
          [:sast_false_positive, Types::Security::ScanProfiles::SastFalsePositiveConfigurationType],
          [:sast_vulnerability_resolution,
            Types::Security::ScanProfiles::SastVulnerabilityResolutionConfigurationType],
          [:secret_detection_false_positive,
            Types::Security::ScanProfiles::SecretDetectionFalsePositiveConfigurationType],
          [:vulnerability_enrichment, Types::Security::ScanProfiles::VulnerabilityEnrichmentConfigurationType]
        ]
      end

      with_them do
        it 'resolves to the type keyed by trigger type', :aggregate_failures do
          type, value = described_class.resolve_type(trigger_for(trigger_type), {})

          expect(type).to eq(expected_type)
          expect(value).to eq(
            ::Security::ScanProfiles::Configuration.defaults_for(:triage_and_remediation, trigger_type)
          )
        end
      end

      it 'resolves the sbom_ingested trigger to the auto-remediation type', :aggregate_failures do
        trigger = trigger_for(:sbom_ingested)

        type, value = described_class.resolve_type(trigger, {})

        expect(type).to eq(Types::Security::ScanProfiles::AutoRemediationConfigurationType)
        expect(value).to include(cooldown: 7, upgrade_policy: 'minor')
      end

      it 'applies project-specific overrides to the sbom_ingested trigger' do
        project = instance_double(Project, duo_dependency_bump_breaking_changes_available?: true)

        _type, value = described_class.resolve_type(trigger_for(:sbom_ingested), { scan_profile_project: project })

        expect(value).to include(upgrade_policy: 'major')
      end

      it 'merges the stored override over the preset defaults', :aggregate_failures do
        trigger = trigger_for(:sast_vulnerability_resolution, { 'open_merge_requests_limit' => nil })

        _type, value = described_class.resolve_type(trigger, {})

        expect(value).to include(severity_level: 'medium', open_merge_requests_limit: nil)
      end
    end

    context 'for a SAST profile' do
      let_it_be(:profile) { create(:security_scan_profile, namespace: group, scan_type: :sast) }

      let_it_be(:trigger) do
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :default_branch_pipeline,
          configuration_values: { 'gitlab_adv_sast_incr_scan' => true })
      end

      it 'resolves to the SAST type with the effective config', :aggregate_failures do
        type, value = described_class.resolve_type(trigger, {})

        expect(type).to eq(Types::Security::ScanProfiles::SastConfigurationType)
        expect(value).to include(gitlab_adv_sast_incr_scan: true)
      end

      context 'without a stored configuration override' do
        let_it_be(:unconfigured_trigger) do
          create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :merge_request_pipeline)
        end

        it 'resolves to the SAST type with an empty effective config' do
          expect(described_class.resolve_type(unconfigured_trigger, {}))
            .to eq([Types::Security::ScanProfiles::SastConfigurationType, {}])
        end
      end
    end

    context 'for a scan type without a typed configuration' do
      let_it_be(:profile) { create(:security_scan_profile, namespace: group, scan_type: :dependency_scanning) }

      let_it_be(:trigger) do
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :default_branch_pipeline)
      end

      it 'resolves to nil' do
        expect(described_class.resolve_type(trigger, {})).to be_nil
      end
    end
  end
end
