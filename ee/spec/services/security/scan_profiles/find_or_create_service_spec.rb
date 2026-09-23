# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::FindOrCreateService, feature_category: :security_testing_configuration do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  describe '.execute' do
    subject(:execute_service) do
      described_class.execute(namespace: namespace, identifier: identifier)
    end

    context 'when namespace is not a root namespace' do
      let(:namespace) { subgroup }
      let(:identifier) { :secret_detection }

      it 'returns an error' do
        result = execute_service

        expect(result).to have_attributes(
          status: :error,
          message: 'Namespace must be a root namespace'
        )
      end

      it 'does not create a scan profile' do
        expect { execute_service }.not_to change { Security::ScanProfile.count }
      end
    end

    context 'when namespace is a root namespace' do
      let(:namespace) { root_group }

      context 'with valid scan_type identifier' do
        let_it_be(:identifier) { :secret_detection }
        let(:default_profile) { Security::DefaultScanProfiles.find_by_scan_type(identifier) }

        context 'when no gitlab_recommended profile exists' do
          it 'creates a new gitlab_recommended profile' do
            expect { execute_service }.to change { Security::ScanProfile.count }.by(1)
          end

          it 'returns success with the created profile' do
            result = execute_service

            expect(result).to be_success
            expect(result.payload[:scan_profile]).to be_a(Security::ScanProfile)
            expect(result.payload[:scan_profile]).to be_persisted
          end

          it 'creates profile with default attributes and triggers' do
            result = execute_service
            profile = result.payload[:scan_profile]

            expect(profile).to have_attributes(
              scan_type: default_profile.scan_type,
              name: default_profile.name,
              description: default_profile.description,
              gitlab_recommended: true,
              namespace: namespace
            )

            expect(profile.scan_profile_triggers.map(&:trigger_type))
              .to match_array(default_profile.scan_profile_triggers.map(&:trigger_type))
          end

          it 'creates trigger associations' do
            expect { execute_service }.to change { Security::ScanProfileTrigger.count }
              .by(default_profile.scan_profile_triggers.size)
          end

          context 'when upsert fails with error' do
            before do
              allow(Security::ScanProfile).to receive(:upsert).and_raise(ActiveRecord::StatementInvalid.new('error'))
            end

            it 'returns an error response' do
              result = execute_service

              expect(result).to have_attributes(
                status: :error,
                message: a_string_starting_with('Failed to create scan profile:')
              )
            end

            it 'does not create a scan profile' do
              expect { execute_service }.not_to change { Security::ScanProfile.count }
            end
          end

          context 'when default profile has no triggers' do
            before do
              default_profile = Security::DefaultScanProfiles.find_by_scan_type(identifier)
              allow(default_profile).to receive(:scan_profile_triggers).and_return([])
              allow(Security::DefaultScanProfiles).to receive(:find_by_preset_key).and_return(default_profile)
            end

            it 'creates the profile without triggers' do
              expect { execute_service }.to change { Security::ScanProfile.count }.by(1)
               .and not_change { Security::ScanProfileTrigger.count }
            end

            it 'returns success with the created profile' do
              result = execute_service

              expect(result).to have_attributes(
                status: :success,
                payload: a_hash_including(scan_profile: an_instance_of(Security::ScanProfile))
              )
            end
          end
        end

        context 'when a gitlab_recommended profile already exists' do
          let_it_be(:default_profile) { Security::DefaultScanProfiles.find_by_scan_type(identifier) }

          let_it_be(:existing_profile) do
            create(:security_scan_profile,
              namespace: root_group,
              scan_type: identifier,
              name: default_profile.name,
              gitlab_recommended: true
            )
          end

          it 'does not create a new profile' do
            expect { execute_service }.not_to change { Security::ScanProfile.count }
          end

          it 'returns the existing profile' do
            result = execute_service

            expect(result).to be_success
            expect(result.payload[:scan_profile]).to eq(existing_profile)
          end

          context 'when there are no existing triggers' do
            it 'persist the defaults triggers' do
              expect { execute_service }.to change { Security::ScanProfileTrigger.count }
                .by(default_profile.scan_profile_triggers.size)
            end

            it 'returns the profile with new triggers' do
              result = execute_service
              expect(result.payload[:scan_profile].scan_profile_triggers.map(&:trigger_type))
                .to match_array(default_profile.scan_profile_triggers.map(&:trigger_type))
            end
          end

          context 'when trigger already exists for the profile' do
            let_it_be(:existing_trigger) do
              create(:security_scan_profile_trigger,
                scan_profile: existing_profile,
                namespace: root_group,
                trigger_type: default_profile.scan_profile_triggers.first.trigger_type
              )
            end

            it 'does not duplicate triggers' do
              expect { execute_service }.to change { Security::ScanProfileTrigger.count }
                .by(default_profile.scan_profile_triggers.size - 1) # created a single trigger already
            end

            it 'returns the profile with existing triggers' do
              result = execute_service
              profile = result.payload[:scan_profile]

              expect(profile.scan_profile_triggers.count).to eq(default_profile.scan_profile_triggers.size)
              expect(profile.scan_profile_triggers.map(&:trigger_type))
                .to match_array(default_profile.scan_profile_triggers.map(&:trigger_type))
            end
          end
        end

        context 'when custom profiles exist but no gitlab_recommended' do
          let_it_be(:custom_profile) do
            create(:security_scan_profile,
              namespace: root_group,
              scan_type: :secret_detection,
              name: 'Custom Secret Detection',
              gitlab_recommended: false
            )
          end

          it 'creates a new gitlab_recommended profile' do
            expect { execute_service }.to change { Security::ScanProfile.count }.by(1)
          end

          it 'returns the newly created gitlab_recommended profile' do
            result = execute_service
            profile = result.payload[:scan_profile]

            expect(profile).not_to eq(custom_profile)
            expect(profile.gitlab_recommended).to be(true)
          end
        end
      end

      context 'with sast scan_type identifier' do
        let(:identifier) { :sast }

        it 'creates a new SAST default profile' do
          expect { execute_service }.to change { Security::ScanProfile.count }.by(1)
        end

        it 'returns success with the created profile' do
          result = execute_service

          expect(result).to be_success
          expect(result.payload[:scan_profile]).to be_a(Security::ScanProfile)
          expect(result.payload[:scan_profile].scan_type).to eq('sast')
        end
      end

      context 'with dependency_scanning scan_type identifier' do
        let(:identifier) { :dependency_scanning }

        it 'creates a new Dependency Scanning default profile' do
          expect { execute_service }.to change { Security::ScanProfile.count }.by(1)
        end

        it 'returns success with the created profile' do
          result = execute_service

          expect(result).to be_success
          expect(result.payload[:scan_profile]).to be_a(Security::ScanProfile)
          expect(result.payload[:scan_profile].scan_type).to eq('dependency_scanning')
        end
      end

      context 'with dependency_scanning_post_processing scan_type identifier' do
        let(:identifier) { :dependency_scanning_post_processing }

        it 'creates a new post-processing default profile', :aggregate_failures do
          expect { execute_service }.to change { Security::ScanProfile.count }.by(1)

          expect(execute_service.payload[:scan_profile].scan_type).to eq('dependency_scanning_post_processing')
        end
      end

      context 'with a triage and remediation preset identifier' do
        def configurations_by_trigger(profile)
          profile.scan_profile_triggers.to_h { |trigger| [trigger.trigger_type, trigger.configuration&.configuration] }
        end

        context 'with the conservative preset' do
          let(:identifier) { :triage_and_remediation_conservative }

          it 'persists every trigger and only the configurations that differ from the defaults',
            :aggregate_failures do
            expect { execute_service }
              .to change { Security::ScanProfile.count }.by(1)
              .and change { Security::ScanProfileTrigger.count }.by(5)
              .and change { Security::ScanProfiles::Configuration.count }.by(5)

            profile = execute_service.payload[:scan_profile]

            expect(profile).to have_attributes(
              scan_type: 'triage_and_remediation',
              name: 'Triage and Remediation (Conservative)',
              gitlab_recommended: true,
              namespace: root_group
            )
            expect(configurations_by_trigger(profile)).to eq(
              'vulnerability_enrichment' => { 'severity_level' => 'high' },
              'sast_vulnerability_resolution' => {
                'severity_level' => 'high', 'run_mode' => 'manual', 'open_merge_requests_limit' => 5
              },
              'sast_false_positive' => { 'severity_level' => 'high', 'run_mode' => 'manual' },
              'secret_detection_false_positive' => { 'severity_level' => 'high', 'run_mode' => 'manual' },
              'sbom_ingested' => { 'auto_remediation' => { 'open_merge_requests_limit' => 5 } }
            )
          end

          it 'persists nothing further when run again', :aggregate_failures do
            execute_service
            second_run = nil

            expect { second_run = described_class.execute(namespace: namespace, identifier: identifier) }
              .to not_change { Security::ScanProfile.count }
              .and not_change { Security::ScanProfileTrigger.count }
              .and not_change { Security::ScanProfiles::Configuration.count }

            expect(second_run).to be_success
          end

          context 'when the triage_and_remediation_profile feature flag is disabled' do
            before do
              stub_feature_flags(triage_and_remediation_profile: false)
            end

            it 'returns an error and persists nothing', :aggregate_failures do
              expect { execute_service }.not_to change { Security::ScanProfile.count }

              expect(execute_service).to have_attributes(
                status: :error,
                message: 'Could not find a default scan profile for this type'
              )
            end
          end
        end

        context 'with the standard preset' do
          let(:identifier) { :triage_and_remediation_standard }

          it 'persists every trigger without a configuration, because it matches the defaults',
            :aggregate_failures do
            expect { execute_service }
              .to change { Security::ScanProfile.count }.by(1)
              .and change { Security::ScanProfileTrigger.count }.by(5)
              .and not_change { Security::ScanProfiles::Configuration.count }

            expect(configurations_by_trigger(execute_service.payload[:scan_profile])).to eq(
              'vulnerability_enrichment' => nil,
              'sast_vulnerability_resolution' => nil,
              'sast_false_positive' => nil,
              'secret_detection_false_positive' => nil,
              'sbom_ingested' => nil
            )
          end
        end

        context 'with all three presets' do
          let(:preset_keys) do
            %w[
              triage_and_remediation_conservative
              triage_and_remediation_standard
              triage_and_remediation_proactive
            ]
          end

          it 'keeps each preset as a separate profile in the namespace', :aggregate_failures do
            expect do
              preset_keys.each { |key| described_class.execute(namespace: namespace, identifier: key) }
            end.to change { Security::ScanProfile.count }.by(3)
              .and change { Security::ScanProfileTrigger.count }.by(15)
              .and change { Security::ScanProfiles::Configuration.count }.by(10)

            expect(Security::ScanProfile.by_namespace(root_group).by_type(:triage_and_remediation).map(&:name))
              .to match_array([
                'Triage and Remediation (Conservative)',
                'Triage and Remediation (Standard)',
                'Triage and Remediation (Proactive)'
              ])
          end
        end
      end

      context 'with invalid scan_type identifier' do
        let(:identifier) { :invalid_type }

        it 'returns an error' do
          result = execute_service

          expect(result).to have_attributes(
            status: :error,
            message: 'Could not find a default scan profile for this type'
          )
        end

        it 'does not create a scan profile' do
          expect { execute_service }.not_to change { Security::ScanProfile.count }
        end
      end

      context 'with numeric id identifier' do
        let_it_be(:existing_profile) do
          create(:security_scan_profile,
            namespace: root_group,
            scan_type: :secret_detection,
            gitlab_recommended: false
          )
        end

        let(:identifier) { existing_profile.id }

        it 'returns the existing profile' do
          result = execute_service

          expect(result).to be_success
          expect(result.payload[:scan_profile]).to eq(existing_profile)
        end

        it 'does not create a new profile' do
          expect { execute_service }.not_to change { Security::ScanProfile.count }
        end

        context 'when the id does not exist' do
          let(:identifier) { non_existing_record_id }

          it 'returns an error' do
            result = execute_service

            expect(result).to have_attributes(
              status: :error,
              message: 'Could not find a default scan profile for this type'
            )
          end

          it 'does not create a scan profile' do
            expect { execute_service }.not_to change { Security::ScanProfile.count }
          end
        end
      end
    end
  end
end
