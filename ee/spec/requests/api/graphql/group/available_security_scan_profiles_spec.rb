# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying available security scan profiles', feature_category: :security_testing_configuration do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user) }

  let_it_be(:scan_profile) do
    create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group)
  end

  let_it_be(:trigger) do
    create(:security_scan_profile_trigger, scan_profile: scan_profile, trigger_type: :sbom_ingested,
      configuration_values: { 'auto_remediation' => { 'severity_level' => 'critical' } })
  end

  let(:profiles_field) do
    query_graphql_field(
      :available_security_scan_profiles,
      { type: :DEPENDENCY_SCANNING_POST_PROCESSING },
      'name configuration'
    )
  end

  let(:query) do
    graphql_query_for(:group, { full_path: group.full_path }, profiles_field)
  end

  # gitlab-recommended defaults sort ahead of persisted profiles, so position in the response
  # is unstable; look profiles up by name instead.
  def returned_profile(name)
    graphql_data_at(:group, :available_security_scan_profiles).find { |profile| profile['name'] == name }
  end

  def create_post_processing_profile(name)
    profile = create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group, name: name)
    create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :sbom_ingested,
      configuration_values: { 'auto_remediation' => { 'severity_level' => 'high' } })
    profile
  end

  before_all do
    group.add_developer(user)
  end

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  it 'returns the effective configuration, merging the persisted override with defaults' do
    post_graphql(query, current_user: user)

    configuration = returned_profile(scan_profile.name)['configuration']

    expect(configuration).to include(
      'auto_remediation' => a_hash_including(
        'severity_level' => 'critical',
        'cooldown' => 7
      )
    )
  end

  it 'does not run additional queries as the number of profiles grows' do
    post_graphql(query, current_user: user) # warm up before recording the control
    control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }
    expect(graphql_data_at(:group, :available_security_scan_profiles)).to be_present

    create_post_processing_profile('second profile')
    create_post_processing_profile('third profile')

    expect { post_graphql(query, current_user: user) }.not_to exceed_query_limit(control)
  end

  describe 'the Triage and Remediation presets' do
    let(:profiles_field) do
      query_graphql_field(
        :available_security_scan_profiles,
        { type: :TRIAGE_AND_REMEDIATION },
        'name scanType triggers'
      )
    end

    let(:preset_triggers) do
      %w[VULNERABILITY_ENRICHMENT SAST_VULNERABILITY_RESOLUTION SAST_FALSE_POSITIVE
        SECRET_DETECTION_FALSE_POSITIVE SBOM_INGESTED]
    end

    it 'serializes every preset with all of its trigger types' do
      post_graphql(query, current_user: user)

      expect(graphql_data_at(:group, :available_security_scan_profiles)).to match_array(
        %w[Conservative Standard Proactive].map do |preset|
          a_hash_including(
            'name' => "Triage and Remediation (#{preset})",
            'scanType' => 'TRIAGE_AND_REMEDIATION',
            'triggers' => match_array(preset_triggers)
          )
        end
      )
    end

    context 'when the triage_and_remediation_profile flag is disabled' do
      before do
        stub_feature_flags(triage_and_remediation_profile: false)
      end

      it 'returns no presets' do
        post_graphql(query, current_user: user)

        expect(graphql_data_at(:group, :available_security_scan_profiles)).to be_empty
      end
    end
  end

  describe 'triggerSettings' do
    let(:trigger_settings_selection) do
      <<~SELECTION
        triggerType
        configuration {
          __typename
          ... on AutoRemediationConfiguration {
            enabled
            cooldown
            severityLevel
            upgradePolicy
            openMergeRequestsLimit
            runnerTags
          }
          ... on SecretDetectionConfiguration {
            historicScan
            imageSuffix
          }
          ... on SastConfiguration {
            secureAnalyzersPrefix
            imageSuffix
            analyzerImageTag
            excludedAnalyzers
            excludedPaths
            advancedSastPartialScan
            gitlabAdvSastIncrScan
          }
          ... on SastFalsePositiveConfiguration {
            severityLevel
            runMode
            cweClasses
          }
          ... on SastVulnerabilityResolutionConfiguration {
            severityLevel
            runMode
            cweClasses
            openMergeRequestsLimit
            falsePositiveConfidence
          }
          ... on SecretDetectionFalsePositiveConfiguration {
            runMode
          }
          ... on VulnerabilityEnrichmentConfiguration {
            severityLevel
            runMode
          }
        }
      SELECTION
    end

    def profiles_with_trigger_settings(type)
      graphql_query_for(:group, { full_path: group.full_path },
        query_graphql_field(
          :available_security_scan_profiles, { type: type },
          ['name', query_graphql_field(:trigger_settings, {}, trigger_settings_selection)]
        ))
    end

    it 'exposes the trigger with its strongly-typed effective auto-remediation configuration' do
      post_graphql(profiles_with_trigger_settings(:DEPENDENCY_SCANNING_POST_PROCESSING), current_user: user)

      settings = returned_profile(scan_profile.name)['triggerSettings']
      setting = settings.find { |s| s['triggerType'] == 'SBOM_INGESTED' }

      configuration = setting['configuration']

      expect(configuration['__typename']).to eq('AutoRemediationConfiguration')
      expect(configuration).to include(
        'severityLevel' => 'CRITICAL', # persisted override
        'cooldown' => 7,               # merged default
        'upgradePolicy' => 'MINOR'     # merged default
      )
    end

    context 'with a secret detection profile' do
      let_it_be(:secret_detection_profile) do
        create(:security_scan_profile, namespace: group, scan_type: :secret_detection, name: 'SD')
      end

      let_it_be(:secret_detection_trigger) do
        create(:security_scan_profile_trigger, scan_profile: secret_detection_profile,
          trigger_type: :default_branch_pipeline,
          configuration_values: { 'historic_scan' => true, 'image_suffix' => '-fips' })
      end

      it 'exposes the strongly-typed secret detection configuration' do
        post_graphql(profiles_with_trigger_settings(:SECRET_DETECTION), current_user: user)

        settings = returned_profile(secret_detection_profile.name)['triggerSettings']
        configuration = settings.first['configuration']

        expect(configuration['__typename']).to eq('SecretDetectionConfiguration')
        expect(configuration).to include(
          'historicScan' => true,
          'imageSuffix' => 'FIPS'
        )
      end

      it 'does not run additional queries as the number of triggers on a profile grows' do
        query = profiles_with_trigger_settings(:SECRET_DETECTION)
        post_graphql(query, current_user: user) # warm up before recording the control
        control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }

        # ScanProfiles::ConfigurationType.resolve_type reads `object.scan_profile` per trigger; the `inverse_of` on
        # the trigger's `belongs_to :scan_profile` keeps that in memory, so adding triggers to a
        # single profile must not add queries.
        create(:security_scan_profile_trigger, scan_profile: secret_detection_profile,
          trigger_type: :git_push_event)
        create(:security_scan_profile_trigger, scan_profile: secret_detection_profile,
          trigger_type: :merge_request_pipeline,
          configuration_values: { 'historic_scan' => true })

        expect { post_graphql(query, current_user: user) }.not_to exceed_query_limit(control)
      end
    end

    context 'with the Triage and Remediation presets' do
      def configuration_for(profile_name, trigger_type)
        returned_profile(profile_name)['triggerSettings']
          .find { |setting| setting['triggerType'] == trigger_type }['configuration']
      end

      before do
        post_graphql(profiles_with_trigger_settings(:TRIAGE_AND_REMEDIATION), current_user: user)
      end

      it 'resolves each trigger to the type keyed by its trigger type', :aggregate_failures do
        expect(graphql_errors).to be_nil
        expect(returned_profile('Triage and Remediation (Standard)')['triggerSettings']).to contain_exactly(
          a_hash_including('triggerType' => 'VULNERABILITY_ENRICHMENT',
            'configuration' => a_hash_including('__typename' => 'VulnerabilityEnrichmentConfiguration')),
          a_hash_including('triggerType' => 'SAST_VULNERABILITY_RESOLUTION',
            'configuration' => a_hash_including('__typename' => 'SastVulnerabilityResolutionConfiguration')),
          a_hash_including('triggerType' => 'SAST_FALSE_POSITIVE',
            'configuration' => a_hash_including('__typename' => 'SastFalsePositiveConfiguration')),
          a_hash_including('triggerType' => 'SECRET_DETECTION_FALSE_POSITIVE',
            'configuration' => a_hash_including('__typename' => 'SecretDetectionFalsePositiveConfiguration')),
          a_hash_including('triggerType' => 'SBOM_INGESTED',
            'configuration' => a_hash_including('__typename' => 'AutoRemediationConfiguration'))
        )
      end

      it 'exposes the preset overrides merged over the Standard defaults', :aggregate_failures do
        expect(configuration_for('Triage and Remediation (Conservative)', 'SAST_FALSE_POSITIVE')).to include(
          'severityLevel' => 'HIGH', 'runMode' => 'MANUAL'
        )

        # Standard is the baseline, so it stores no override and reads back from the defaults.
        expect(configuration_for('Triage and Remediation (Standard)', 'SAST_VULNERABILITY_RESOLUTION')).to include(
          'severityLevel' => 'MEDIUM', 'runMode' => 'AUTO', 'openMergeRequestsLimit' => 15
        )

        # Proactive's explicit nil means "no limit" and must win over the default of 15.
        expect(configuration_for('Triage and Remediation (Proactive)', 'SAST_VULNERABILITY_RESOLUTION')).to include(
          'severityLevel' => 'INFO', 'openMergeRequestsLimit' => nil
        )
      end
    end

    context 'with a persisted triage and remediation profile' do
      let_it_be(:remediation_profile) do
        create(:security_scan_profile, :triage_and_remediation, namespace: group, name: 'Custom triage')
      end

      let_it_be(:enrichment_trigger) do
        create(:security_scan_profile_trigger, scan_profile: remediation_profile,
          trigger_type: :vulnerability_enrichment,
          configuration_values: { 'run_mode' => 'manual' })
      end

      let_it_be(:resolution_trigger) do
        create(:security_scan_profile_trigger, scan_profile: remediation_profile,
          trigger_type: :sast_vulnerability_resolution,
          configuration_values: {
            'cwe_classes' => ['CWE-89'], 'false_positive_confidence' => 'likely_not_false_positive'
          })
      end

      def configuration_for(trigger_type)
        returned_profile('Custom triage')['triggerSettings']
          .find { |setting| setting['triggerType'] == trigger_type }['configuration']
      end

      it 'exposes the stored configuration for each trigger', :aggregate_failures do
        post_graphql(profiles_with_trigger_settings(:TRIAGE_AND_REMEDIATION), current_user: user)

        expect(configuration_for('VULNERABILITY_ENRICHMENT')).to include(
          '__typename' => 'VulnerabilityEnrichmentConfiguration',
          'runMode' => 'MANUAL'
        )

        expect(configuration_for('SAST_VULNERABILITY_RESOLUTION')).to include(
          '__typename' => 'SastVulnerabilityResolutionConfiguration',
          'cweClasses' => ['CWE-89'],
          'falsePositiveConfidence' => 'LIKELY_NOT_FALSE_POSITIVE'
        )
      end
    end

    context 'with a scan type that has no typed configuration' do
      let_it_be(:dependency_scanning_profile) do
        create(:security_scan_profile, namespace: group, scan_type: :dependency_scanning, name: 'Dependency scanning')
      end

      let_it_be(:dependency_scanning_trigger) do
        create(:security_scan_profile_trigger, scan_profile: dependency_scanning_profile,
          trigger_type: :default_branch_pipeline)
      end

      it 'returns a null configuration instead of failing to resolve the union' do
        post_graphql(profiles_with_trigger_settings(:DEPENDENCY_SCANNING), current_user: user)

        expect(graphql_errors).to be_nil

        settings = returned_profile(dependency_scanning_profile.name)['triggerSettings']
        expect(settings.first['configuration']).to be_nil
      end
    end

    context 'with a SAST profile' do
      let_it_be(:sast_profile) do
        create(:security_scan_profile, namespace: group, scan_type: :sast, name: 'SAST')
      end

      let_it_be(:sast_trigger) do
        create(:security_scan_profile_trigger, scan_profile: sast_profile, trigger_type: :default_branch_pipeline,
          configuration_values: {
            'secure_analyzers_prefix' => 'registry.gitlab.com/security-products',
            'image_suffix' => '-fips',
            'analyzer_image_tag' => '5',
            'excluded_analyzers' => %w[brakeman],
            'excluded_paths' => %w[spec test],
            'advanced_sast_partial_scan' => 'differential',
            'gitlab_adv_sast_incr_scan' => true
          })
      end

      it 'exposes SAST configuration', :aggregate_failures do
        post_graphql(profiles_with_trigger_settings(:SAST), current_user: user)

        settings = returned_profile(sast_profile.name)['triggerSettings']
        configuration = settings.first['configuration']

        expect(configuration['__typename']).to eq('SastConfiguration')
        expect(configuration).to include(
          'secureAnalyzersPrefix' => 'registry.gitlab.com/security-products',
          'imageSuffix' => 'FIPS',
          'analyzerImageTag' => '5',
          'excludedAnalyzers' => %w[brakeman],
          'excludedPaths' => %w[spec test],
          'advancedSastPartialScan' => 'DIFFERENTIAL',
          'gitlabAdvSastIncrScan' => true
        )
      end

      context 'without a stored configuration override' do
        let_it_be(:unconfigured_trigger) do
          create(:security_scan_profile_trigger, scan_profile: sast_profile, trigger_type: :merge_request_pipeline)
        end

        it 'exposes the SAST type with all fields nil' do
          post_graphql(profiles_with_trigger_settings(:SAST), current_user: user)

          settings = returned_profile(sast_profile.name)['triggerSettings']
          configuration = settings.find { |s| s['triggerType'] == 'MERGE_REQUEST_PIPELINE' }['configuration']

          expect(
            configuration.values_at(
              'secureAnalyzersPrefix', 'imageSuffix', 'analyzerImageTag', 'excludedAnalyzers', 'excludedPaths',
              'advancedSastPartialScan', 'gitlabAdvSastIncrScan'
            )
          ).to all(be_nil)
        end
      end
    end

    it 'does not run additional queries as the number of profiles grows' do
      trigger_query = profiles_with_trigger_settings(:DEPENDENCY_SCANNING_POST_PROCESSING)
      post_graphql(trigger_query, current_user: user) # warm up
      control = ActiveRecord::QueryRecorder.new { post_graphql(trigger_query, current_user: user) }

      create_post_processing_profile('second profile')
      create_post_processing_profile('third profile')

      expect { post_graphql(trigger_query, current_user: user) }.not_to exceed_query_limit(control)
    end
  end

  describe 'projectCount' do
    let_it_be(:attached_project) do
      create(:security_scan_profile_project, scan_profile: scan_profile)
    end

    let(:project_count_query) do
      graphql_query_for(:group, { full_path: group.full_path },
        query_graphql_field(
          :available_security_scan_profiles,
          { type: :DEPENDENCY_SCANNING_POST_PROCESSING },
          'name projectCount'
        ))
    end

    it 'returns the number of projects the profile is attached to' do
      post_graphql(project_count_query, current_user: user)

      expect(returned_profile(scan_profile.name)['projectCount']).to eq(1)
    end

    it 'returns 0 for a profile with no attached projects' do
      create_post_processing_profile('Empty profile')

      post_graphql(project_count_query, current_user: user)

      expect(returned_profile('Empty profile')['projectCount']).to eq(0)
    end

    it 'does not run additional queries as the number of profiles grows' do
      post_graphql(project_count_query, current_user: user) # warm up
      control = ActiveRecord::QueryRecorder.new { post_graphql(project_count_query, current_user: user) }

      second = create_post_processing_profile('second profile')
      create(:security_scan_profile_project, scan_profile: second)
      third = create_post_processing_profile('third profile')
      create(:security_scan_profile_project, scan_profile: third)

      expect { post_graphql(project_count_query, current_user: user) }.not_to exceed_query_limit(control)
    end
  end
end
