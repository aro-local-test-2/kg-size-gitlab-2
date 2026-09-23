# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SecurityScanProfileCreate', feature_category: :security_testing_configuration do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:root_group) { create(:group) }

  let(:namespace_id) { root_group.to_global_id.to_s }
  let(:scan_type) { 'SAST' }
  let(:name) { 'My scan profile' }
  let(:description) { 'A test scan profile' }
  let(:triggers) { [{ trigger_type: 'DEFAULT_BRANCH_PIPELINE' }] }
  let(:strip_defaults) { nil }

  let(:input) do
    {
      namespace_id: namespace_id,
      scan_type: scan_type,
      name: name,
      description: description,
      triggers: triggers,
      strip_defaults: strip_defaults
    }.compact
  end

  let(:mutation) do
    graphql_mutation(:security_scan_profile_create, input) do
      <<~FIELDS
        errors
        scanProfile {
          id
          name
          scanType
          triggers
        }
      FIELDS
    end
  end

  def mutation_response
    graphql_mutation_response(:security_scan_profile_create)
  end

  describe 'GraphQL mutation' do
    before do
      stub_licensed_features(security_scan_profiles: true)
    end

    context 'when the user does not have permission' do
      it_behaves_like 'a mutation that returns a top-level access error'

      it 'does not create a scan profile' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { Security::ScanProfile.count }
      end
    end

    context 'when the user has permission' do
      before_all do
        root_group.add_maintainer(current_user)
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL', :create_security_scan_profiles do
        let(:user) { current_user }
        let(:boundary_object) { root_group }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end

      context 'when the security_scan_profiles licensed feature is unavailable' do
        before do
          stub_licensed_features(security_scan_profiles: false)
        end

        it_behaves_like 'a mutation that returns a top-level access error'
      end

      context 'when the namespace does not exist' do
        let(:namespace_id) { "gid://gitlab/Group/#{non_existing_record_id}" }

        it_behaves_like 'a mutation that returns a top-level access error'
      end

      context 'when the namespace is not a top-level namespace' do
        let_it_be(:subgroup) { create(:group, parent: root_group) }

        let(:namespace_id) { subgroup.to_global_id.to_s }

        it 'returns a top-level argument error and does not create a profile', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .not_to change { Security::ScanProfile.count }

          expect(graphql_errors.first['message']).to eq('namespace_id must reference a top-level namespace.')
        end
      end

      context 'with profile and a pipeline trigger' do
        it 'creates the scan profile', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['scanProfile']).to include(
            'name' => name,
            'scanType' => 'SAST',
            'triggers' => ['DEFAULT_BRANCH_PIPELINE']
          )
        end
      end

      context 'without triggers' do
        let(:triggers) { [] }

        it 'returns a top-level validation error and does not create a profile', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .not_to change { Security::ScanProfile.count }

          expect_graphql_errors_to_include('triggers is too short (minimum is 1)')
        end
      end

      context 'without a description' do
        let(:description) { nil }

        it 'returns a top-level schema error and does not create a profile', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .not_to change { Security::ScanProfile.count }

          expect_graphql_errors_to_include(/provided invalid value for description \(Expected value to not be null\)/)
        end
      end

      context 'when the name is reserved for a GitLab-recommended profile' do
        let(:name) { Security::DefaultScanProfiles.find_by_scan_type(:sast).name }

        it 'returns mutation errors and does not create a profile', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .not_to change { Security::ScanProfile.count }

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors'])
            .to contain_exactly('Name is reserved for GitLab-recommended scan profiles.')
        end
      end

      context 'with a dependency scanning post-processing profile and a trigger' do
        let(:scan_type) { 'DEPENDENCY_SCANNING_POST_PROCESSING' }
        let(:strip_defaults) { false }
        let(:triggers) do
          [{
            trigger_type: 'SBOM_INGESTED',
            configuration: {
              dependency_scanning_post_processing: {
                auto_remediation: {
                  enabled: true,
                  cooldown: 3,
                  severity_level: 'HIGH',
                  upgrade_policy: 'MINOR'
                }
              }
            }
          }]
        end

        it 'creates the profile and attaches the configuration to the trigger', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .to change { Security::ScanProfile.count }.by(1)
            .and change { Security::ScanProfileTrigger.count }.by(1)
            .and change { Security::ScanProfiles::Configuration.count }.by(1)

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['scanProfile']).to include('scanType' => 'DEPENDENCY_SCANNING_POST_PROCESSING')

          expect(Security::ScanProfileTrigger.find_by(trigger_type: :sbom_ingested)).to have_attributes(
            trigger_type: 'sbom_ingested',
            configuration: have_attributes(
              configuration: {
                'auto_remediation' =>
                  { 'enabled' => true, 'cooldown' => 3, 'severity_level' => 'high', 'upgrade_policy' => 'minor' }
              }
            )
          )
        end
      end

      context 'when strip_defaults is enabled (the default)' do
        let(:scan_type) { 'DEPENDENCY_SCANNING_POST_PROCESSING' }
        let(:triggers) do
          [{
            trigger_type: 'SBOM_INGESTED',
            configuration: {
              dependency_scanning_post_processing: {
                auto_remediation: { cooldown: 3, upgrade_policy: 'MINOR' }
              }
            }
          }]
        end

        it 'stores only the non-default values', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .to change { Security::ScanProfiles::Configuration.count }.by(1)

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors']).to be_empty
          expect(Security::ScanProfileTrigger.find_by(trigger_type: :sbom_ingested).configuration.configuration)
            .to eq('auto_remediation' => { 'cooldown' => 3 })
        end
      end

      context 'with a secret detection profile and a trigger' do
        let(:scan_type) { 'SECRET_DETECTION' }
        let(:triggers) do
          [{
            trigger_type: 'MERGE_REQUEST_PIPELINE',
            configuration: {
              secret_detection: {
                image_suffix: :FIPS,
                secure_analyzers_prefix: 'registry.example.com/analyzers',
                historic_scan: true,
                log_options: '--all',
                excluded_paths: ['spec/', 'qa/'],
                ruleset_git_reference: 'gitlab.com/example-group/remote-ruleset'
              }
            }
          }]
        end

        it 'creates the profile and attaches the configuration to the trigger', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .to change { Security::ScanProfile.count }.by(1)
            .and change { Security::ScanProfileTrigger.count }.by(1)
            .and change { Security::ScanProfiles::Configuration.count }.by(1)

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['scanProfile']).to include('scanType' => 'SECRET_DETECTION')

          trigger = Security::ScanProfileTrigger.find_by(trigger_type: :merge_request_pipeline)
          expect(trigger.configuration.configuration)
            .to eq(
              'image_suffix' => '-fips',
              'secure_analyzers_prefix' => 'registry.example.com/analyzers',
              'historic_scan' => true,
              'log_options' => '--all',
              'excluded_paths' => ['spec/', 'qa/'],
              'ruleset_git_reference' => 'gitlab.com/example-group/remote-ruleset'
            )
        end
      end

      context 'with a sast profile and a trigger' do
        let(:scan_type) { 'SAST' }
        let(:triggers) do
          [{
            trigger_type: 'MERGE_REQUEST_PIPELINE',
            configuration: {
              sast: {
                image_suffix: :FIPS,
                secure_analyzers_prefix: 'registry.example.com/analyzers',
                analyzer_image_tag: '5',
                excluded_analyzers: ['semgrep-sast'],
                excluded_paths: ['spec/', 'qa/'],
                advanced_sast_partial_scan: :DIFFERENTIAL,
                gitlab_adv_sast_incr_scan: true
              }
            }
          }]
        end

        it 'creates the profile and attaches the configuration to the trigger', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .to change { Security::ScanProfile.count }.by(1)
            .and change { Security::ScanProfileTrigger.count }.by(1)
            .and change { Security::ScanProfiles::Configuration.count }.by(1)

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['scanProfile']).to include('scanType' => 'SAST')

          trigger = Security::ScanProfileTrigger.find_by(trigger_type: :merge_request_pipeline)
          expect(trigger.configuration.configuration)
            .to eq(
              'image_suffix' => '-fips',
              'secure_analyzers_prefix' => 'registry.example.com/analyzers',
              'analyzer_image_tag' => '5',
              'excluded_analyzers' => ['semgrep-sast'],
              'excluded_paths' => ['spec/', 'qa/'],
              'advanced_sast_partial_scan' => 'differential',
              'gitlab_adv_sast_incr_scan' => true
            )
        end
      end

      context 'with a secret detection configuration on a git push event trigger' do
        let(:scan_type) { 'SECRET_DETECTION' }
        let(:triggers) do
          [{
            trigger_type: 'GIT_PUSH_EVENT',
            configuration: { secret_detection: { historic_scan: true } }
          }]
        end

        it 'returns mutation errors and persists nothing', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .to not_change { Security::ScanProfile.count }
            .and not_change { Security::ScanProfiles::Configuration.count }

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['scanProfile']).to be_nil
          expect(mutation_response['errors'])
            .to include('Configuration is not allowed for the git_push_event trigger')
        end
      end

      context 'when the configuration is invalid' do
        let(:scan_type) { 'DEPENDENCY_SCANNING_POST_PROCESSING' }
        let(:triggers) do
          [{
            trigger_type: 'SBOM_INGESTED',
            configuration: {
              dependency_scanning_post_processing: {
                auto_remediation: { cooldown: 999 }
              }
            }
          }]
        end

        it 'returns mutation errors and persists nothing', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .to not_change { Security::ScanProfile.count }

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['scanProfile']).to be_nil
          expect(mutation_response['errors'])
            .to contain_exactly('Configuration number at `/auto_remediation/cooldown` is greater than: 100')
        end
      end

      context 'with a triage and remediation profile' do
        let(:scan_type) { 'TRIAGE_AND_REMEDIATION' }
        let(:triggers) { [{ trigger_type: 'SBOM_INGESTED' }, { trigger_type: 'SAST_FALSE_POSITIVE' }] }

        def stored_configuration(trigger_type)
          Security::ScanProfileTrigger.find_by(trigger_type: trigger_type).configuration&.configuration
        end

        it 'creates the profile with its remediation triggers', :aggregate_failures do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .to change { Security::ScanProfile.count }.by(1)

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['scanProfile']).to include(
            'name' => name,
            'scanType' => 'TRIAGE_AND_REMEDIATION',
            'triggers' => match_array(%w[SBOM_INGESTED SAST_FALSE_POSITIVE])
          )
        end

        context 'with a configuration per trigger' do
          let(:triggers) do
            [
              {
                trigger_type: 'SBOM_INGESTED',
                configuration: {
                  triage_and_remediation: {
                    sbom_ingested: { auto_remediation: { cooldown: 3, upgrade_policy: 'MAJOR' } }
                  }
                }
              },
              {
                trigger_type: 'SAST_FALSE_POSITIVE',
                configuration: {
                  triage_and_remediation: {
                    sast_false_positive: {
                      severity_level: 'HIGH', run_mode: 'MANUAL', cwe_classes: %w[CWE-89 CWE-79]
                    }
                  }
                }
              },
              {
                trigger_type: 'SAST_VULNERABILITY_RESOLUTION',
                configuration: {
                  triage_and_remediation: {
                    sast_vulnerability_resolution: { false_positive_confidence: 'LIKELY_NOT_FALSE_POSITIVE' }
                  }
                }
              },
              {
                trigger_type: 'SECRET_DETECTION_FALSE_POSITIVE',
                configuration: {
                  triage_and_remediation: {
                    secret_detection_false_positive: { severity_level: 'CRITICAL', run_mode: 'MANUAL' }
                  }
                }
              },
              {
                trigger_type: 'VULNERABILITY_ENRICHMENT',
                configuration: {
                  triage_and_remediation: { vulnerability_enrichment: { run_mode: 'MANUAL' } }
                }
              }
            ]
          end

          it 'unwraps each trigger member and persists it against that trigger', :aggregate_failures do
            expect { post_graphql_mutation(mutation, current_user: current_user) }
              .to change { Security::ScanProfiles::Configuration.count }.by(5)

            expect(mutation_response['errors']).to be_empty
            expect(stored_configuration(:sbom_ingested))
              .to eq('auto_remediation' => { 'cooldown' => 3, 'upgrade_policy' => 'major' })
            expect(stored_configuration(:sast_false_positive))
              .to eq('severity_level' => 'high', 'run_mode' => 'manual', 'cwe_classes' => %w[CWE-89 CWE-79])
            expect(stored_configuration(:sast_vulnerability_resolution))
              .to eq('false_positive_confidence' => 'likely_not_false_positive')
            expect(stored_configuration(:secret_detection_false_positive))
              .to eq('severity_level' => 'critical', 'run_mode' => 'manual')
            expect(stored_configuration(:vulnerability_enrichment)).to eq('run_mode' => 'manual')
          end
        end

        context 'when strip_defaults is enabled (the default)' do
          let(:triggers) do
            [
              {
                trigger_type: 'SBOM_INGESTED',
                configuration: {
                  triage_and_remediation: { sbom_ingested: { auto_remediation: { cooldown: 3 } } }
                }
              },
              {
                trigger_type: 'SAST_FALSE_POSITIVE',
                configuration: {
                  triage_and_remediation: { sast_false_positive: { severity_level: 'MEDIUM', run_mode: 'AUTO' } }
                }
              }
            ]
          end

          it 'strips against the trigger defaults, not the scan type defaults', :aggregate_failures do
            expect { post_graphql_mutation(mutation, current_user: current_user) }
              .to change { Security::ScanProfiles::Configuration.count }.by(1)

            expect(mutation_response['errors']).to be_empty
            expect(stored_configuration(:sbom_ingested)).to eq('auto_remediation' => { 'cooldown' => 3 })
            expect(stored_configuration(:sast_false_positive)).to be_nil
          end
        end

        context 'when the configuration member does not match the trigger type' do
          let(:triggers) do
            [{
              trigger_type: 'SBOM_INGESTED',
              configuration: {
                triage_and_remediation: { sast_false_positive: { run_mode: 'MANUAL' } }
              }
            }]
          end

          it 'returns a top-level argument error', :aggregate_failures do
            post_graphql_mutation(mutation, current_user: current_user)

            expect_graphql_errors_to_include(
              "Configuration 'sast_false_positive' does not match trigger type 'sbom_ingested'"
            )
            expect(Security::ScanProfile.count).to eq(0)
          end
        end

        context 'when more than 50 CWE identifiers are given' do
          let(:triggers) do
            [{
              trigger_type: 'SAST_FALSE_POSITIVE',
              configuration: {
                triage_and_remediation: {
                  sast_false_positive: { cwe_classes: Array.new(51) { |i| "CWE-#{i}" } }
                }
              }
            }]
          end

          it 'is rejected', :aggregate_failures do
            post_graphql_mutation(mutation, current_user: current_user)

            expect_graphql_errors_to_include(/cweClasses/)
            expect(Security::ScanProfile.count).to eq(0)
          end
        end

        context 'when a CWE identifier is malformed' do
          let(:triggers) do
            [{
              trigger_type: 'SAST_FALSE_POSITIVE',
              configuration: {
                triage_and_remediation: { sast_false_positive: { cwe_classes: %w[CWE-89 sql-injection] } }
              }
            }]
          end

          it 'is rejected before reaching the JSON schema', :aggregate_failures do
            post_graphql_mutation(mutation, current_user: current_user)

            expect_graphql_errors_to_include(/not a valid CWE identifier/)
            expect(Security::ScanProfile.count).to eq(0)
          end
        end

        context 'when the triage_and_remediation_profile feature flag is disabled' do
          before do
            stub_feature_flags(triage_and_remediation_profile: false)
          end

          it_behaves_like 'a mutation that returns a top-level access error'

          it 'does not create a scan profile' do
            expect { post_graphql_mutation(mutation, current_user: current_user) }
              .not_to change { Security::ScanProfile.count }
          end
        end
      end

      context 'when the configuration member does not match the scan type' do
        let(:scan_type) { 'SAST' }
        let(:triggers) do
          [{
            trigger_type: 'DEFAULT_BRANCH_PIPELINE',
            configuration: {
              dependency_scanning_post_processing: {
                auto_remediation: { enabled: true }
              }
            }
          }]
        end

        it 'returns a top-level argument error', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors.first['message'])
            .to eq("Configuration 'dependency_scanning_post_processing' does not match scan type 'sast'")
          expect(Security::ScanProfile.count).to eq(0)
        end
      end
    end
  end
end
