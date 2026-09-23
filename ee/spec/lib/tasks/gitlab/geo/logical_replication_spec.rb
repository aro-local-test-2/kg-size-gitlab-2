# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Tasks::Gitlab::Geo::LogicalReplication, feature_category: :geo_replication do
  subject(:instance) { Class.new.include(described_class).new }

  describe 'EXCLUDED_TABLES' do
    it 'matches the published contract, which only changes deliberately' do
      # GitLab Dedicated's seed job derives its expectations from the live publication and fails
      # on drift, so adding or removing a table here needs a matching change there.
      expect(described_class::EXCLUDED_TABLES).to contain_exactly(
        'ar_internal_metadata',
        'batched_background_migration_job_transition_logs',
        'batched_background_migration_jobs',
        'batched_background_migrations',
        'detached_partitions',
        'postgres_async_foreign_key_validations',
        'postgres_async_indexes',
        'postgres_reindex_actions',
        'postgres_reindex_queued_actions',
        'schema_migrations'
      )
    end

    it 'names tables that exist, so a rename cannot silently leave one published',
      :aggregate_failures do
      described_class::EXCLUDED_TABLES.each do |table|
        expect(ApplicationRecord.connection.table_exists?(table)).to be(true), "#{table} does not exist"
      end
    end
  end

  describe 'SEEDED_METADATA_TABLES' do
    it 'is a subset of EXCLUDED_TABLES, since seeding only makes sense for unreplicated tables' do
      expect(described_class::EXCLUDED_TABLES).to include(*described_class::SEEDED_METADATA_TABLES)
    end
  end

  describe '#publication_name' do
    context 'when the GEO_PUBLICATION env var is unset' do
      it 'defaults to "geo_publication"' do
        stub_env('GEO_PUBLICATION', nil)

        expect(instance.publication_name).to eq('geo_publication')
      end
    end

    context 'when the GEO_PUBLICATION env var is set' do
      it 'returns the value from the environment' do
        stub_env('GEO_PUBLICATION', 'my_custom_publication')

        expect(instance.publication_name).to eq('my_custom_publication')
      end
    end
  end

  describe '#publication_tables' do
    context 'when the publication name is empty' do
      it 'returns an empty hash without querying the database' do
        expect(ApplicationRecord.connection).not_to receive(:execute)

        expect(instance.publication_tables('')).to eq({})
      end
    end

    context 'when the publication exists' do
      let(:result) { instance_double(PG::Result, values: [%w[projects public], %w[users public]]) }

      it 'maps the registered table names to the schema each one lives in' do
        expect(ApplicationRecord.connection).to receive(:execute) do |sql|
          expect(sql).to match(/FROM pg_publication p/)
          expect(sql).to match(/JOIN pg_publication_rel pr ON pr\.prpubid = p\.oid/)
          expect(sql).to match(/JOIN pg_class c ON c\.oid = pr\.prrelid/)
          expect(sql).to match(/JOIN pg_namespace n ON n\.oid = c\.relnamespace/)
          expect(sql).to include("p.pubname IN ('geo_publication')")

          result
        end

        expect(instance.publication_tables('geo_publication'))
          .to eq('projects' => 'public', 'users' => 'public')
      end

      it 'quotes the publication name to guard against SQL injection' do
        expect(ApplicationRecord.connection).to receive(:execute) do |sql|
          expect(sql).to include("p.pubname IN ('o''hara''')")
          result
        end

        instance.publication_tables("o'hara'")
      end
    end

    context 'when the publication has no tables' do
      let(:result) { instance_double(PG::Result, values: []) }

      it 'returns an empty hash' do
        allow(ApplicationRecord.connection).to receive(:execute).and_return(result)

        expect(instance.publication_tables('geo_publication')).to eq({})
      end
    end
  end

  describe '#partition_roots' do
    let(:leaf) { 'batched_background_migration_job_transition_logs_202603' }
    let(:root) { 'batched_background_migration_job_transition_logs' }
    let(:result) { instance_double(PG::Result, values: [[leaf, root]]) }

    it 'maps every partition to the name of its root partitioned table' do
      expect(ApplicationRecord.connection).to receive(:execute) do |sql|
        expect(sql).to match(/WITH RECURSIVE/)
        expect(sql).to match(/pg_catalog\.pg_inherits/)

        result
      end

      expect(instance.partition_roots).to eq(leaf => root)
    end

    it 'has no entry for a table that is not a partition' do
      allow(ApplicationRecord.connection).to receive(:execute).and_return(result)

      expect(instance.partition_roots['projects']).to be_nil
    end
  end

  describe '#excluded_table?' do
    let(:excluded_leaf) { 'batched_background_migration_job_transition_logs_202603' }
    let(:roots) do
      {
        excluded_leaf => 'batched_background_migration_job_transition_logs',
        'ci_builds_101' => 'ci_builds'
      }
    end

    it 'is true for a table listed in EXCLUDED_TABLES' do
      expect(instance.excluded_table?('schema_migrations', roots)).to be(true)
    end

    it 'is true for a partition whose root partitioned table is excluded' do
      expect(instance.excluded_table?(excluded_leaf, roots)).to be(true)
    end

    it 'is false for a partition whose root partitioned table is not excluded' do
      expect(instance.excluded_table?('ci_builds_101', roots)).to be(false)
    end

    it 'is false for a table that is neither excluded nor a partition' do
      expect(instance.excluded_table?('projects', roots)).to be(false)
    end
  end

  describe '#alter_publication' do
    before do
      allow(ApplicationRecord.connection).to receive(:execute)
    end

    context 'when the action is "ADD"' do
      it 'issues an ALTER PUBLICATION ... ADD TABLE statement with a quoted identifier' do
        instance.alter_publication('ADD', 'projects')

        expect(ApplicationRecord.connection).to have_received(:execute)
          .with('ALTER PUBLICATION geo_publication ADD TABLE "projects"')
      end
    end

    context 'when the action is "DROP"' do
      it 'issues an ALTER PUBLICATION ... DROP TABLE statement with a quoted identifier' do
        instance.alter_publication('DROP', 'projects')

        expect(ApplicationRecord.connection).to have_received(:execute)
          .with('ALTER PUBLICATION geo_publication DROP TABLE "projects"')
      end
    end

    context 'when the action is anything else' do
      it 'raises ArgumentError and does not issue a query' do
        expect { instance.alter_publication('TRUNCATE', 'projects') }
          .to raise_error(ArgumentError, /action must be ADD or DROP/)

        expect(ApplicationRecord.connection).not_to have_received(:execute)
      end
    end
  end

  describe '#publisher_connection_string' do
    it 'returns the value of the GEO_PUBLISHER_CONNECTION_STRING env var' do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', 'postgresql://primary/gitlabhq_production')

      expect(instance.publisher_connection_string).to eq('postgresql://primary/gitlabhq_production')
    end

    it 'returns nil when the env var is unset' do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', nil)

      expect(instance.publisher_connection_string).to be_nil
    end
  end

  describe '#copy_data?' do
    it 'defaults to true when the GEO_SUBSCRIPTION_COPY_DATA env var is unset' do
      stub_env('GEO_SUBSCRIPTION_COPY_DATA', nil)

      expect(instance.copy_data?).to be(true)
    end

    it 'returns false only for the literal value "false"' do
      stub_env('GEO_SUBSCRIPTION_COPY_DATA', 'false')

      expect(instance.copy_data?).to be(false)
    end

    it 'returns true for any other value' do
      stub_env('GEO_SUBSCRIPTION_COPY_DATA', 'no')

      expect(instance.copy_data?).to be(true)
    end
  end

  describe '#subscriber_connection_string' do
    it 'returns the value of the GEO_SUBSCRIBER_CONNECTION_STRING env var' do
      stub_env('GEO_SUBSCRIBER_CONNECTION_STRING', 'postgresql://secondary/gitlabhq_production')

      expect(instance.subscriber_connection_string).to eq('postgresql://secondary/gitlabhq_production')
    end

    it 'returns nil when the env var is unset' do
      stub_env('GEO_SUBSCRIBER_CONNECTION_STRING', nil)

      expect(instance.subscriber_connection_string).to be_nil
    end
  end

  describe '#with_subscriber_connection' do
    let(:subscriber_connection) { instance_double(PG::Connection, close: true) }

    before do
      stub_env('GEO_SUBSCRIBER_CONNECTION_STRING', 'postgresql://secondary/gitlabhq_production')
      allow(PG).to receive(:connect)
        .with('postgresql://secondary/gitlabhq_production').and_return(subscriber_connection)
    end

    it 'yields the subscriber connection and closes it' do
      expect { |block| instance.with_subscriber_connection(&block) }.to yield_with_args(subscriber_connection)

      expect(subscriber_connection).to have_received(:close)
    end

    it 'closes the connection when the block raises' do
      expect { instance.with_subscriber_connection { raise PG::Error, 'boom' } }.to raise_error(PG::Error)

      expect(subscriber_connection).to have_received(:close)
    end
  end

  describe '#current_database_subscription' do
    let(:connection) { instance_double(PG::Connection) }

    it 'scopes the lookup to the current database and the configured subscription name' do
      row = { 'oid' => '16400', 'subslotname' => 'geo_subscription', 'subenabled' => 't' }

      expect(connection).to receive(:exec_params) do |sql, params|
        expect(sql).to match(/SELECT s\.oid, s\.subslotname, s\.subenabled/)
        expect(sql).to match(/JOIN pg_catalog\.pg_database d ON d\.oid = s\.subdbid/)
        expect(sql).to match(/d\.datname = current_database\(\)/)
        expect(sql).to match(/s\.subname = \$1/)
        expect(params).to eq(['geo_subscription'])

        instance_double(PG::Result, first: row)
      end

      expect(instance.current_database_subscription(connection)).to eq(row)
    end

    it 'passes the subscription name as a bind parameter rather than interpolating it' do
      stub_env('GEO_SUBSCRIPTION', "o'hara'")

      expect(connection).to receive(:exec_params) do |sql, params|
        expect(sql).not_to include("o'hara'")
        expect(params).to eq(["o'hara'"])

        instance_double(PG::Result, first: nil)
      end

      instance.current_database_subscription(connection)
    end
  end

  describe '#local_database_owns_publication?' do
    let(:connection) { instance_double(PG::Connection) }

    it 'is true when the local database has the publication' do
      expect(connection).to receive(:exec_params)
        .with("SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = $1", ['geo_publication'])
        .and_return([{ '?column?' => '1' }])

      expect(instance.local_database_owns_publication?(connection)).to be(true)
    end

    it 'is false when the local database has no such publication' do
      allow(connection).to receive(:exec_params).and_return([])

      expect(instance.local_database_owns_publication?(connection)).to be(false)
    end
  end

  describe '#application_settings_present?' do
    let(:connection) { instance_double(PG::Connection) }

    it 'is true when the table has rows' do
      allow(connection).to receive(:exec).and_return([{ 'present' => 't' }])

      expect(instance.application_settings_present?(connection)).to be(true)
    end

    it 'is false when the table is empty' do
      allow(connection).to receive(:exec).and_return([{ 'present' => 'f' }])

      expect(instance.application_settings_present?(connection)).to be(false)
    end

    it 'lets PG::UndefinedTable through so callers can report an unseeded schema' do
      allow(connection).to receive(:exec).and_raise(PG::UndefinedTable, 'does not exist')

      expect { instance.application_settings_present?(connection) }.to raise_error(PG::UndefinedTable)
    end
  end

  describe '#drop_publisher_replication_slots' do
    let(:sync_slots_result) { instance_double(PG::Result, values: []) }
    let(:publisher_connection) do
      instance_double(PG::Connection, exec: true, exec_params: sync_slots_result, close: true)
    end

    before do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', 'postgresql://primary/gitlabhq_production')
      allow(publisher_connection).to receive(:escape_literal) { |value| "'#{value}'" }
      allow(PG).to receive(:connect).with('postgresql://primary/gitlabhq_production').and_return(publisher_connection)
    end

    it 'drops the replication slot on the publisher and closes the connection' do
      instance.drop_publisher_replication_slots('geo_subscription', 'pg\_16400\_sync\_%')

      expect(publisher_connection).to have_received(:exec)
        .with("SELECT pg_drop_replication_slot('geo_subscription')")
      expect(publisher_connection).to have_received(:close)
    end

    it 'also drops any stranded tablesync slots matching the pattern' do
      allow(publisher_connection).to receive(:exec_params)
        .with("SELECT slot_name FROM pg_replication_slots WHERE slot_name LIKE $1", ['pg\_16400\_sync\_%'])
        .and_return(instance_double(PG::Result, values: [['pg_16400_sync_16501_123'], ['pg_16400_sync_16502_123']]))

      instance.drop_publisher_replication_slots('geo_subscription', 'pg\_16400\_sync\_%')

      expect(publisher_connection).to have_received(:exec)
        .with("SELECT pg_drop_replication_slot('geo_subscription')")
      expect(publisher_connection).to have_received(:exec)
        .with("SELECT pg_drop_replication_slot('pg_16400_sync_16501_123')")
      expect(publisher_connection).to have_received(:exec)
        .with("SELECT pg_drop_replication_slot('pg_16400_sync_16502_123')")
    end

    it 'closes the connection even when dropping the slot fails' do
      allow(publisher_connection).to receive(:exec).and_raise(PG::Error, 'boom')

      expect { instance.drop_publisher_replication_slots('geo_subscription', 'pg\_16400\_sync\_%') }
        .to raise_error(PG::Error)
      expect(publisher_connection).to have_received(:close)
    end

    it 'still attempts and logs earlier slots when a later slot exhausts its drop retries' do
      allow(instance).to receive(:sleep)
      allow(publisher_connection).to receive(:exec_params)
        .with("SELECT slot_name FROM pg_replication_slots WHERE slot_name LIKE $1", ['pg\_16400\_sync\_%'])
        .and_return(instance_double(PG::Result, values: [['pg_16400_sync_16501_123'], ['pg_16400_sync_16502_123']]))
      allow(publisher_connection).to receive(:exec) do |sql|
        raise PG::ObjectInUse, 'slot is active' if sql.include?('pg_16400_sync_16502_123')

        true
      end

      expect { instance.drop_publisher_replication_slots('geo_subscription', 'pg\_16400\_sync\_%') }
        .to output(/Dropped replication slot pg_16400_sync_16501_123 on the publisher/).to_stdout
        .and raise_error(PG::ObjectInUse)

      expect(publisher_connection).to have_received(:exec)
        .with("SELECT pg_drop_replication_slot('pg_16400_sync_16501_123')")
      expect(publisher_connection).to have_received(:exec)
        .with("SELECT pg_drop_replication_slot('pg_16400_sync_16502_123')")
        .exactly(described_class::DROP_SLOT_ATTEMPTS).times
    end
  end

  describe '#drop_replication_slot' do
    let(:publisher_connection) { instance_double(PG::Connection, exec: true) }

    before do
      allow(publisher_connection).to receive(:escape_literal) { |value| "'#{value}'" }
    end

    it 'reports an already-dropped slot instead of raising' do
      allow(publisher_connection).to receive(:exec).and_raise(PG::UndefinedObject, 'does not exist')

      expect { instance.drop_replication_slot(publisher_connection, 'geo_subscription') }
        .to output(/Replication slot geo_subscription does not exist on the publisher/).to_stdout
    end

    it 'retries while the walsender still holds the slot' do
      calls = 0
      allow(instance).to receive(:sleep)
      allow(publisher_connection).to receive(:exec) do
        calls += 1
        raise PG::ObjectInUse, 'slot is active' if calls < 3

        true
      end

      expect { instance.drop_replication_slot(publisher_connection, 'geo_subscription') }
        .to output(/Dropped replication slot geo_subscription on the publisher/).to_stdout
      expect(calls).to eq(3)
    end

    it 'gives up after repeated PG::ObjectInUse errors' do
      allow(instance).to receive(:sleep)
      allow(publisher_connection).to receive(:exec).and_raise(PG::ObjectInUse, 'slot is active')

      expect { instance.drop_replication_slot(publisher_connection, 'geo_subscription') }
        .to raise_error(PG::ObjectInUse)
      expect(publisher_connection).to have_received(:exec)
        .exactly(described_class::DROP_SLOT_ATTEMPTS).times
    end
  end

  describe '#manual_slot_cleanup_message' do
    it 'includes the cleanup SQL for the main slot and the tablesync slot pattern' do
      message = instance.manual_slot_cleanup_message('geo_subscription', 'pg\_16400\_sync\_%')

      expect(message).to include('Run this manually on the publisher')
      expect(message).to include("slot_name = 'geo_subscription' OR slot_name LIKE 'pg\\_16400\\_sync\\_%'")
    end
  end

  describe '#subscription_created_message' do
    it 'names the subscription and points at the sequence sync step' do
      stub_env('GEO_SUBSCRIPTION', 'geo_subscription')

      message = instance.subscription_created_message

      expect(message).to include('The subscription geo_subscription was created')
      expect(message).to include('gitlab:geo:logical_replication:sync_sequences')
    end
  end

  describe '#with_publisher_connection' do
    let(:publisher_connection) { instance_double(PG::Connection, close: true) }

    before do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', 'postgresql://primary/gitlabhq_production')
      allow(PG).to receive(:connect)
        .with('postgresql://primary/gitlabhq_production').and_return(publisher_connection)
    end

    it 'yields the publisher connection and closes it' do
      expect { |block| instance.with_publisher_connection(&block) }.to yield_with_args(publisher_connection)

      expect(publisher_connection).to have_received(:close)
    end

    it 'closes the connection when the block raises' do
      expect { instance.with_publisher_connection { raise PG::Error, 'boom' } }.to raise_error(PG::Error)

      expect(publisher_connection).to have_received(:close)
    end
  end

  describe '#schema_migrations_present?' do
    let(:connection) { instance_double(PG::Connection) }

    it 'lets PG::UndefinedTable through so callers can report an unseeded schema' do
      allow(connection).to receive(:exec).and_raise(PG::UndefinedTable, 'does not exist')

      expect { instance.schema_migrations_present?(connection) }.to raise_error(PG::UndefinedTable)
    end
  end

  describe '#missing_seeded_metadata_tables' do
    # A real libpq connection, so the catalog query actually runs against PostgreSQL.
    let(:connection) { ApplicationRecord.connection.raw_connection }

    it 'returns nothing when the seeded tables exist' do
      expect(instance.missing_seeded_metadata_tables(connection)).to eq([])
    end

    it 'names the tables that do not exist' do
      stub_const("#{described_class}::SEEDED_METADATA_TABLES", %w[schema_migrations not_a_real_table])

      expect(instance.missing_seeded_metadata_tables(connection)).to eq(%w[not_a_real_table])
    end
  end

  describe '#ar_internal_metadata_environment' do
    let(:connection) { instance_double(PG::Connection) }

    it 'looks the key up with a bind parameter' do
      expect(connection).to receive(:exec_params) do |sql, params|
        expect(sql).not_to include('environment')
        expect(params).to eq(['environment'])

        instance_double(PG::Result, first: { 'value' => 'production' })
      end

      expect(instance.ar_internal_metadata_environment(connection)).to eq('production')
    end
  end

  describe '#read_publisher_metadata' do
    let(:connection) { instance_double(PG::Connection) }

    before do
      allow(connection).to receive(:exec) do |sql|
        if sql.include?('SELECT version')
          instance_double(PG::Result, values: [['20260101000000']])
        elsif sql.include?('ar_internal_metadata')
          instance_double(PG::Result, values: [%w[environment production 2026-01-01 2026-01-01]])
        end
      end
    end

    it 'reads both tables from one repeatable read snapshot', :aggregate_failures do
      state = instance.read_publisher_metadata(connection)

      expect(connection).to have_received(:exec).with('BEGIN ISOLATION LEVEL REPEATABLE READ')
      expect(state).to eq(
        versions: ['20260101000000'],
        metadata_rows: [%w[environment production 2026-01-01 2026-01-01]]
      )
    end
  end

  describe '#write_subscriber_metadata' do
    let(:connection) { instance_double(PG::Connection, exec: nil, exec_params: nil) }

    before do
      allow(connection).to receive(:quote_ident) { |value| %("#{value}") }
    end

    it 'batches the inserts so a large table cannot exhaust the bind parameter limit' do
      stub_const("#{described_class}::METADATA_INSERT_BATCH_SIZE", 2)

      instance.write_subscriber_metadata(connection, versions: %w[1 2 3], metadata_rows: [])

      expect(connection).to have_received(:exec_params).with(
        'INSERT INTO "schema_migrations" ("version") VALUES ($1), ($2)', %w[1 2]
      )
      expect(connection).to have_received(:exec_params).with(
        'INSERT INTO "schema_migrations" ("version") VALUES ($1)', %w[3]
      )
    end

    it 'skips the insert when the publisher table is empty' do
      instance.write_subscriber_metadata(connection, versions: [], metadata_rows: [])

      expect(connection).not_to have_received(:exec_params)
    end

    context 'when a statement fails' do
      before do
        allow(connection).to receive(:exec).with(/TRUNCATE/).and_raise(PG::InsufficientPrivilege, 'permission denied')
      end

      it 'rolls back and re-raises, leaving the connection usable', :aggregate_failures do
        expect { instance.write_subscriber_metadata(connection, versions: %w[1], metadata_rows: []) }
          .to raise_error(PG::InsufficientPrivilege)

        expect(connection).to have_received(:exec).with('ROLLBACK')
        expect(connection).not_to have_received(:exec).with('COMMIT')
      end
    end
  end

  describe '#schema_migrations_mismatch_message' do
    it 'caps each list and still reports the total' do
      missing = (1..25).map { |index| format('202601%<index>02d000000', index: index) }

      message = instance.schema_migrations_mismatch_message(
        missing, [], subscription_present: false, subscription_enabled: false
      )

      expect(message).to include('Missing on the subscriber (25, first 20 shown)')
      expect(message).not_to include('20260121000000')
    end

    it 'omits the side that has no differences' do
      message = instance.schema_migrations_mismatch_message(
        [], %w[20260101000000], subscription_present: false, subscription_enabled: false
      )

      expect(message).to include('Extra on the subscriber (1): 20260101000000')
      expect(message).not_to include('Missing on the subscriber')
    end

    context 'when there is no subscription yet' do
      it 'points missing versions at a re-seed', :aggregate_failures do
        message = instance.schema_migrations_mismatch_message(
          %w[20260101000000], [], subscription_present: false, subscription_enabled: false
        )

        expect(message).to include('A migration landed on the publisher after the seed')
        expect(message).to include('gitlab:geo:logical_replication:metadata:seed')
      end

      it 'describes extra versions as stale', :aggregate_failures do
        message = instance.schema_migrations_mismatch_message(
          [], %w[20260101000000], subscription_present: false, subscription_enabled: false
        )

        expect(message).to include('These rows are stale')
        expect(message).to include('gitlab:geo:logical_replication:metadata:seed')
      end
    end

    context 'when a subscription exists' do
      it 'names the publisher as the side that is ahead', :aggregate_failures do
        message = instance.schema_migrations_mismatch_message(
          %w[20260101000000], [], subscription_present: true, subscription_enabled: true
        )

        expect(message).to include('The publisher is ahead')
        expect(message).to include('replication stalls')
        expect(message).to include('db:migrate on the subscriber')
        expect(message).to include('gitlab:geo:logical_replication:subscription:refresh')
        expect(message).not_to include('metadata:seed')
      end

      it 'reports replication as paused when the subscription is disabled', :aggregate_failures do
        message = instance.schema_migrations_mismatch_message(
          %w[20260101000000], [], subscription_present: true, subscription_enabled: false
        )

        expect(message).to include('The publisher is ahead')
        expect(message).to include('replication is paused')
        expect(message).not_to include('stalls')
        expect(message).to include('db:migrate on the subscriber')
        expect(message).to include('gitlab:geo:logical_replication:publication:set_tables')
        expect(message).to include('gitlab:geo:logical_replication:metadata:verify')
        expect(message.index('subscription:enable')).to be < message.index('subscription:refresh')
      end

      it 'names the subscriber as the side that is ahead', :aggregate_failures do
        message = instance.schema_migrations_mismatch_message(
          [], %w[20260101000000], subscription_present: true, subscription_enabled: true
        )

        expect(message).to include('The subscriber is ahead')
        expect(message).to include('db:migrate on the publisher')
        expect(message).not_to include('metadata:seed')
      end
    end
  end

  describe '#subscription_disabled_message' do
    it 'explains the pause and lists the upgrade steps in order', :aggregate_failures do
      message = instance.subscription_disabled_message

      expect(message).to include('Subscription geo_subscription disabled')
      expect(message).to include('retains WAL')
      expect(message).to include('db:migrate on the publisher')
      expect(message).to include('db:migrate on the subscriber')
      expect(message).to include('publication:set_tables')
      expect(message).to include('metadata:verify')
      expect(message).to include('subscription:enable')
      expect(message).to include('subscription:refresh')
    end
  end

  describe '#subscription_enabled_message' do
    it 'reports the resume and points at refresh', :aggregate_failures do
      message = instance.subscription_enabled_message

      expect(message).to include('Subscription geo_subscription enabled')
      expect(message).to include('gitlab:geo:logical_replication:subscription:refresh')
    end
  end
end
