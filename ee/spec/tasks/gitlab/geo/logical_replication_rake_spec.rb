# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:geo:logical_replication rake tasks', :silence_stdout, feature_category: :geo_replication do
  before do
    # Loaded before the Geo tasks so db:migrate exists and can be enhanced with the sync hook.
    Rake.application.rake_require 'active_record/railties/databases'
    Rake.application.rake_require 'tasks/gitlab/helpers'
    Rake.application.rake_require 'tasks/gitlab/geo/logical_replication'
  end

  describe 'gitlab:geo:logical_replication:sync_sequences' do
    let(:service) { instance_double(Gitlab::Database::SyncSequencesWithTableData) }

    it 'invokes SyncSequencesWithTableData without a sequence scope' do
      expect(Gitlab::Database::SyncSequencesWithTableData).to receive(:new)
        .with(only_sequences: nil).and_return(service)
      expect(service).to receive(:execute)

      run_rake_task('gitlab:geo:logical_replication:sync_sequences')
    end

    it 'passes ONLY_SEQUENCES as the sequence scope' do
      stub_env('ONLY_SEQUENCES', 'geo_nodes_id_seq, geo_node_namespace_links_id_seq')

      expect(Gitlab::Database::SyncSequencesWithTableData).to receive(:new)
        .with(only_sequences: %w[geo_nodes_id_seq geo_node_namespace_links_id_seq]).and_return(service)
      expect(service).to receive(:execute)

      run_rake_task('gitlab:geo:logical_replication:sync_sequences')
    end

    it 'aborts with the error message when the sync fails' do
      allow(Gitlab::Database::SyncSequencesWithTableData).to receive(:new).and_return(service)
      allow(service).to receive(:execute)
        .and_raise(Gitlab::Database::SyncSequencesWithTableData::SyncError, 'sync failed for: foo_id_seq')

      expect { run_rake_task('gitlab:geo:logical_replication:sync_sequences') }
        .to raise_error(SystemExit).and output(/sync failed for: foo_id_seq/).to_stderr
    end

    # This task must be runnable at initial LR setup while the subscription is live (the
    # active-subscription gate belongs only to the promotion path). A real integration test with
    # an active subscription isn't possible in specs (it needs superuser rights and a live
    # publisher), so this invariant is pinned at the mocking boundary instead.
    # https://gitlab.com/gitlab-org/gitlab/-/work_items/613693
    it 'does not gate on an active subscription' do
      allow(Gitlab::Database::SyncSequencesWithTableData).to receive(:new).and_return(service)
      allow(service).to receive(:execute)

      expect(Gitlab::Geo::LogicalReplication).not_to receive(:ensure_no_active_subscription!)

      run_rake_task('gitlab:geo:logical_replication:sync_sequences')
    end
  end

  describe 'gitlab:geo:logical_replication:sync_sequences_before_migrate' do
    let(:task_name) { 'gitlab:geo:logical_replication:sync_sequences_before_migrate' }
    let(:service) { instance_double(Gitlab::Database::SyncSequencesWithTableData) }

    before do
      allow(Gitlab::Database::SyncSequencesWithTableData).to receive(:new).and_return(service)
      allow(service).to receive(:execute)
    end

    it 'runs before db:migrate' do
      expect(Rake::Task['db:migrate'].prerequisites).to include(task_name)
    end

    context 'when logical replication is in use' do
      before do
        allow(Gitlab::Geo::LogicalReplication).to receive(:in_use?).and_return(true)
      end

      it 'syncs the sequences and reports why', :aggregate_failures do
        expect { run_rake_task(task_name) }
          .to output(/Logical replication secondary detected, syncing sequences/).to_stdout

        expect(service).to have_received(:execute)
      end

      it 'aborts the migration when the sync fails', :aggregate_failures do
        allow(service).to receive(:execute).and_raise(
          Gitlab::Database::SyncSequencesWithTableData::SyncError, 'Sequence sync failed for: foo_id_seq'
        )

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/Sequence sync failed for: foo_id_seq/).to_stderr
      end

      context 'when GEO_SKIP_SEQUENCE_SYNC is set' do
        before do
          stub_env('GEO_SKIP_SEQUENCE_SYNC', '1')
        end

        it 'reports the skip and does not sync', :aggregate_failures do
          expect { run_rake_task(task_name) }
            .to output(/GEO_SKIP_SEQUENCE_SYNC/).to_stdout

          expect(service).not_to have_received(:execute)
        end
      end
    end

    context 'when logical replication is not in use' do
      before do
        allow(Gitlab::Geo::LogicalReplication).to receive(:in_use?).and_return(false)
      end

      it 'stays silent and does not sync', :aggregate_failures do
        expect { run_rake_task(task_name) }.not_to output.to_stdout

        expect(service).not_to have_received(:execute)
      end
    end

    context 'when the database cannot answer whether logical replication is in use' do
      before do
        allow(Gitlab::Geo::LogicalReplication).to receive(:in_use?)
          .and_raise(ActiveRecord::StatementInvalid, 'relation "geo_nodes" does not exist')
      end

      it 'warns and treats it as not in use, so a fresh install still migrates', :aggregate_failures do
        expect { run_rake_task(task_name) }.to output(
          a_string_including('Could not determine whether this is a Geo logical replication secondary')
          .and(a_string_including('relation "geo_nodes" does not exist'))
        ).to_stderr

        expect(service).not_to have_received(:execute)
      end
    end

    context 'when the feature flag cannot be read' do
      before do
        allow(Gitlab::Geo::LogicalReplication).to receive(:in_use?)
          .and_raise(Redis::CannotConnectError, 'Error connecting to Redis')
      end

      it 'warns and treats it as not in use', :aggregate_failures do
        expect { run_rake_task(task_name) }
          .to output(/Could not determine whether this is a Geo logical replication secondary/).to_stderr

        expect(service).not_to have_received(:execute)
      end
    end
  end
end
