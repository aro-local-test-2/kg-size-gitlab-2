# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:geo:logical_replication:*', :silence_stdout, :aggregate_failures, feature_category: :geo_replication do
  include RakeHelpers
  include ::EE::GeoHelpers

  let(:statement_invalid) { ActiveRecord::StatementInvalid.new }

  before_all do
    # db:migrate has to exist before the task file is loaded, because it hooks the sequence sync
    # into it. Rails defines it for real; a stub keeps that hook independent of spec load order.
    Rake::Task.define_task('db:migrate') unless Rake::Task.task_defined?('db:migrate')
    Rake.application.rake_require 'tasks/gitlab/geo/logical_replication'
    Rake::Task.define_task(:gitlab_environment)
  end

  before do
    %w[
      publication:create
      publication:delete
      publication:set_tables
      preflight:write_activity
      subscription:refresh
      subscription:create
      subscription:disable
      subscription:enable
      subscription:drop
      metadata:seed
      metadata:verify
    ].each { |task| Rake::Task["gitlab:geo:logical_replication:#{task}"].reenable }
  end

  # The subscription tasks run without the Rails environment and talk to PostgreSQL over libpq, so
  # they are driven entirely through stubbed PG connections rather than ApplicationRecord.
  shared_context 'with libpq connections' do
    let(:subscriber_connection_string) { 'postgresql://secondary/gitlabhq_production' }
    let(:publisher_connection_string) { 'postgresql://primary/gitlabhq_production' }
    let(:owns_publication_result) { [] }
    let(:application_settings_result) { [{ 'present' => 'f' }] }
    let(:schema_migrations_result) { [{ 'present' => 't' }] }
    let(:missing_metadata_tables) { [] }
    let(:subscription_row) do
      { 'oid' => '16400', 'subslotname' => 'geo_subscription', 'subenabled' => 't' }
    end

    let(:sync_slots_result) { instance_double(PG::Result, values: []) }
    let(:publisher_versions) { %w[20260101000000 20260102000000] }
    let(:subscriber_versions) { publisher_versions }
    let(:publisher_environment) { 'production' }
    let(:subscriber_environment) { publisher_environment }

    let(:publisher_metadata_rows) do
      [['environment', 'production', '2026-01-01 00:00:00', '2026-01-01 00:00:00']]
    end

    let(:subscriber_connection) do
      instance_double(PG::Connection, close: true, user: 'geo_subscription_owner', db: 'gitlabhq_production')
    end

    let(:publisher_connection) do
      instance_double(PG::Connection, close: true, user: 'gitlab_replicator', db: 'gitlabhq_production')
    end

    before do
      stub_env('GEO_SUBSCRIBER_CONNECTION_STRING', subscriber_connection_string)

      allow(subscriber_connection).to receive(:quote_ident) { |value| %("#{value}") }
      allow(subscriber_connection).to receive(:escape_literal) { |value| "'#{value}'" }
      allow(subscriber_connection).to receive(:exec) do |sql|
        if sql.include?('SELECT version')
          instance_double(PG::Result, values: subscriber_versions.map { |version| [version] })
        elsif sql.include?('application_settings')
          application_settings_result
        elsif sql.include?('schema_migrations')
          schema_migrations_result
        end
      end
      allow(subscriber_connection).to receive(:exec_params) do |sql, _params|
        if sql.include?('pg_publication')
          owns_publication_result
        elsif sql.include?('pg_subscription')
          instance_double(PG::Result, first: subscription_row)
        elsif sql.include?('to_regclass')
          instance_double(PG::Result, values: missing_metadata_tables.map { |table| [table] })
        elsif sql.include?('SELECT value FROM ar_internal_metadata')
          instance_double(PG::Result, first: subscriber_environment && { 'value' => subscriber_environment })
        end
      end

      allow(publisher_connection).to receive(:quote_ident) { |value| %("#{value}") }
      allow(publisher_connection).to receive(:escape_literal) { |value| "'#{value}'" }
      allow(publisher_connection).to receive(:exec) do |sql|
        if sql.include?('SELECT version')
          instance_double(PG::Result, values: publisher_versions.map { |version| [version] })
        elsif sql.include?('FROM ar_internal_metadata')
          instance_double(PG::Result, values: publisher_metadata_rows)
        end
      end
      allow(publisher_connection).to receive(:exec_params) do |sql, _params|
        if sql.include?('SELECT value FROM ar_internal_metadata')
          instance_double(PG::Result, first: publisher_environment && { 'value' => publisher_environment })
        else
          sync_slots_result
        end
      end

      allow(PG).to receive(:connect).with(subscriber_connection_string).and_return(subscriber_connection)
      allow(PG).to receive(:connect).with(publisher_connection_string).and_return(publisher_connection)
    end
  end

  describe 'gitlab:geo:logical_replication:publication:create' do
    let(:task_name) { 'gitlab:geo:logical_replication:publication:create' }

    context 'when running on a primary site' do
      before do
        stub_primary_site
        allow(ApplicationRecord.connection).to receive(:execute)
      end

      it 'creates the publication' do
        run_rake_task(task_name)

        expect(ApplicationRecord.connection).to have_received(:execute)
          .with("CREATE PUBLICATION geo_publication;")
      end

      context 'when the publication already exists' do
        before do
          allow(statement_invalid).to receive(:cause).and_return(PG::DuplicateObject.new)
          allow(ApplicationRecord.connection).to receive(:execute).and_raise(statement_invalid)
        end

        it 'reports the publication exists and does not raise' do
          expect { run_rake_task(task_name) }
            .to output(/Publication already exists/).to_stdout
        end
      end

      context 'when an unexpected database error occurs' do
        before do
          allow(ApplicationRecord.connection).to receive(:execute).and_raise(
            ActiveRecord::StatementInvalid.new('syntax error')
          )
        end

        it 're-raises the error' do
          expect { run_rake_task(task_name) }.to raise_error(ActiveRecord::StatementInvalid)
        end
      end
    end

    context 'when running on a secondary site' do
      before do
        stub_secondary_site
      end

      it 'aborts' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/only available on the primary node/).to_stderr
      end
    end
  end

  describe 'gitlab:geo:logical_replication:publication:delete' do
    let(:task_name) { 'gitlab:geo:logical_replication:publication:delete' }

    context 'when running on a primary site' do
      before do
        stub_primary_site
        allow(ApplicationRecord.connection).to receive(:execute)
      end

      it 'drops the publication' do
        run_rake_task(task_name)

        expect(ApplicationRecord.connection).to have_received(:execute)
          .with("DROP PUBLICATION geo_publication;")
      end

      context 'when the publication does not exist' do
        before do
          allow(statement_invalid).to receive(:cause).and_return(PG::UndefinedObject.new)
          allow(ApplicationRecord.connection).to receive(:execute).and_raise(statement_invalid)
        end

        it 'reports the publication does not exist and does not raise' do
          expect { run_rake_task(task_name) }
            .to output(/publication does not exist/).to_stdout
        end
      end

      context 'when an unexpected database error occurs' do
        before do
          allow(statement_invalid).to receive(:cause).and_return(StandardError.new)
          allow(ApplicationRecord.connection).to receive(:execute).and_raise(statement_invalid)
        end

        it 're-raises the error' do
          expect { run_rake_task(task_name) }.to raise_error(ActiveRecord::StatementInvalid)
        end
      end
    end

    context 'when running on a secondary site' do
      before do
        stub_secondary_site
      end

      it 'aborts' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/only available on the primary node/).to_stderr
      end
    end
  end

  describe 'gitlab:geo:logical_replication:publication:set_tables' do
    let(:task_name) { 'gitlab:geo:logical_replication:publication:set_tables' }
    let(:db_tables) { %w[projects users ar_internal_metadata schema_migrations] }
    let(:current_publication_tables) { [] }
    let(:partition_roots) { {} }
    let(:published_schemas) { {} }

    context 'when running on a primary site' do
      before do
        stub_primary_site
        allow(ApplicationRecord.connection).to receive(:execute) do |sql|
          if sql.include?('pg_catalog.pg_inherits')
            instance_double(PG::Result, values: partition_roots.to_a)
          elsif sql.match?(/SELECT.*pg_publication/m)
            instance_double(PG::Result, values: current_publication_tables.map do |t|
              [t, published_schemas.fetch(t, 'public')]
            end)
          end
        end
        allow(ApplicationRecord.connection).to receive(:tables).and_return(db_tables)
      end

      context 'when no tables are in the publication yet' do
        it 'adds every non-excluded table' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).to have_received(:execute)
            .with('ALTER PUBLICATION geo_publication ADD TABLE "projects"')
          expect(ApplicationRecord.connection).to have_received(:execute)
            .with('ALTER PUBLICATION geo_publication ADD TABLE "users"')
        end

        it 'does not add excluded tables' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).not_to have_received(:execute)
            .with(/ADD TABLE "schema_migrations"/)
          expect(ApplicationRecord.connection).not_to have_received(:execute)
            .with(/ADD TABLE "ar_internal_metadata"/)
        end
      end

      context 'when a table is already in the publication' do
        let(:current_publication_tables) { %w[projects] }

        it 'does not add it again' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).not_to have_received(:execute)
            .with(/ADD TABLE "projects"/)
        end

        it 'still adds tables not yet in the publication' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).to have_received(:execute)
            .with('ALTER PUBLICATION geo_publication ADD TABLE "users"')
        end
      end

      context 'when an excluded table is currently in the publication' do
        let(:current_publication_tables) { %w[schema_migrations] }

        it 'removes the excluded table' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).to have_received(:execute)
            .with('ALTER PUBLICATION geo_publication DROP TABLE "schema_migrations"')
        end
      end

      context 'when an excluded table is not in the publication' do
        let(:current_publication_tables) { [] }

        it 'does not issue a DROP TABLE for it' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).not_to have_received(:execute)
            .with(/DROP TABLE "schema_migrations"/)
        end
      end

      it 'resolves the partition roots once, not once per table' do
        run_rake_task(task_name)

        expect(ApplicationRecord.connection).to have_received(:execute)
          .with(/pg_catalog\.pg_inherits/).once
      end

      context 'when a partition of an excluded table is published' do
        let(:leaf) { 'batched_background_migration_job_transition_logs_202603' }
        let(:db_tables) { ['projects', leaf] }
        let(:partition_roots) { { leaf => 'batched_background_migration_job_transition_logs' } }
        let(:current_publication_tables) { [leaf] }

        it 'removes it, because exclusion follows the root partitioned table' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).to have_received(:execute)
            .with(%(ALTER PUBLICATION geo_publication DROP TABLE "#{leaf}"))
        end
      end

      context 'when a partition of an excluded table is not published' do
        let(:leaf) { 'batched_background_migration_job_transition_logs_202603' }
        let(:db_tables) { ['projects', leaf] }
        let(:partition_roots) { { leaf => 'batched_background_migration_job_transition_logs' } }

        it 'does not add it' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).not_to have_received(:execute)
            .with(/TABLE "#{leaf}"/)
        end
      end

      context 'when a partition Rails does not list is published and its root is excluded' do
        let(:leaf) { 'batched_background_migration_job_transition_logs_202609' }
        let(:db_tables) { %w[projects] }
        let(:current_publication_tables) { ['projects', leaf] }
        let(:published_schemas) { { leaf => 'gitlab_partitions_dynamic' } }
        let(:partition_roots) { { leaf => 'batched_background_migration_job_transition_logs' } }

        it 'removes it using its schema-qualified name', :aggregate_failures do
          expect { run_rake_task(task_name) }
            .to output(/Removing gitlab_partitions_dynamic\.#{leaf}/).to_stdout

          expect(ApplicationRecord.connection).to have_received(:execute)
            .with(%(ALTER PUBLICATION geo_publication DROP TABLE "gitlab_partitions_dynamic"."#{leaf}"))
        end
      end

      context 'when a partition Rails does not list is published and its root is not excluded' do
        let(:leaf) { 'ci_builds_101' }
        let(:db_tables) { %w[projects] }
        let(:current_publication_tables) { ['projects', leaf] }
        let(:published_schemas) { { leaf => 'gitlab_partitions_dynamic' } }
        let(:partition_roots) { { leaf => 'ci_builds' } }

        it 'leaves it in the publication' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).not_to have_received(:execute)
            .with(/DROP TABLE .*#{leaf}/)
        end
      end

      context 'when a partition of a table that is not excluded is not published' do
        let(:leaf) { 'ci_builds_101' }
        let(:db_tables) { ['projects', leaf] }
        let(:partition_roots) { { leaf => 'ci_builds' } }

        it 'adds it' do
          run_rake_task(task_name)

          expect(ApplicationRecord.connection).to have_received(:execute)
            .with(%(ALTER PUBLICATION geo_publication ADD TABLE "#{leaf}"))
        end
      end
    end

    context 'when running on a secondary site' do
      before do
        stub_secondary_site
      end

      it 'aborts via the :create prerequisite' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/only available on the primary node/).to_stderr
      end
    end
  end

  describe 'gitlab:geo:logical_replication:preflight:write_activity' do
    let(:task_name) { 'gitlab:geo:logical_replication:preflight:write_activity' }
    let(:publisher_connection_string) { 'postgresql://primary/gitlabhq_production' }
    let(:result) do
      instance_double(Gitlab::Geo::PublisherWriteActivityCheck::Result, message: 'no writes detected', blocking?: false)
    end

    before do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', publisher_connection_string)
      allow(Gitlab::Geo::PublisherWriteActivityCheck).to receive(:execute).and_return(result)
    end

    it 'runs the check against the validated connection string and reports the result' do
      expect { run_rake_task(task_name) }.to output(/no writes detected/).to_stdout

      expect(Gitlab::Geo::PublisherWriteActivityCheck)
        .to have_received(:execute).with(connection_string: publisher_connection_string)
    end

    context 'when the check reports blocking' do
      let(:result) do
        instance_double(
          Gitlab::Geo::PublisherWriteActivityCheck::Result, message: 'writes detected', blocking?: true
        )
      end

      it 'aborts with the message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/writes detected/).to_stderr
      end
    end

    context 'when GEO_PUBLISHER_CONNECTION_STRING is unset' do
      before do
        stub_env('GEO_PUBLISHER_CONNECTION_STRING', nil)
      end

      it 'aborts without running the check' do
        expect(Gitlab::Geo::PublisherWriteActivityCheck).not_to receive(:execute)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_PUBLISHER_CONNECTION_STRING must be set/).to_stderr
      end
    end
  end

  describe 'gitlab:geo:logical_replication:subscription:refresh' do
    include_context 'with libpq connections'

    let(:task_name) { 'gitlab:geo:logical_replication:subscription:refresh' }

    it 'refreshes the subscription and closes the connection' do
      expect { run_rake_task(task_name) }
        .to output(/Subscription geo_subscription refreshed\./).to_stdout

      expect(subscriber_connection).to have_received(:exec)
        .with('ALTER SUBSCRIPTION "geo_subscription" REFRESH PUBLICATION')
      expect(subscriber_connection).to have_received(:close)
    end

    context 'when GEO_SUBSCRIBER_CONNECTION_STRING is unset' do
      let(:subscriber_connection_string) { nil }

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_SUBSCRIBER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when the local database owns the publication' do
      let(:owns_publication_result) { [{ '?column?' => '1' }] }

      it 'aborts and closes the connection' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/owns publication geo_publication/).to_stderr

        expect(subscriber_connection).to have_received(:close)
      end
    end

    context 'when the subscription does not exist' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::UndefinedObject, 'does not exist')
      end

      it 'aborts' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/Subscription geo_subscription does not exist/).to_stderr
      end
    end

    context 'when it errors' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::Error, 'I am a spec error')
      end

      it 'prints out an error message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit, /Error refreshing the subscription: I am a spec error/)
      end
    end
  end

  describe 'gitlab:geo:logical_replication:subscription:disable' do
    include_context 'with libpq connections'

    let(:task_name) { 'gitlab:geo:logical_replication:subscription:disable' }

    it 'disables the subscription and prints the upgrade steps' do
      expect { run_rake_task(task_name) }.to output(
        a_string_including('Subscription geo_subscription disabled')
        .and(a_string_including('retains WAL'))
        .and(a_string_including('gitlab:geo:logical_replication:subscription:enable'))
      ).to_stdout

      expect(subscriber_connection).to have_received(:exec)
        .with('ALTER SUBSCRIPTION "geo_subscription" DISABLE')
      expect(subscriber_connection).to have_received(:close)
    end

    context 'when the subscription is already disabled' do
      let(:subscription_row) do
        { 'oid' => '16400', 'subslotname' => 'geo_subscription', 'subenabled' => 'f' }
      end

      it 'reports the state and does not alter the subscription' do
        expect { run_rake_task(task_name) }
          .to output(/Subscription geo_subscription is already disabled/).to_stdout

        expect(subscriber_connection).not_to have_received(:exec).with(/ALTER SUBSCRIPTION/)
      end
    end

    context 'when the subscription does not exist' do
      let(:subscription_row) { nil }

      it 'aborts without altering the subscription' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/Subscription geo_subscription does not exist/).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/ALTER SUBSCRIPTION/)
      end
    end

    context 'when GEO_SUBSCRIBER_CONNECTION_STRING is unset' do
      let(:subscriber_connection_string) { nil }

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_SUBSCRIBER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when the local database owns the publication' do
      let(:owns_publication_result) { [{ '?column?' => '1' }] }

      it 'aborts and closes the connection' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/owns publication geo_publication/).to_stderr

        expect(subscriber_connection).to have_received(:close)
      end
    end

    context 'when it errors' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::Error, 'I am a spec error')
      end

      it 'prints out an error message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit, /Error disabling the subscription: I am a spec error/)
      end
    end
  end

  describe 'gitlab:geo:logical_replication:subscription:enable' do
    include_context 'with libpq connections'

    let(:task_name) { 'gitlab:geo:logical_replication:subscription:enable' }
    let(:subscription_row) do
      { 'oid' => '16400', 'subslotname' => 'geo_subscription', 'subenabled' => 'f' }
    end

    it 'enables the subscription and points at refresh' do
      expect { run_rake_task(task_name) }.to output(
        a_string_including('Subscription geo_subscription enabled')
        .and(a_string_including('gitlab:geo:logical_replication:subscription:refresh'))
      ).to_stdout

      expect(subscriber_connection).to have_received(:exec)
        .with('ALTER SUBSCRIPTION "geo_subscription" ENABLE')
      expect(subscriber_connection).to have_received(:close)
    end

    context 'when the subscription is already enabled' do
      let(:subscription_row) do
        { 'oid' => '16400', 'subslotname' => 'geo_subscription', 'subenabled' => 't' }
      end

      it 'reports the state and does not alter the subscription' do
        expect { run_rake_task(task_name) }
          .to output(/Subscription geo_subscription is already enabled/).to_stdout

        expect(subscriber_connection).not_to have_received(:exec).with(/ALTER SUBSCRIPTION/)
      end
    end

    context 'when the subscription does not exist' do
      let(:subscription_row) { nil }

      it 'aborts without altering the subscription' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/Subscription geo_subscription does not exist/).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/ALTER SUBSCRIPTION/)
      end
    end

    context 'when GEO_SUBSCRIBER_CONNECTION_STRING is unset' do
      let(:subscriber_connection_string) { nil }

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_SUBSCRIBER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when the local database owns the publication' do
      let(:owns_publication_result) { [{ '?column?' => '1' }] }

      it 'aborts and closes the connection' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/owns publication geo_publication/).to_stderr

        expect(subscriber_connection).to have_received(:close)
      end
    end

    context 'when it errors' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::Error, 'I am a spec error')
      end

      it 'prints out an error message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit, /Error enabling the subscription: I am a spec error/)
      end
    end
  end

  describe 'gitlab:geo:logical_replication:subscription:create' do
    include_context 'with libpq connections'

    let(:task_name) { 'gitlab:geo:logical_replication:subscription:create' }

    before do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', publisher_connection_string)
    end

    it 'creates the subscription with copy_data enabled and quoted identifiers' do
      run_rake_task(task_name)

      expect(subscriber_connection).to have_received(:exec).with(
        a_string_including('CREATE SUBSCRIPTION "geo_subscription"')
        .and(a_string_including("CONNECTION 'postgresql://primary/gitlabhq_production'"))
        .and(a_string_including('PUBLICATION "geo_publication"'))
        .and(a_string_including('WITH (copy_data = true)'))
      )
    end

    it 'points the operator at the sequence sync step' do
      expect { run_rake_task(task_name) }
        .to output(/gitlab:geo:logical_replication:sync_sequences/).to_stdout
    end

    it 'closes the subscriber connection' do
      run_rake_task(task_name)

      expect(subscriber_connection).to have_received(:close)
    end

    context 'when GEO_SUBSCRIBER_CONNECTION_STRING is unset' do
      let(:subscriber_connection_string) { nil }

      it 'aborts naming the privileges the role needs' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('GEO_SUBSCRIBER_CONNECTION_STRING must be set')
            .and(a_string_including('pg_create_subscription'))
          ).to_stderr
      end
    end

    context 'when GEO_PUBLISHER_CONNECTION_STRING is unset' do
      before do
        stub_env('GEO_PUBLISHER_CONNECTION_STRING', nil)
      end

      it 'aborts with a clear message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_PUBLISHER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when the local database owns the publication' do
      let(:owns_publication_result) { [{ '?column?' => '1' }] }

      it 'aborts before creating anything' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/owns publication geo_publication/).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/CREATE SUBSCRIPTION/)
        expect(subscriber_connection).to have_received(:close)
      end
    end

    context 'when application_settings already has rows' do
      let(:application_settings_result) { [{ 'present' => 't' }] }

      it 'aborts explaining both causes and the remedy' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('application_settings already contains rows')
            .and(a_string_including('points at a live GitLab database'))
            .and(a_string_including('Rails booted against this subscriber'))
            .and(a_string_including('DELETE FROM application_settings;'))
          ).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/CREATE SUBSCRIPTION/)
      end

      context 'when GEO_SUBSCRIPTION_COPY_DATA is set to false' do
        before do
          stub_env('GEO_SUBSCRIPTION_COPY_DATA', 'false')
        end

        it 'skips the gate and creates the subscription without the initial data copy' do
          run_rake_task(task_name)

          expect(subscriber_connection).not_to have_received(:exec).with(/application_settings/)
          expect(subscriber_connection).to have_received(:exec)
            .with(a_string_including('WITH (copy_data = false)'))
        end

        it 'confirms creation without pointing at the sequence sync step, since no copy runs' do
          expect { run_rake_task(task_name) }
            .to output(
              a_string_including('Subscription geo_subscription was created.')
              .and(satisfy { |out| out.exclude?('sync_sequences') })
            ).to_stdout
        end
      end
    end

    context 'when the schema has not been seeded' do
      before do
        allow(subscriber_connection).to receive(:exec) do |sql|
          raise PG::UndefinedTable, 'relation "application_settings" does not exist' if
            sql.include?('application_settings')
        end
      end

      it 'aborts pointing at the schema-only dump' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('the schema has not been seeded on this database yet')
            .and(a_string_including('schema-only dump'))
          ).to_stderr
      end
    end

    context 'when schema_migrations is empty' do
      let(:schema_migrations_result) { [{ 'present' => 'f' }] }

      it 'aborts pointing at the metadata seed task' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('schema_migrations is empty on this database')
            .and(a_string_including('gitlab:geo:logical_replication:metadata:seed'))
          ).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/CREATE SUBSCRIPTION/)
      end

      context 'when GEO_SUBSCRIPTION_COPY_DATA is set to false' do
        before do
          stub_env('GEO_SUBSCRIPTION_COPY_DATA', 'false')
        end

        it 'skips the gate and creates the subscription' do
          run_rake_task(task_name)

          expect(subscriber_connection).to have_received(:exec)
            .with(a_string_including('WITH (copy_data = false)'))
        end
      end
    end

    context 'when the role cannot read application_settings' do
      let(:table_owner_result) { [{ 'owner' => 'gitlab' }] }

      before do
        allow(subscriber_connection).to receive(:exec) do |sql|
          raise PG::InsufficientPrivilege, 'permission denied for table application_settings' if
            sql.include?('EXISTS')

          table_owner_result if sql.include?('pg_catalog.pg_class')
        end
      end

      it 'aborts pointing at the membership grant, not at the create privileges' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('Cannot read application_settings')
            .and(a_string_including('needs membership in the role that owns the replicated tables'))
            .and(a_string_including('GRANT gitlab TO geo_subscription_owner;'))
            .and(satisfy { |message| message.exclude?('pg_create_subscription') })
          ).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/CREATE SUBSCRIPTION/)
      end

      context 'when the owner cannot be looked up' do
        let(:table_owner_result) { [] }

        it 'falls back to a placeholder rather than losing the privilege error' do
          expect { run_rake_task(task_name) }
            .to raise_error(SystemExit)
            .and output(/GRANT <table owner> TO geo_subscription_owner;/).to_stderr
        end
      end
    end

    context 'when the subscription already exists' do
      before do
        allow(subscriber_connection).to receive(:exec) do |sql|
          raise PG::DuplicateObject, 'already exists' if sql.include?('CREATE SUBSCRIPTION')

          sql.include?('application_settings') ? application_settings_result : schema_migrations_result
        end
      end

      it 'warns that the existing connection info was not verified, without raising' do
        expect { run_rake_task(task_name) }.to output(
          a_string_including("Subscription geo_subscription already exists")
          .and(a_string_including("NOT verified or updated"))
          .and(a_string_including("subscription:drop"))
        ).to_stdout
      end

      it 'does not point at the sequence sync step, since no copy was started' do
        expect { run_rake_task(task_name) }
          .to output(satisfy { |out| out.exclude?('sync_sequences') }).to_stdout
      end
    end

    context 'when the subscriber is unreachable' do
      before do
        allow(PG).to receive(:connect)
          .with(subscriber_connection_string).and_raise(PG::ConnectionBad, 'could not connect to server')
      end

      it 'aborts with the error message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit, /Error creating the subscription: could not connect to server/)
      end
    end

    context 'when the role is not allowed to create a subscription' do
      before do
        allow(subscriber_connection).to receive(:exec) do |sql|
          raise PG::InsufficientPrivilege, 'permission denied to create subscription' if
            sql.include?('CREATE SUBSCRIPTION')

          sql.include?('application_settings') ? application_settings_result : schema_migrations_result
        end
      end

      it 'aborts naming the grants the role is missing' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('GRANT pg_create_subscription TO geo_subscription_owner;')
            .and(a_string_including('GRANT CREATE ON DATABASE gitlabhq_production TO geo_subscription_owner;'))
          ).to_stderr
      end
    end
  end

  describe 'gitlab:geo:logical_replication:subscription:drop' do
    include_context 'with libpq connections'

    let(:task_name) { 'gitlab:geo:logical_replication:subscription:drop' }

    context 'when GEO_SUBSCRIBER_CONNECTION_STRING is unset' do
      let(:subscriber_connection_string) { nil }

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_SUBSCRIBER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when the local database owns the publication' do
      let(:owns_publication_result) { [{ '?column?' => '1' }] }

      it 'aborts and closes the connection' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/owns publication geo_publication/).to_stderr

        expect(subscriber_connection).to have_received(:close)
      end
    end

    context 'when the subscription does not exist' do
      let(:subscription_row) { nil }

      it 'reports the no-op and does not touch the publisher' do
        expect { run_rake_task(task_name) }
          .to output(/Subscription does not exist. Not doing anything/).to_stdout

        expect(PG).not_to have_received(:connect).with(publisher_connection_string)
        expect(subscriber_connection).to have_received(:close)
      end
    end

    context 'when the subscription exists' do
      before do
        stub_env('GEO_PUBLISHER_CONNECTION_STRING', publisher_connection_string)
      end

      it 'disables, detaches the slot, and drops the subscription in order' do
        run_rake_task(task_name)

        expect(subscriber_connection).to have_received(:exec)
          .with('ALTER SUBSCRIPTION "geo_subscription" DISABLE').ordered
        expect(subscriber_connection).to have_received(:exec)
          .with('ALTER SUBSCRIPTION "geo_subscription" SET (slot_name = NONE)').ordered
        expect(subscriber_connection).to have_received(:exec)
          .with('DROP SUBSCRIPTION "geo_subscription"').ordered
        expect(subscriber_connection).to have_received(:close)
      end

      it 'drops the detached replication slot on the publisher' do
        run_rake_task(task_name)

        expect(publisher_connection).to have_received(:exec)
          .with("SELECT pg_drop_replication_slot('geo_subscription')")
      end

      context 'when the initial sync left tablesync slots behind' do
        let(:sync_slots_result) do
          instance_double(PG::Result, values: [['pg_16400_sync_16501_123']])
        end

        it 'drops the stranded tablesync slots too' do
          run_rake_task(task_name)

          expect(publisher_connection).to have_received(:exec_params)
            .with("SELECT slot_name FROM pg_replication_slots WHERE slot_name LIKE $1", ['pg\_16400\_sync\_%'])
          expect(publisher_connection).to have_received(:exec)
            .with("SELECT pg_drop_replication_slot('pg_16400_sync_16501_123')")
        end
      end

      context 'when the slot was already dropped on the publisher' do
        before do
          allow(publisher_connection).to receive(:exec).and_raise(PG::UndefinedObject, 'does not exist')
        end

        it 'reports it and finishes without a warning' do
          expect { run_rake_task(task_name) }.to output(
            /Replication slot geo_subscription does not exist on the publisher/
          ).to_stdout
        end
      end

      context 'when the walsender never releases the slot' do
        before do
          stub_const('Tasks::Gitlab::Geo::LogicalReplication::DROP_SLOT_ATTEMPTS', 1)
          allow(publisher_connection).to receive(:exec).and_raise(PG::ObjectInUse, 'replication slot is active')
        end

        it 'warns with the manual command once the retries are exhausted' do
          expect { run_rake_task(task_name) }.to output(
            a_string_including("could not drop the replication slots on the publisher")
            .and(a_string_including("Run this manually on the publisher"))
          ).to_stdout
        end
      end

      context 'when the publisher is unreachable' do
        before do
          allow(PG).to receive(:connect)
            .with(publisher_connection_string).and_raise(PG::ConnectionBad, 'could not connect to server')
        end

        it 'warns with the manual command instead of failing' do
          expect { run_rake_task(task_name) }.to output(
            a_string_including("could not drop the replication slots on the publisher")
            .and(a_string_including("Run this manually on the publisher"))
            .and(a_string_including("slot_name = 'geo_subscription' OR slot_name LIKE 'pg\\_16400\\_sync\\_%'"))
          ).to_stdout
        end
      end

      context 'when GEO_PUBLISHER_CONNECTION_STRING is unset' do
        before do
          stub_env('GEO_PUBLISHER_CONNECTION_STRING', nil)
        end

        it 'points at the env var and prints the manual command' do
          expect { run_rake_task(task_name) }.to output(
            a_string_including("Set GEO_PUBLISHER_CONNECTION_STRING to drop the replication slots automatically")
            .and(a_string_including("Run this manually on the publisher"))
            .and(a_string_including("slot_name = 'geo_subscription' OR slot_name LIKE 'pg\\_16400\\_sync\\_%'"))
          ).to_stdout

          expect(PG).not_to have_received(:connect).with(publisher_connection_string)
        end
      end
    end

    context 'when retrying after a partial drop left the slot detached' do
      let(:subscription_row) { { 'oid' => '16400', 'subslotname' => nil } }

      before do
        stub_env('GEO_PUBLISHER_CONNECTION_STRING', publisher_connection_string)
      end

      it 'falls back to the subscription name and still drops the publisher slot' do
        run_rake_task(task_name)

        expect(publisher_connection).to have_received(:exec)
          .with("SELECT pg_drop_replication_slot('geo_subscription')")
      end
    end

    context 'when an unexpected database error occurs' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::Error, 'I am a spec error')
      end

      it 'aborts with the error message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit, /Error dropping the subscription: I am a spec error/)
      end
    end
  end

  describe 'gitlab:geo:logical_replication:metadata:seed' do
    include_context 'with libpq connections'

    let(:task_name) { 'gitlab:geo:logical_replication:metadata:seed' }
    let(:subscription_row) { nil }

    before do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', publisher_connection_string)
    end

    it 'reads the publisher in a single repeatable read transaction' do
      run_rake_task(task_name)

      expect(publisher_connection).to have_received(:exec)
        .with('BEGIN ISOLATION LEVEL REPEATABLE READ').ordered
      expect(publisher_connection).to have_received(:exec)
        .with(a_string_including('SELECT version FROM schema_migrations')).ordered
      expect(publisher_connection).to have_received(:exec)
        .with(a_string_including('FROM ar_internal_metadata')).ordered
      expect(publisher_connection).to have_received(:exec).with('COMMIT').ordered
      expect(publisher_connection).to have_received(:close)
    end

    it 'replaces both tables in a single subscriber transaction' do
      run_rake_task(task_name)

      expect(subscriber_connection).to have_received(:exec).with('BEGIN').ordered
      expect(subscriber_connection).to have_received(:exec).with('TRUNCATE "schema_migrations"').ordered
      expect(subscriber_connection).to have_received(:exec).with('TRUNCATE "ar_internal_metadata"').ordered
      expect(subscriber_connection).to have_received(:exec).with('COMMIT').ordered
      expect(subscriber_connection).to have_received(:close)
    end

    it 'inserts the publisher rows through bind parameters' do
      run_rake_task(task_name)

      expect(subscriber_connection).to have_received(:exec_params).with(
        'INSERT INTO "schema_migrations" ("version") VALUES ($1), ($2)',
        %w[20260101000000 20260102000000]
      )
      expect(subscriber_connection).to have_received(:exec_params).with(
        'INSERT INTO "ar_internal_metadata" ("key", "value", "created_at", "updated_at") ' \
          'VALUES ($1, $2, $3, $4)',
        ['environment', 'production', '2026-01-01 00:00:00', '2026-01-01 00:00:00']
      )
    end

    it 'reports the counts and points at the subscription step' do
      expect { run_rake_task(task_name) }.to output(
        a_string_including(
          'Seeded 2 schema_migrations rows (latest 20260102000000) and 1 ar_internal_metadata rows'
        ).and(a_string_including('gitlab:geo:logical_replication:subscription:create'))
      ).to_stdout
    end

    context 'when a version contains a quote' do
      let(:publisher_versions) { ["2026'; DROP TABLE users; --"] }

      it 'passes it as a bind parameter instead of interpolating it' do
        run_rake_task(task_name)

        expect(subscriber_connection).to have_received(:exec_params).with(
          'INSERT INTO "schema_migrations" ("version") VALUES ($1)',
          ["2026'; DROP TABLE users; --"]
        )
        expect(subscriber_connection).not_to have_received(:exec).with(a_string_including('DROP TABLE users'))
      end
    end

    context 'when GEO_SUBSCRIBER_CONNECTION_STRING is unset' do
      let(:subscriber_connection_string) { nil }

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_SUBSCRIBER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when GEO_PUBLISHER_CONNECTION_STRING is unset' do
      before do
        stub_env('GEO_PUBLISHER_CONNECTION_STRING', nil)
      end

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_PUBLISHER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when the local database owns the publication' do
      let(:owns_publication_result) { [{ '?column?' => '1' }] }

      it 'aborts before writing anything' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/owns publication geo_publication/).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/TRUNCATE/)
        expect(subscriber_connection).to have_received(:close)
      end
    end

    context 'when a subscription already exists in this database' do
      let(:subscription_row) { { 'oid' => '16400', 'subslotname' => 'geo_subscription' } }

      it 'refuses and points at the verify task instead' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('Subscription geo_subscription already exists in this database')
            .and(a_string_including('gitlab:geo:logical_replication:metadata:verify'))
          ).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/TRUNCATE/)
        expect(PG).not_to have_received(:connect).with(publisher_connection_string)
      end
    end

    context 'when the schema has not been restored on the subscriber' do
      let(:missing_metadata_tables) { %w[schema_migrations ar_internal_metadata] }

      it 'aborts naming the missing tables and the schema-only dump' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('schema_migrations and ar_internal_metadata does not exist')
            .and(a_string_including('schema-only dump'))
          ).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/TRUNCATE/)
        expect(PG).not_to have_received(:connect).with(publisher_connection_string)
      end
    end

    context 'when application_settings already has rows' do
      let(:application_settings_result) { [{ 'present' => 't' }] }

      it 'refuses to overwrite what looks like a live database' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/application_settings already contains rows/).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/TRUNCATE/)
        expect(PG).not_to have_received(:connect).with(publisher_connection_string)
      end
    end

    context 'when the publisher role cannot read the metadata tables' do
      before do
        allow(publisher_connection).to receive(:exec) do |sql|
          raise PG::InsufficientPrivilege, 'permission denied for table schema_migrations' if
            sql.include?('SELECT version')
        end
      end

      it 'aborts naming the explicit SELECT grant' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('not part of the publication')
            .and(a_string_including('GRANT SELECT ON schema_migrations, ar_internal_metadata TO gitlab_replicator;'))
          ).to_stderr

        expect(subscriber_connection).not_to have_received(:exec).with(/TRUNCATE/)
        expect(publisher_connection).to have_received(:close)
      end
    end

    context 'when the subscriber role cannot write the metadata tables' do
      let(:table_owner_result) { [{ 'owner' => 'gitlab' }] }

      before do
        allow(subscriber_connection).to receive(:exec) do |sql|
          raise PG::InsufficientPrivilege, 'permission denied for table schema_migrations' if sql.include?('TRUNCATE')

          if sql.include?('pg_catalog.pg_class')
            table_owner_result
          elsif sql.include?('application_settings')
            application_settings_result
          end
        end
      end

      it 'aborts naming the membership grant rather than a SELECT grant' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('Cannot write the replication metadata on the subscriber')
            .and(a_string_including('GRANT gitlab TO geo_subscription_owner;'))
            .and(satisfy { |message| message.exclude?('GRANT SELECT') })
          ).to_stderr

        expect(subscriber_connection).to have_received(:close)
      end

      it 'rolls the failed transaction back before looking the table owner up' do
        expect { run_rake_task(task_name) }.to raise_error(SystemExit)

        expect(subscriber_connection).to have_received(:exec).with(/TRUNCATE/).ordered
        expect(subscriber_connection).to have_received(:exec).with('ROLLBACK').ordered
        expect(subscriber_connection).to have_received(:exec).with(/pg_catalog\.pg_class/).ordered
      end
    end

    context 'when an unexpected database error occurs' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::Error, 'I am a spec error')
      end

      it 'aborts with the error message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit, /Error seeding the replication metadata: I am a spec error/)
      end
    end
  end

  describe 'gitlab:geo:logical_replication:metadata:verify' do
    include_context 'with libpq connections'

    let(:task_name) { 'gitlab:geo:logical_replication:metadata:verify' }

    before do
      stub_env('GEO_PUBLISHER_CONNECTION_STRING', publisher_connection_string)
    end

    it 'reports the match and closes both connections' do
      expect { run_rake_task(task_name) }
        .to output(/schema_migrations match: 2 versions, latest 20260102000000/).to_stdout

      expect(publisher_connection).to have_received(:close)
      expect(subscriber_connection).to have_received(:close)
    end

    it 'does not write to either side' do
      run_rake_task(task_name)

      expect(subscriber_connection).not_to have_received(:exec).with(/TRUNCATE/)
    end

    context 'when the publisher is ahead of the subscriber' do
      let(:subscriber_versions) { %w[20260101000000] }

      context 'when there is no subscription yet' do
        let(:subscription_row) { nil }

        it 'aborts listing the missing versions and the seed remediation' do
          expect { run_rake_task(task_name) }
            .to raise_error(SystemExit)
            .and output(
              a_string_including('Missing on the subscriber (1): 20260102000000')
              .and(a_string_including('gitlab:geo:logical_replication:metadata:seed'))
              .and(a_string_including('db:migrate'))
            ).to_stderr
        end
      end

      context 'when an enabled subscription exists' do
        it 'aborts telling the operator to migrate the subscriber' do
          expect { run_rake_task(task_name) }
            .to raise_error(SystemExit)
            .and output(
              a_string_including('Missing on the subscriber (1): 20260102000000')
              .and(a_string_including('The publisher is ahead'))
              .and(a_string_including('replication stalls'))
              .and(a_string_including('db:migrate on the subscriber'))
              .and(a_string_including('gitlab:geo:logical_replication:subscription:refresh'))
              .and(satisfy { |message| message.exclude?('metadata:seed') })
            ).to_stderr
        end
      end

      context 'when the subscription is disabled' do
        let(:subscription_row) do
          { 'oid' => '16400', 'subslotname' => 'geo_subscription', 'subenabled' => 'f' }
        end

        it 'aborts reporting replication as paused and enabling before refreshing' do
          expect { run_rake_task(task_name) }
            .to raise_error(SystemExit)
            .and output(
              a_string_including('The publisher is ahead')
              .and(a_string_including('replication is paused'))
              .and(satisfy { |message| message.exclude?('stalls') })
              .and(satisfy do |message|
                message.index('subscription:enable') < message.index('subscription:refresh')
              end)
            ).to_stderr
        end
      end
    end

    context 'when the subscriber has versions the publisher does not' do
      let(:subscriber_versions) { publisher_versions + %w[20260103000000] }

      context 'when there is no subscription yet' do
        let(:subscription_row) { nil }

        it 'aborts describing the rows as stale' do
          expect { run_rake_task(task_name) }
            .to raise_error(SystemExit)
            .and output(
              a_string_including('Extra on the subscriber (1): 20260103000000')
              .and(a_string_including('stale'))
            ).to_stderr
        end
      end

      context 'when a subscription exists' do
        it 'aborts telling the operator to migrate the publisher' do
          expect { run_rake_task(task_name) }
            .to raise_error(SystemExit)
            .and output(
              a_string_including('Extra on the subscriber (1): 20260103000000')
              .and(a_string_including('The subscriber is ahead'))
              .and(a_string_including('db:migrate on the publisher'))
              .and(satisfy { |message| message.exclude?('metadata:seed') })
            ).to_stderr
        end
      end
    end

    context 'when both sides have versions the other lacks' do
      let(:subscriber_versions) { %w[20260101000000 20260103000000] }

      it 'aborts reporting both lists' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('Missing on the subscriber (1): 20260102000000')
            .and(a_string_including('Extra on the subscriber (1): 20260103000000'))
          ).to_stderr
      end
    end

    context 'when more versions are missing than the list shows' do
      let(:publisher_versions) { (1..25).map { |index| format('202601%<index>02d000000', index: index) } }
      let(:subscriber_versions) { [] }

      it 'caps the list and reports the total' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('Missing on the subscriber (25, first 20 shown)')
            .and(a_string_including('20260101000000'))
            .and(satisfy { |message| message.exclude?('20260121000000') })
          ).to_stderr
      end
    end

    context 'when the ar_internal_metadata environments differ' do
      let(:subscriber_environment) { 'development' }

      it 'aborts reporting both environments' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(
            a_string_including('ar_internal_metadata environment differs')
            .and(a_string_including('publisher "production"'))
            .and(a_string_including('subscriber "development"'))
          ).to_stderr
      end
    end

    context 'when GEO_SUBSCRIBER_CONNECTION_STRING is unset' do
      let(:subscriber_connection_string) { nil }

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_SUBSCRIBER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when GEO_PUBLISHER_CONNECTION_STRING is unset' do
      before do
        stub_env('GEO_PUBLISHER_CONNECTION_STRING', nil)
      end

      it 'aborts without connecting' do
        expect(PG).not_to receive(:connect)

        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/GEO_PUBLISHER_CONNECTION_STRING must be set/).to_stderr
      end
    end

    context 'when schema_migrations does not exist on the publisher' do
      before do
        allow(publisher_connection).to receive(:exec).and_raise(PG::UndefinedTable, 'does not exist')
      end

      it 'names the publisher as the side without the table' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/does not exist on the publisher/).to_stderr
      end
    end

    context 'when schema_migrations does not exist on the subscriber' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::UndefinedTable, 'does not exist')
      end

      it 'names the subscriber as the side without the table' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit)
          .and output(/does not exist on the subscriber/).to_stderr
      end
    end

    context 'when an unexpected database error occurs' do
      before do
        allow(subscriber_connection).to receive(:exec).and_raise(PG::Error, 'I am a spec error')
      end

      it 'aborts with the error message' do
        expect { run_rake_task(task_name) }
          .to raise_error(SystemExit, /Error verifying the replication metadata: I am a spec error/)
      end
    end
  end
end
