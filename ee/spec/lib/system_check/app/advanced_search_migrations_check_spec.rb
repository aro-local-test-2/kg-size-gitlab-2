# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SystemCheck::App::AdvancedSearchMigrationsCheck, feature_category: :global_search do
  subject(:instance) { described_class.new }

  let(:version) { '20220101800000' }
  let(:file) { 'test_migrate.rb' }
  let(:migration) do
    instance_double(
      Elastic::MigrationRecord, version: version, name_for_key: 'test_migrate', filename: file, skip?: false
    )
  end

  let(:pending_docs_url) do
    'doc/integration/advanced_search/elasticsearch.md#all-migrations-must-be-finished-before-doing-a-major-upgrade'
  end

  before do
    allow(Elastic::MigrationRecord).to receive(:new).and_return(migration)
  end

  describe '.skip?' do
    context 'with elasticsearch disabled' do
      it 'returns true' do
        stub_ee_application_setting(elasticsearch_indexing?: false)
        expect(instance).to be_skip
      end
    end

    context 'with elasticsearch enabled' do
      it 'returns false' do
        stub_ee_application_setting(elasticsearch_indexing?: true)
        expect(instance).not_to be_skip
      end
    end
  end

  describe '.check?' do
    context 'with pending migrations' do
      it 'returns false' do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations!).and_return(true)

        expect(instance).not_to be_check
      end
    end

    context 'without pending migrations' do
      it 'returns true' do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations!).and_return(false)

        expect(instance).to be_check
      end
    end

    context 'when the search cluster is unreachable' do
      it 'returns false instead of propagating the error' do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations!)
          .and_raise(Elastic::DataMigrationService::ClusterUnreachableError, 'boom')

        expect(instance).not_to be_check
      end
    end

    context 'when elasticsearch indexing is disabled' do
      it 'returns true because the bang predicate short-circuits' do
        stub_ee_application_setting(elasticsearch_indexing: false)

        expect(instance).to be_check
      end
    end
  end

  describe '.show_error' do
    context 'with pending migrations' do
      before do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations!).and_return(true)
      end

      it 'returns the elasticsearch.md page' do
        expect(instance).to receive(:for_more_information).with(pending_docs_url)
        expect(instance).to receive(:try_fixing_it).with(
          'Wait for all advanced search migrations to complete.',
          'To list pending migrations, run `sudo gitlab-rake gitlab:elastic:list_pending_migrations`'
        )

        instance.show_error
      end
    end

    context 'when the search cluster is unreachable' do
      before do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations!)
          .and_raise(Elastic::DataMigrationService::ClusterUnreachableError, 'boom')
      end

      it 'gives connectivity advice instead of migration advice' do
        expect(instance).to receive(:for_more_information)
                             .with('doc/integration/advanced_search/elasticsearch.md')
        expect(instance).to receive(:try_fixing_it).with(
          'Check that the search cluster is running and reachable from this node, then run this check again.',
          'To check the connection, run `sudo gitlab-rake gitlab:elastic:info`'
        )

        instance.show_error
      end
    end
  end

  describe '#fail_info' do
    subject { described_class.fail_info }

    context 'when the cluster is reachable' do
      before do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations!).and_return(true)
      end

      context 'when pending migration count is 1' do
        before do
          allow(described_class).to receive(:pending_migrations_count).and_return 1
        end

        it { is_expected.to eq 'no (You have 1 pending migration.)' }
      end

      context 'when pending migration count is greater than 1' do
        before do
          allow(described_class).to receive(:pending_migrations_count).and_return 5
        end

        it { is_expected.to eq 'no (You have 5 pending migrations.)' }
      end
    end

    context 'when the search cluster is unreachable' do
      before do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations!)
          .and_raise(Elastic::DataMigrationService::ClusterUnreachableError, 'Search cluster ping failed.')
      end

      it 'reports the unreachable cluster with different text from the pending case' do
        is_expected.to eq(
          'no (Unable to determine migration status: Search cluster ping failed.)'
        )
      end
    end
  end

  describe 'cluster probes per executed check' do
    # SimpleExecutor calls #check?, .check_fail (=> .fail_info) and #show_error
    # separately, and each now probes the cluster itself instead of reading state
    # stashed by #check?. A failed check therefore probes up to three times.
    it 'probes the cluster once per callback on the failure path' do
      allow(Elastic::DataMigrationService).to receive(:pending_migrations!).and_return(true)
      allow(described_class).to receive(:pending_migrations_count).and_return(1)
      allow(instance).to receive(:for_more_information)
      allow(instance).to receive(:try_fixing_it)

      instance.check?
      described_class.fail_info
      instance.show_error

      expect(Elastic::DataMigrationService).to have_received(:pending_migrations!).exactly(3).times
    end
  end

  describe '#pending_migrations_count' do
    subject { described_class.pending_migrations_count }

    context 'with pending migrations' do
      before do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations).and_return([migration])
      end

      it { is_expected.to eq 1 }
    end

    context 'without pending migrations' do
      before do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations).and_return([])
      end

      it { is_expected.to eq 0 }
    end

    context 'when pending_migrations returns a nil value' do
      before do
        allow(Elastic::DataMigrationService).to receive(:pending_migrations).and_return(nil)
      end

      it { is_expected.to eq 0 }
    end
  end
end
