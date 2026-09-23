# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::LicensesSyncWorker, feature_category: :software_composition_analysis do
  using RSpec::Parameterized::TableSyntax

  it { is_expected.to be_a(PackageMetadata::CronJitter) }

  describe '#perform' do
    let(:instance) { described_class.new }
    let(:lease) { instance_double(Gitlab::ExclusiveLease) }

    # The routing examples below are the delayed run, so the jitter re-enqueue does
    # not stand between them and the sync. The tick itself is covered further down.
    subject(:perform!) { instance.perform(true) }

    before do
      allow(instance).to receive(:try_obtain_lease).and_yield
      allow(Gitlab::ExclusiveLease).to receive(:new).and_return(lease)
    end

    shared_examples_for 'it syncs' do
      it 'calls the v3 sync service' do
        expect(PackageMetadata::LicenseV3SyncService).to receive(:execute).with(lease: lease)

        perform!
      end
    end

    shared_examples_for 'it does not sync' do
      it 'does not call a sync service' do
        expect(PackageMetadata::LicenseV3SyncService).not_to receive(:execute)
        expect(PackageMetadata::SyncService).not_to receive(:execute)

        perform!
      end
    end

    context 'when neither license_scanning nor the dependency firewall is available' do
      before do
        stub_licensed_features(license_scanning: false)
        allow(::Security::DependencyFirewall::Availability).to receive(:instance_configurable?).and_return(false)
      end

      it_behaves_like 'it does not sync'
    end

    context 'when license_scanning is unavailable but the dependency firewall is (Premium)' do
      before do
        stub_licensed_features(license_scanning: false)
        allow(::Security::DependencyFirewall::Availability).to receive(:instance_configurable?).and_return(true)
        allow(Rails.env).to receive(:development?).and_return(false)
      end

      it 'is eligible to run -- Premium reaches the sync through the dependency firewall' do
        expect(instance.send(:should_run?)).to be(true)
      end
    end

    context 'when the license_scanning feature is enabled' do
      before do
        stub_licensed_features(license_scanning: true)
      end

      context 'and rails is not development' do
        before do
          allow(Rails.env).to receive(:development?).and_return(false)
        end

        # Every row of the routing table. An offline root follows the flag only once
        # it holds a `v3` directory; without one the vendored v2 layout keeps syncing.
        context 'and routing every combination of vendored directory and flag' do
          where(:case_name, :vendored, :v3_vendored, :flag, :expected_service, :extra_args) do
            'vendored v3, flag on'  | true  | true  | true  | PackageMetadata::LicenseV3SyncService | {}
            'vendored v3, flag off' | true  | true  | false | PackageMetadata::SyncService          | { data_type: 'licenses' }
            'vendored v2, flag on'  | true  | false | true  | PackageMetadata::SyncService          | { data_type: 'licenses' }
            'vendored v2, flag off' | true  | false | false | PackageMetadata::SyncService          | { data_type: 'licenses' }
            'online, flag on'       | false | false | true  | PackageMetadata::LicenseV3SyncService | {}
            'online, flag off'      | false | false | false | PackageMetadata::SyncService          | { data_type: 'licenses' }
          end

          with_them do
            let(:other_service) do
              ([PackageMetadata::SyncService, PackageMetadata::LicenseV3SyncService] - [expected_service]).first
            end

            before do
              stub_application_setting(package_metadata_purl_types: [1])
              stub_feature_flags(sync_v3_license_expressions: flag)
              allow(File).to receive(:exist?).and_call_original
              allow(File).to receive(:exist?)
                .with(PackageMetadata::SyncConfiguration::Location::LICENSES_PATH).and_return(vendored)
              allow(File).to receive(:exist?)
                .with(PackageMetadata::SyncConfiguration::Location::OLD_LICENSES_PATH).and_return(false)
              # Pinned rather than left to fall through: a developer with a real
              # vendor/package_metadata/licenses/v3 on disk would otherwise flip
              # the offline rows to v3 locally while CI stayed green.
              allow(File).to receive(:exist?)
                .with(File.join(PackageMetadata::SyncConfiguration::Location::LICENSES_PATH, 'v3'))
                .and_return(v3_vendored)
            end

            it 'routes to the sync service the config selects', :aggregate_failures do
              expect(other_service).not_to receive(:execute)
              expect(expected_service).to receive(:execute).with(**extra_args, lease: lease)

              perform!
            end
          end
        end

        # No purl types means no configs, which must not read as v3: an air-gapped
        # install would then reach a service whose offline connector raises.
        context 'and no purl types are enabled' do
          before do
            stub_application_setting(package_metadata_purl_types: [])
          end

          it 'calls the v2 sync service' do
            expect(PackageMetadata::LicenseV3SyncService).not_to receive(:execute)
            expect(PackageMetadata::SyncService).to receive(:execute)
              .with(data_type: 'licenses', lease: lease)

            perform!
          end
        end

        # A v2 run clobbers the expressions v3 wrote, and resuming v3 from its old
        # bookmark would never rewrite them, so the bookmarks must not survive.
        context 'and v3 licenses checkpoints exist' do
          # Two purl types, neither of them the enabled one: the delete keys on
          # data_type and version_format only, so it must take every registry's
          # bookmark regardless of which purl types the instance syncs.
          let_it_be(:v3_licenses_npm) do
            create(:pm_checkpoint, data_type: 'licenses', version_format: 'v3', purl_type: 'npm')
          end

          let_it_be(:v3_licenses_pypi) do
            create(:pm_checkpoint, data_type: 'licenses', version_format: 'v3', purl_type: 'pypi')
          end

          let_it_be(:v2_licenses) do
            create(:pm_checkpoint, data_type: 'licenses', version_format: 'v2', purl_type: 'npm')
          end

          let_it_be(:v3_malware) do
            create(:pm_checkpoint, data_type: 'malware_advisories', version_format: 'v3', purl_type: 'npm')
          end

          before do
            stub_application_setting(package_metadata_purl_types: [1])
            allow(File).to receive(:exist?).and_call_original
            allow(File).to receive(:exist?)
              .with(PackageMetadata::SyncConfiguration::Location::LICENSES_PATH).and_return(false)
            allow(File).to receive(:exist?)
              .with(PackageMetadata::SyncConfiguration::Location::OLD_LICENSES_PATH).and_return(false)
            allow(PackageMetadata::SyncService).to receive(:execute)
            allow(PackageMetadata::LicenseV3SyncService).to receive(:execute)
          end

          context 'when the flag is disabled' do
            before do
              stub_feature_flags(sync_v3_license_expressions: false)
            end

            it 'deletes every v3 licenses checkpoint and nothing else', :aggregate_failures do
              expect { perform! }.to change { PackageMetadata::Checkpoint.count }.by(-2)

              expect(PackageMetadata::Checkpoint.all).to contain_exactly(v2_licenses, v3_malware)
            end

            it 'records how many were deleted' do
              expect(instance).to receive(:log_extra_metadata_on_done).with(:v3_license_checkpoints_deleted, 2)

              perform!
            end
          end

          context 'when the flag is enabled' do
            before do
              stub_feature_flags(sync_v3_license_expressions: true)
            end

            it 'keeps them' do
              expect { perform! }.not_to change { PackageMetadata::Checkpoint.count }
            end
          end

          # A vendored directory pins v2 even with the flag on, so the purge has to
          # key on the resolved config. An air-gapped install never changes the flag,
          # so a flag-based check would clobber expressions and keep the bookmarks.
          context 'when a vendored directory pins v2 while the flag is enabled' do
            before do
              stub_feature_flags(sync_v3_license_expressions: true)
              allow(File).to receive(:exist?)
                .with(PackageMetadata::SyncConfiguration::Location::LICENSES_PATH).and_return(true)
            end

            it 'deletes every v3 licenses checkpoint and nothing else', :aggregate_failures do
              expect { perform! }.to change { PackageMetadata::Checkpoint.count }.by(-2)

              expect(PackageMetadata::Checkpoint.all).to contain_exactly(v2_licenses, v3_malware)
            end
          end

          # No purl types means no config, so the v2 route ingests nothing. Purging
          # there would throw away v3's progress with no clobbering to compensate for.
          context 'when no purl types are enabled' do
            where(:flag) { [true, false] }

            with_them do
              before do
                stub_application_setting(package_metadata_purl_types: [])
                stub_feature_flags(sync_v3_license_expressions: flag)
              end

              it 'keeps them' do
                expect { perform! }.not_to change { PackageMetadata::Checkpoint.count }
              end
            end
          end
        end

        # The guard covers the steady state: once a v2 instance has purged, every
        # later run finds nothing, so it must skip the delete and the log line too.
        context 'and no v3 licenses checkpoints exist' do
          before do
            stub_application_setting(package_metadata_purl_types: [1])
            stub_feature_flags(sync_v3_license_expressions: false)
            allow(PackageMetadata::SyncService).to receive(:execute)
          end

          it 'logs no deleted count' do
            expect(instance).not_to receive(:log_extra_metadata_on_done)

            perform!
          end
        end
      end

      context 'and rails is development' do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        context 'and sync in dev env variable is true' do
          before do
            stub_env('PM_SYNC_IN_DEV', true)
          end

          it_behaves_like 'it syncs'
        end

        context 'and sync in dev env variable is false' do
          before do
            stub_env('PM_SYNC_IN_DEV', false)
          end

          it_behaves_like 'it does not sync'
        end
      end
    end

    context 'on the cron tick (jittered = false)' do
      subject(:perform!) { instance.perform }

      before do
        stub_licensed_features(license_scanning: true)
        allow(Rails.env).to receive(:development?).and_return(false)
      end

      context 'on a self-managed instance' do
        before do
          allow(Gitlab).to receive(:com?).and_return(false)
        end

        it 're-enqueues itself after the per-instance offset instead of syncing',
          :aggregate_failures do
          expect(described_class).to receive(:perform_in).with(instance.send(:jitter_offset), true)
          expect(PackageMetadata::LicenseV3SyncService).not_to receive(:execute)
          expect(PackageMetadata::SyncService).not_to receive(:execute)

          perform!
        end
      end

      context 'on GitLab.com' do
        before do
          allow(Gitlab).to receive(:com?).and_return(true)
        end

        it 'syncs on the tick, without jitter', :aggregate_failures do
          expect(described_class).not_to receive(:perform_in)
          expect(PackageMetadata::LicenseV3SyncService).to receive(:execute).with(lease: lease)

          perform!
        end
      end

      context 'when the license is unavailable' do
        before do
          stub_licensed_features(license_scanning: false)
          allow(Gitlab).to receive(:com?).and_return(false)
        end

        it 'does not re-enqueue when the license is unavailable' do
          expect(described_class).not_to receive(:perform_in)

          perform!
        end
      end
    end
  end
end
