# frozen_string_literal: true

module Tasks
  module Gitlab
    module Geo
      module LogicalReplication
        # Operational contract for the subscription tasks.
        #
        # The subscription tasks talk to PostgreSQL over libpq instead of Rails, because they run
        # against a subscriber whose schema has only been seeded: booting Rails there would write
        # rows (for example application_settings) that collide with the initial table copy, and the
        # application role is not privileged enough to create a subscription anyway.
        #
        # GEO_PUBLISHER_CONNECTION_STRING is the primary's `gitlab_replicator` role (the one
        # documented for streaming replication: REPLICATION attribute plus read access to the
        # published tables). It is embedded in CREATE SUBSCRIPTION and reused to drop the leftover
        # replication slots on the publisher during subscription:drop.
        #
        # preflight:write_activity and set_secondary_as_primary both read it to check that the
        # publisher is not being written to. That check needs one more grant than the rest:
        #   GRANT pg_read_all_stats TO gitlab_replicator;
        # pg_read_all_data does not cover pg_stat_activity, and without it the check aborts rather
        # than report a publisher it cannot see into as write-free.
        #
        # GEO_SUBSCRIBER_CONNECTION_STRING is a privileged role on the subscriber. That role owns
        # the subscription and needs three things:
        #
        #   1. pg_create_subscription, plus CREATE on the database.
        #   2. A password in GEO_PUBLISHER_CONNECTION_STRING (PostgreSQL requires one when the
        #      subscription owner is not a superuser).
        #   3. Membership in the role that owns the replicated tables:
        #        GRANT gitlab TO geo_subscription_owner;
        #
        # (3) is the one people miss. Before writing to a table, the replication workers switch to
        # that table's owner with SET ROLE, which only membership allows; pg_read_all_data and
        # pg_write_all_data grant the reads and writes but not the role switch, so they are not a
        # substitute. The same membership satisfies the precondition read in subscription:create.
        #
        # Without it, every worker fails with `role "X" cannot SET ROLE to "Y"` after it has already
        # created a replication slot and origin for its table. Those pile up, one per table, until
        # the subscriber reports "could not find free replication state slot for replication
        # origin". That error suggests raising max_replication_slots; don't, it's a symptom. Grant
        # the membership, then drop and recreate the subscription, which cleans up the leftovers.
        #
        # DDL is not replicated, so partitions the publisher creates after the schema seed do not
        # exist on the subscriber. subscription:refresh fails on them until they are created
        # locally (matching bounds AND the same owner, or the workers die on SET ROLE).
        #
        # The initial copy carries no sequence values, so subscriber sequences remain at their start
        # values and local writes before promotion can hit duplicate-key errors. The sync_sequences
        # task fixes that and is safe to run while the subscription is active, because logical
        # replication does not replicate sequence state.
        #
        # Promotion runs the write activity check before this sync, because a write landing on the
        # publisher between the sync and the cutover is never replicated and collides on the promoted
        # site. An unreachable publisher is not an error there: a DR failover must never be blocked.
        #
        # Seeding order for the initial sync. schema_migrations and ar_internal_metadata are in
        # EXCLUDED_TABLES, so neither the initial copy nor the ongoing delta carries their rows, and
        # a schema-only dump carries their definition but not their contents. Without those rows
        # Rails reports every migration as pending and the application does not boot:
        #
        #   1. Restore pg_dump --schema-only --no-publications --no-subscriptions from the primary.
        #   2. Run metadata:seed right away. Steps 1 and 2 are not one snapshot, so no migration may
        #      run on the publisher in between; metadata:verify catches drift afterwards.
        #   3. publication:set_tables on the primary, then subscription:create.
        #   4. Once every pg_subscription_rel row reports srsubstate = 'r', run metadata:verify and
        #      then sync_sequences.
        #   5. metadata:verify can also run right after step 2, and a failure there is fixed by
        #      re-taking the dump and re-seeding. After step 3 a subscription exists and metadata:seed
        #      refuses to run, so a failure in step 4 is fixed by running the missing migrations on
        #      the subscriber instead. The pair is past seeding then, and the rules below apply.
        #
        # detached_partitions is excluded like the other two but is never seeded: it is per-instance
        # partition-manager bookkeeping with locally allocated ids, so the subscriber owns its rows.
        #
        # Excluded tables. EXCLUDED_TABLES holds three kinds of table, all written independently
        # on each side: schema and partition bookkeeping (seeded from the publisher, or owned per
        # site); batched background migration state, where the transition logs have a foreign key
        # to the jobs and so have to leave with them; and the trackers that migrations and the
        # reindexing cron write for asynchronous DDL and reindexing. Publishing any of them makes
        # both sides insert the same ids, and the apply worker then stalls on duplicate keys. A
        # partitioned table is excluded through its parent, which un-publishes every one of its
        # partitions; set_tables also removes partitions that other tooling published one by one.
        #
        # An existing pair adopts a change to the list with publication:set_tables on the primary,
        # which drops the tables that are now excluded, followed by subscription:refresh on the
        # subscriber. Rows the initial copy already brought over stay: they describe migrations that
        # ran against the replicated data. From then on each site owns those tables.
        #
        # Upgrading an LR pair. DDL is not replicated, so the subscriber runs the migrations itself:
        # the publisher goes first, the subscriber catches up, replication paused in between.
        #
        #   1. subscription:disable on the subscriber.
        #   2. db:migrate on the publisher, post-deploy migrations included.
        #   3. db:migrate on the subscriber the same way, as a privileged role: migrations write
        #      DDL, which the read-only application role cannot. On an LR secondary db:migrate
        #      syncs the sequences first, so the migrations do not collide with the replicated
        #      ids. That gate reads the feature flag, so the flag has to be visible here already.
        #   4. publication:set_tables on the publisher, so tables the upgrade added are published
        #      and tables that are now excluded are dropped. See "Excluded tables" above.
        #   5. metadata:verify. It has to report a match before replication resumes.
        #   6. subscription:enable, then subscription:refresh. Refreshing earlier fails with "ALTER
        #      SUBSCRIPTION ... REFRESH is not allowed for disabled subscriptions"; tables added in
        #      step 4 only replicate after it, and new partitions must exist locally first, as
        #      above.
        #
        # Skipping the pause is not destructive. The apply worker fails with "logical replication
        # target relation ... is missing replicated column" and retries until the subscriber
        # migrates, while the slot retains the WAL. The pause only avoids that error loop.
        #
        # When the two sides drift, metadata:verify names the side that is behind; migrate it. A
        # migration that ran only on the subscriber cannot be undone, so bring the publisher up to
        # it instead. Never run metadata:seed once a subscription exists. On the secondary,
        # gitlab:geo:check reports migrations that are still pending.

        # Grouped as the "Excluded tables" note above describes: schema and partition bookkeeping,
        # batched background migration state, asynchronous DDL trackers, reindexing bookkeeping.
        EXCLUDED_TABLES = %w[
          ar_internal_metadata
          detached_partitions
          schema_migrations

          batched_background_migration_job_transition_logs
          batched_background_migration_jobs
          batched_background_migrations

          postgres_async_foreign_key_validations
          postgres_async_indexes

          postgres_reindex_actions
          postgres_reindex_queued_actions
        ].freeze

        # Copied from the publisher instead, since the subscriber cannot boot without them.
        SEEDED_METADATA_TABLES = %w[
          schema_migrations
          ar_internal_metadata
        ].freeze

        DROP_SLOT_ATTEMPTS = 5

        METADATA_INSERT_BATCH_SIZE = 1_000

        METADATA_MISMATCH_LIST_LIMIT = 20

        def publication_name
          ENV.fetch("GEO_PUBLICATION", "geo_publication")
        end

        def subscription_name
          ENV.fetch("GEO_SUBSCRIPTION", "geo_subscription")
        end

        def db_connection
          ApplicationRecord.connection
        end

        def excluded_tables
          EXCLUDED_TABLES
        end

        # Keyed by relname, because db_connection.tables yields bare names. GitLab partitions are
        # one level deep today, but the recursion resolves to the root regardless.
        def partition_roots
          db_connection.execute(<<~SQL.squish).values.to_h
            WITH RECURSIVE ancestors AS (
              SELECT inhrelid AS partition_id, inhparent AS ancestor_id
              FROM pg_catalog.pg_inherits
              UNION ALL
              SELECT a.partition_id, i.inhparent
              FROM ancestors a
              JOIN pg_catalog.pg_inherits i ON i.inhrelid = a.ancestor_id
            )
            SELECT leaf.relname, root.relname
            FROM ancestors a
            JOIN pg_catalog.pg_class leaf ON leaf.oid = a.partition_id
            JOIN pg_catalog.pg_class root ON root.oid = a.ancestor_id
            WHERE NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid = a.ancestor_id
            )
          SQL
        end

        # Callers pass partition_roots in so the lookup is built once, not once per table.
        def excluded_table?(table, partition_roots)
          excluded_tables.include?(table) || excluded_tables.include?(partition_roots[table])
        end

        # Returns relname => schema for the relations registered to the publication. Partitions
        # live outside the search path, so removing one needs its schema.
        def publication_tables(publication)
          return {} if publication.empty?

          db_connection.execute(<<~SQL.squish).values.to_h
            SELECT c.relname, n.nspname
            FROM pg_publication p
            JOIN pg_publication_rel pr ON pr.prpubid = p.oid
            JOIN pg_class c ON c.oid = pr.prrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE p.pubname IN (#{db_connection.quote(publication)})
          SQL
        end

        def alter_publication(action, table)
          raise ArgumentError, "action must be ADD or DROP" unless %w[ADD DROP].include?(action)

          db_connection.execute(
            "ALTER PUBLICATION #{publication_name} #{action} TABLE #{db_connection.quote_table_name(table)}"
          )
        end

        def publisher_connection_string
          ENV["GEO_PUBLISHER_CONNECTION_STRING"]
        end

        def subscriber_connection_string
          ENV["GEO_SUBSCRIBER_CONNECTION_STRING"]
        end

        def copy_data?
          ENV["GEO_SUBSCRIPTION_COPY_DATA"] != "false"
        end

        def with_subscriber_connection
          connection = PG.connect(subscriber_connection_string)

          yield connection
        ensure
          connection&.close
        end

        def with_publisher_connection
          connection = PG.connect(publisher_connection_string)

          yield connection
        ensure
          connection&.close
        end

        # subname is only unique per (subdbid, subname) and pg_subscription is cluster-wide,
        # so scope to the current database to avoid matching another database's subscription.
        def current_database_subscription(connection)
          connection.exec_params(<<~SQL.squish, [subscription_name]).first
            SELECT s.oid, s.subslotname, s.subenabled
            FROM pg_catalog.pg_subscription s
            JOIN pg_catalog.pg_database d ON d.oid = s.subdbid
            WHERE d.datname = current_database()
            AND s.subname = $1
          SQL
        end

        # The publisher and the subscriber must never be the same database: replicating a
        # publication into the database that owns it would feed the primary its own writes.
        def local_database_owns_publication?(connection)
          connection.exec_params(
            "SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = $1", [publication_name]
          ).any?
        end

        # Raises PG::UndefinedTable when the schema has not been seeded yet; callers turn that
        # into an actionable message rather than treating it as an empty table.
        def application_settings_present?(connection)
          connection.exec("SELECT EXISTS (SELECT 1 FROM application_settings) AS present")
            .first["present"] == "t"
        end

        def schema_migrations_present?(connection)
          connection.exec("SELECT EXISTS (SELECT 1 FROM schema_migrations) AS present")
            .first["present"] == "t"
        end

        # to_regclass resolves through search_path, like the unqualified TRUNCATE and INSERT that
        # follow, so a schema that was never restored aborts before the write transaction starts.
        def missing_seeded_metadata_tables(connection)
          connection.exec_params(
            "SELECT name FROM unnest($1::text[]) AS name WHERE to_regclass(name) IS NULL",
            ["{#{SEEDED_METADATA_TABLES.join(',')}}"]
          ).values.flatten
        end

        def schema_migrations_versions(connection)
          connection.exec("SELECT version FROM schema_migrations ORDER BY version").values.flatten
        end

        def ar_internal_metadata_environment(connection)
          connection.exec_params(
            "SELECT value FROM ar_internal_metadata WHERE key = $1", ["environment"]
          ).first&.dig("value")
        end

        def metadata_state(connection)
          {
            versions: schema_migrations_versions(connection),
            environment: ar_internal_metadata_environment(connection)
          }
        end

        # One transaction so both tables come from the same publisher snapshot.
        def read_publisher_metadata(connection)
          connection.exec("BEGIN ISOLATION LEVEL REPEATABLE READ")

          versions = schema_migrations_versions(connection)
          metadata_rows = connection.exec(
            "SELECT key, value, created_at, updated_at FROM ar_internal_metadata ORDER BY key"
          ).values

          connection.exec("COMMIT")

          { versions: versions, metadata_rows: metadata_rows }
        end

        # TRUNCATE and re-insert rather than upsert, so a re-run converges exactly on the publisher
        # and leaves no stale versions behind.
        def write_subscriber_metadata(connection, versions:, metadata_rows:)
          connection.exec("BEGIN")

          SEEDED_METADATA_TABLES.each do |table|
            connection.exec("TRUNCATE #{connection.quote_ident(table)}")
          end

          insert_metadata_rows(connection, "schema_migrations", %w[version], versions.map { |v| [v] })
          insert_metadata_rows(
            connection, "ar_internal_metadata", %w[key value created_at updated_at], metadata_rows
          )

          connection.exec("COMMIT")
        rescue PG::Error
          rollback_quietly(connection)
          raise
        end

        # A failed statement leaves the connection in an aborted transaction, where every later query
        # fails with PG::InFailedSqlTransaction, including the table-owner lookup in the error message.
        def rollback_quietly(connection)
          connection.exec("ROLLBACK")
        rescue PG::Error
          nil
        end

        def insert_metadata_rows(connection, table, columns, rows)
          return if rows.empty?

          column_list = columns.map { |column| connection.quote_ident(column) }.join(", ")

          rows.each_slice(METADATA_INSERT_BATCH_SIZE) do |batch|
            placeholders = batch.each_index.map do |row|
              binds = columns.each_index.map { |column| "$#{(row * columns.size) + column + 1}" }

              "(#{binds.join(', ')})"
            end

            connection.exec_params(
              "INSERT INTO #{connection.quote_ident(table)} (#{column_list}) VALUES #{placeholders.join(', ')}",
              batch.flatten
            )
          end
        end

        # The slots live on the publisher, outside this connection, so it needs its own
        # libpq connection.
        def drop_publisher_replication_slots(slot_name, sync_slot_pattern)
          publisher_connection = PG.connect(publisher_connection_string)

          sync_slots = publisher_connection.exec_params(
            "SELECT slot_name FROM pg_replication_slots WHERE slot_name LIKE $1", [sync_slot_pattern]
          ).values.flatten

          ([slot_name] + sync_slots).uniq.each do |slot|
            drop_replication_slot(publisher_connection, slot)
          end
        ensure
          publisher_connection&.close
        end

        def drop_replication_slot(connection, slot)
          attempts = 0

          begin
            connection.exec("SELECT pg_drop_replication_slot(#{connection.escape_literal(slot)})")
            puts "Dropped replication slot #{slot} on the publisher"
          rescue PG::UndefinedObject
            puts "Replication slot #{slot} does not exist on the publisher. Nothing to drop"
          rescue PG::ObjectInUse
            # The walsender can take a moment to release the slot after
            # ALTER SUBSCRIPTION ... DISABLE, so give it a few chances.
            attempts += 1
            raise unless attempts < DROP_SLOT_ATTEMPTS

            sleep 1
            retry
          end
        end

        # An orphaned slot causes unbounded WAL retention on the publisher, so always
        # hand the operator the cleanup SQL when we could not drop the slots ourselves.
        def manual_slot_cleanup_message(slot_name, sync_slot_pattern)
          <<~MSG
            Run this manually on the publisher:
              SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots
              WHERE slot_name = '#{slot_name}' OR slot_name LIKE '#{sync_slot_pattern}';
          MSG
        end

        def publisher_connection_string_message
          "GEO_PUBLISHER_CONNECTION_STRING must be set to a libpq connection string for the " \
            "replication role on the publisher database (the Geo primary)."
        end

        def subscriber_connection_string_message(create: false)
          message = "GEO_SUBSCRIBER_CONNECTION_STRING must be set to a libpq connection string for a " \
            "privileged role on the subscriber database."

          return message unless create

          "#{message} The role has to hold pg_create_subscription and " \
            "CREATE on the database."
        end

        def subscription_created_message
          <<~MSG.chomp
            The subscription #{subscription_name} was created and the initial table copy is starting.
            The copy does not carry sequence values, so subscriber sequences remain at their start values.
            Once all rows in pg_subscription_rel report srsubstate = 'r', run:
              bundle exec rake gitlab:geo:logical_replication:sync_sequences
            to advance the local sequences past the copied data.
          MSG
        end

        def subscription_disabled_message
          <<~MSG.chomp
            Subscription #{subscription_name} disabled. Replication is paused and the publisher
            retains WAL until it is enabled again. To upgrade the pair from here:
              1. db:migrate on the publisher, post-deploy migrations included.
              2. db:migrate on the subscriber the same way, as a privileged role.
              3. bundle exec rake gitlab:geo:logical_replication:publication:set_tables (publisher)
              4. bundle exec rake gitlab:geo:logical_replication:metadata:verify
              5. bundle exec rake gitlab:geo:logical_replication:subscription:enable
              6. bundle exec rake gitlab:geo:logical_replication:subscription:refresh
          MSG
        end

        def subscription_enabled_message
          <<~MSG.chomp
            Subscription #{subscription_name} enabled. Replication resumes from the WAL the publisher
            retained while it was paused. If the publication gained tables in the meantime, run:
              bundle exec rake gitlab:geo:logical_replication:subscription:refresh
          MSG
        end

        def subscription_already_disabled_message
          "Subscription #{subscription_name} is already disabled. Not doing anything"
        end

        def subscription_already_enabled_message
          "Subscription #{subscription_name} is already enabled. Not doing anything"
        end

        def subscription_missing_message
          "Subscription #{subscription_name} does not exist"
        end

        def publisher_target_message
          <<~MSG.chomp
            This database owns publication #{publication_name}, so GEO_SUBSCRIBER_CONNECTION_STRING points at
            the publisher (the Geo primary) rather than the subscriber. Refusing to proceed.
          MSG
        end

        def seeded_database_message
          <<~MSG.chomp
            application_settings already contains rows, so this is not an empty subscriber and the initial
            table copy would conflict with them. Either:

              - GEO_SUBSCRIBER_CONNECTION_STRING points at a live GitLab database instead of the freshly
                seeded subscriber, so point it at the right database; or
              - Rails booted against this subscriber before the subscription existed and wrote the initial
                rows (see https://gitlab.com/gitlab-org/gitlab/-/work_items/621882). If you are certain this
                is the fresh subscriber, clear them with `DELETE FROM application_settings;` and re-run.
          MSG
        end

        def unseeded_database_message(tables = "application_settings")
          <<~MSG.chomp
            #{tables} does not exist, so the schema has not been seeded on this database yet.
            Restore the schema-only dump from the primary before creating the subscription.
          MSG
        end

        def unreadable_application_settings_message(connection, error)
          <<~MSG.chomp
            Cannot read application_settings to check that this database is an empty subscriber:
            #{error.message.strip}
            Role #{connection.user} needs membership in the role that owns the replicated tables.
            PostgreSQL runs the apply workers as the table owner, so they need that same membership
            to SET ROLE:
              GRANT #{replicated_table_owner(connection)} TO #{connection.user};
          MSG
        end

        # Names the owner concretely so the grant can be copy-pasted. pg_class is world-readable,
        # but this is only a hint: a failed lookup must never mask the privilege error being reported.
        def replicated_table_owner(connection, table = "application_settings")
          owner = connection.exec(<<~SQL.squish).first&.dig("owner")
            SELECT relowner::regrole::text AS owner
            FROM pg_catalog.pg_class
            WHERE oid = to_regclass(#{connection.escape_literal(table)})
          SQL

          owner.presence || "<table owner>"
        rescue PG::Error
          "<table owner>"
        end

        def create_privileges_message(connection, error)
          <<~MSG.chomp
            Not allowed to create the subscription (#{error.message.strip}).
            Role #{connection.user} needs the following grants:
              GRANT pg_create_subscription TO #{connection.user};
              GRANT CREATE ON DATABASE #{connection.db} TO #{connection.user};
          MSG
        end

        def unseeded_metadata_message
          <<~MSG.chomp
            schema_migrations is empty on this database, so Rails would report every migration as
            pending and the application would not boot. Seed it from the publisher first:
              bundle exec rake gitlab:geo:logical_replication:metadata:seed
          MSG
        end

        def unseeded_metadata_tables_message(missing_tables)
          unseeded_database_message(missing_tables.join(" and "))
        end

        def metadata_seed_subscription_exists_message
          <<~MSG.chomp
            Subscription #{subscription_name} already exists in this database, and seeding is a
            pre-subscription step: once the subscription is live the subscriber owns its own migration
            state, so overwriting schema_migrations here would be destructive. To compare the two
            sides instead, run:
              bundle exec rake gitlab:geo:logical_replication:metadata:verify
          MSG
        end

        def unreadable_publisher_metadata_message(connection, error)
          <<~MSG.chomp
            Cannot read the replication metadata on the publisher:
            #{error.message.strip}
            schema_migrations and ar_internal_metadata are not part of the publication, so read access
            to the published tables does not cover them. Grant it explicitly:
              GRANT SELECT ON schema_migrations, ar_internal_metadata TO #{connection.user};
          MSG
        end

        def unwritable_metadata_message(connection, error)
          <<~MSG.chomp
            Cannot write the replication metadata on the subscriber:
            #{error.message.strip}
            Role #{connection.user} needs membership in the role that owns the replicated tables:
              GRANT #{replicated_table_owner(connection, 'schema_migrations')} TO #{connection.user};
          MSG
        end

        def metadata_seeded_message(versions, metadata_rows)
          counts = "Seeded #{versions.size} schema_migrations rows (latest #{versions.max}) and " \
            "#{metadata_rows.size} ar_internal_metadata rows from the publisher."

          <<~MSG.chomp
            #{counts}
            The seed reflects the publisher state right now, so it only matches the schema-only dump
            when no migration ran on the publisher in between. Next:
              bundle exec rake gitlab:geo:logical_replication:subscription:create
          MSG
        end

        def schema_migrations_match_message(versions)
          "schema_migrations match: #{versions.size} versions, latest #{versions.max}"
        end

        # A mismatch means something different before and after the subscription exists: seeding
        # drift beforehand, a half-finished upgrade afterwards.
        def schema_migrations_mismatch_message(
          missing_on_subscriber, extra_on_subscriber, subscription_present:, subscription_enabled:
        )
          parts = ["schema_migrations differ between the publisher and the subscriber."]

          if missing_on_subscriber.any?
            parts << version_list_message("Missing on the subscriber", missing_on_subscriber)
            parts << (
              subscription_present ? publisher_ahead_message(subscription_enabled) : unseeded_versions_message
            )
          end

          if extra_on_subscriber.any?
            parts << version_list_message("Extra on the subscriber", extra_on_subscriber)
            parts << (subscription_present ? subscriber_ahead_message : stale_versions_message)
          end

          parts.join("\n")
        end

        def unseeded_versions_message
          <<~MSG.chomp
            A migration landed on the publisher after the seed. While there is no subscription yet,
            re-take the schema-only dump and re-run:
              bundle exec rake gitlab:geo:logical_replication:metadata:seed
            Once the subscription exists, run the missing migrations on the subscriber with
            db:migrate instead, so its schema matches its schema_migrations.
          MSG
        end

        def stale_versions_message
          <<~MSG.chomp
            These rows are stale: the seed came from a later publisher state than the schema dump.
            Re-take the schema-only dump and re-run:
              bundle exec rake gitlab:geo:logical_replication:metadata:seed
          MSG
        end

        # The next steps depend on the subscription state: PostgreSQL refuses to refresh a disabled
        # subscription, so the paused path has to enable it before refreshing.
        def publisher_ahead_message(subscription_enabled)
          if subscription_enabled
            <<~MSG.chomp
              The publisher is ahead. The subscription is enabled, so replication stalls on the new schema
              until the subscriber catches up. Run db:migrate on the subscriber, post-deploy migrations
              included, and then:
                bundle exec rake gitlab:geo:logical_replication:publication:set_tables (publisher)
                bundle exec rake gitlab:geo:logical_replication:subscription:refresh
            MSG
          else
            <<~MSG.chomp
              The publisher is ahead. The subscription is disabled, so replication is paused and resumes
              once the pair is upgraded. Remaining steps:
                1. db:migrate on the subscriber, post-deploy migrations included, as a privileged role.
                2. bundle exec rake gitlab:geo:logical_replication:publication:set_tables (publisher)
                3. bundle exec rake gitlab:geo:logical_replication:metadata:verify
                4. bundle exec rake gitlab:geo:logical_replication:subscription:enable
                5. bundle exec rake gitlab:geo:logical_replication:subscription:refresh
              Refresh comes after enable: PostgreSQL refuses to refresh a disabled subscription.
            MSG
          end
        end

        def subscriber_ahead_message
          <<~MSG.chomp
            The subscriber is ahead. Under the publisher-first rule that means the publisher has not
            finished migrating, or a migration ran only here. Run db:migrate on the publisher. Do not
            re-seed the metadata while a subscription exists.
          MSG
        end

        def version_list_message(label, versions)
          shown = versions.first(METADATA_MISMATCH_LIST_LIMIT)
          count = versions.size > shown.size ? "#{versions.size}, first #{shown.size} shown" : versions.size.to_s

          "#{label} (#{count}): #{shown.join(', ')}"
        end

        def environment_mismatch_message(publisher_environment, subscriber_environment)
          <<~MSG.chomp
            ar_internal_metadata environment differs: publisher #{publisher_environment.inspect},
            subscriber #{subscriber_environment.inspect}. Re-seed the metadata so the subscriber
            matches the publisher:
              bundle exec rake gitlab:geo:logical_replication:metadata:seed
          MSG
        end

        def missing_metadata_table_message(side)
          <<~MSG.chomp
            schema_migrations or ar_internal_metadata does not exist on the #{side}, so its schema is
            not in place. Check that GEO_PUBLISHER_CONNECTION_STRING and
            GEO_SUBSCRIBER_CONNECTION_STRING point at GitLab databases, and that the schema-only dump
            has been restored on the subscriber.
          MSG
        end
      end
    end
  end
end
