# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Geo::PublisherWriteActivityCheck, feature_category: :geo_replication do
  let(:connection_string) { 'postgresql://publisher/gitlabhq_production' }
  let(:connection) { instance_double(PG::Connection, user: 'gitlab_replicator', close: true) }
  let(:in_recovery) { 'f' }
  let(:publication_exists) { 't' }
  let(:masked_sessions) { '0' }
  let(:sessions) { [] }
  let(:maintenance_mode) { 't' }

  let(:writer_session) do
    {
      'pid' => '123', 'usename' => 'gitlab', 'application_name' => 'rails',
      'state' => 'active', 'holds_write_transaction' => 't',
      'transaction_age_seconds' => '5', 'query' => 'INSERT INTO projects...'
    }
  end

  subject(:check) { described_class.new(connection_string: connection_string, connect_retry_interval: 0) }

  before do
    allow(PG).to receive(:connect).and_return(connection)
    allow(connection).to receive(:exec_params).with(described_class::TARGET_SQL, anything).and_return(
      instance_double(PG::Result, first: { 'in_recovery' => in_recovery, 'publication_exists' => publication_exists })
    )
    allow(connection).to receive(:exec) do |sql|
      if sql.include?('masked_sessions')
        instance_double(PG::Result, first: { 'masked_sessions' => masked_sessions })
      elsif sql.include?('pg_stat_activity')
        instance_double(PG::Result, to_a: sessions)
      elsif sql.include?('maintenance_mode')
        instance_double(PG::Result, first: { 'maintenance_mode' => maintenance_mode })
      end
    end
  end

  describe '#execute' do
    it 'connects with the configured timeout, application name and keepalives' do
      check.execute

      expect(PG).to have_received(:connect).with(
        connection_string,
        connect_timeout: described_class::CONNECT_TIMEOUT_SECONDS,
        application_name: described_class::APPLICATION_NAME,
        **described_class::KEEPALIVE_OPTIONS
      )
    end

    it 'scopes the statement timeout to one transaction and rolls it back before closing' do
      check.execute

      expect(connection).to have_received(:exec).with('BEGIN').ordered
      expect(connection).to have_received(:exec)
        .with("SET LOCAL statement_timeout = #{described_class::STATEMENT_TIMEOUT_MS}").ordered
      expect(connection).to have_received(:exec).with('ROLLBACK').ordered
      expect(connection).to have_received(:close).ordered
    end

    it 'applies custom connect and statement timeouts' do
      described_class.new(
        connection_string: connection_string, connect_timeout: 2, statement_timeout_ms: 500
      ).execute

      expect(PG).to have_received(:connect).with(
        connection_string, hash_including(connect_timeout: 2)
      )
      expect(connection).to have_received(:exec).with('SET LOCAL statement_timeout = 500')
    end

    context 'when the publisher has no active sessions' do
      it 'reports no writes and does not block' do
        result = check.execute

        expect(result.status).to eq(:no_writes)
        expect(result).not_to be_blocking
      end
    end

    context 'when a session holds a write transaction' do
      let(:sessions) { [writer_session] }

      it 'detects the write and blocks, naming the session in the message' do
        result = check.execute

        expect(result.status).to eq(:writes_detected)
        expect(result).to be_blocking
        expect(result.message).to include('123', 'gitlab', 'rails', 'active', '5s', 'INSERT INTO projects')
      end

      it 'logs the blocking pids without the query text' do
        expect(Gitlab::Geo::Logger).to receive(:error).with(hash_including(blocking_pids: [123]))
        expect(Gitlab::Geo::Logger).not_to receive(:error).with(hash_including(message: /INSERT/))

        check.execute
      end
    end

    context 'when a session is idle in transaction with no write xid yet' do
      let(:sessions) do
        [writer_session.merge('pid' => '456', 'state' => 'idle in transaction', 'holds_write_transaction' => 'f')]
      end

      it 'blocks, because an open transaction can write at any moment' do
        result = check.execute

        expect(result.status).to eq(:writes_detected)
        expect(result).to be_blocking
      end
    end

    context 'when a session is idle in an aborted transaction' do
      let(:sessions) do
        [writer_session.merge('state' => 'idle in transaction (aborted)', 'holds_write_transaction' => 'f')]
      end

      it 'does not block, because an aborted transaction can never commit' do
        result = check.execute

        expect(result.status).to eq(:no_writes)
        expect(result).not_to be_blocking
      end
    end

    context 'when only a read-only active session is present' do
      let(:sessions) do
        [writer_session.merge('pid' => '789', 'holds_write_transaction' => 'f', 'transaction_age_seconds' => nil)]
      end

      it 'passes, reports the session, and does not render a blank transaction age' do
        result = check.execute

        expect(result.status).to eq(:no_writes)
        expect(result).not_to be_blocking
        expect(result.message).to include('789', 'xact_age=n/a')
      end
    end

    context 'when the role cannot see every session in pg_stat_activity' do
      let(:masked_sessions) { '2' }

      it 'blocks and names the grant the role needs' do
        result = check.execute

        expect(result.status).to eq(:stats_not_visible)
        expect(result).to be_blocking
        expect(result.message).to include('GRANT pg_read_all_stats TO gitlab_replicator;')
      end
    end

    context 'when the target database is in recovery' do
      let(:in_recovery) { 't' }

      it 'blocks, because a standby cannot be the publisher' do
        result = check.execute

        expect(result.status).to eq(:wrong_target)
        expect(result).to be_blocking
        expect(result.message).to include('in recovery')
      end
    end

    context 'when the target database has no publication of the expected name' do
      let(:publication_exists) { 'f' }

      it 'blocks and names the publication it looked for' do
        result = described_class.new(
          connection_string: connection_string, publication_name: 'geo_publication', connect_retry_interval: 0
        ).execute

        expect(result.status).to eq(:wrong_target)
        expect(result).to be_blocking
        expect(result.message).to include('geo_publication')
      end

      it 'skips only the publication check when no publication name is given' do
        result = described_class.new(
          connection_string: connection_string, publication_name: nil, connect_retry_interval: 0
        ).execute

        expect(result.status).to eq(:no_writes)
      end
    end

    context 'when no writes are detected but maintenance mode is off' do
      let(:maintenance_mode) { 'f' }

      it 'passes but warns that writes can resume' do
        result = check.execute

        expect(result.status).to eq(:no_writes)
        expect(result.message).to include('Maintenance mode is off on the publisher')
      end
    end

    context 'when reading maintenance_mode raises' do
      before do
        allow(connection).to receive(:exec) do |sql|
          raise PG::InsufficientPrivilege, 'permission denied' if sql.include?('maintenance_mode')

          if sql.include?('masked_sessions')
            instance_double(PG::Result, first: { 'masked_sessions' => masked_sessions })
          elsif sql.include?('pg_stat_activity')
            instance_double(PG::Result, to_a: sessions)
          end
        end
      end

      it 'does not change the outcome and still rolls the transaction back' do
        result = check.execute

        expect(result.status).to eq(:no_writes)
        expect(result.maintenance_mode).to be_nil
        expect(connection).to have_received(:exec).with('ROLLBACK')
      end
    end

    context 'when a query fails on an established connection' do
      shared_examples 'a query-phase failure classified as' do |status, blocking:|
        it "returns #{status}, #{blocking ? 'blocking' : 'not blocking'}, without retrying the connection" do
          result = check.execute

          expect(PG).to have_received(:connect).once
          expect(result.status).to eq(status)
          expect(result.blocking?).to be(blocking)
          expect(connection).to have_received(:exec).with('ROLLBACK')
        end
      end

      def failing_sessions_query(error)
        allow(connection).to receive(:exec) do |sql|
          raise error if sql.include?('pg_stat_activity') && sql.exclude?('masked_sessions')

          instance_double(PG::Result, first: { 'masked_sessions' => masked_sessions })
        end
      end

      context 'with a server-reported error such as a missing column' do
        before do
          failing_sessions_query(PG::UndefinedColumn.new('column a.backend_type does not exist'))
        end

        it_behaves_like 'a query-phase failure classified as', :check_failed, blocking: true

        it 'names the error and says nothing was verified' do
          expect(check.execute.message).to include('PG::UndefinedColumn', 'nothing was verified')
        end
      end

      context 'with the statement timeout firing' do
        before do
          failing_sessions_query(PG::QueryCanceled.new('canceling statement due to statement timeout'))
        end

        it_behaves_like 'a query-phase failure classified as', :unreachable, blocking: false

        it 'says the publisher accepted the connection but did not answer in time' do
          expect(check.execute.message)
            .to include('did not answer within', "#{described_class::STATEMENT_TIMEOUT_MS}ms")
        end
      end

      context 'with the connection dropping mid-query' do
        before do
          failing_sessions_query(PG::ConnectionBad.new('server closed the connection unexpectedly'))
        end

        it_behaves_like 'a query-phase failure classified as', :unreachable, blocking: false
      end

      context 'with an unexpected Ruby error' do
        before do
          failing_sessions_query(NoMethodError.new('boom'))
        end

        it_behaves_like 'a query-phase failure classified as', :check_failed, blocking: true

        it 'tracks the exception' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(NoMethodError))

          check.execute
        end
      end
    end

    context 'when the publisher is unreachable' do
      before do
        allow(PG).to receive(:connect).and_raise(PG::ConnectionBad, 'could not connect to server')
      end

      it 'retries the connection a bounded number of times, then does not block' do
        result = check.execute

        expect(PG).to have_received(:connect).exactly(described_class::CONNECT_ATTEMPTS).times
        expect(result.status).to eq(:unreachable)
        expect(result).not_to be_blocking
        expect(result.message).to include('could not connect to server')
      end
    end

    context 'when the publisher is only briefly unreachable' do
      before do
        calls = 0
        allow(PG).to receive(:connect) do
          calls += 1
          raise PG::ConnectionBad, 'blip' if calls < 3

          connection
        end
      end

      it 'connects on a later attempt instead of skipping the gate' do
        result = check.execute

        expect(PG).to have_received(:connect).exactly(3).times
        expect(result.status).to eq(:no_writes)
      end

      it 'waits the retry interval between attempts' do
        checker = described_class.new(connection_string: connection_string)
        allow(checker).to receive(:sleep)

        checker.execute

        expect(checker).to have_received(:sleep).with(described_class::CONNECT_RETRY_INTERVAL_SECONDS).twice
      end
    end

    context 'when connecting raises something other than a PG error' do
      before do
        allow(PG).to receive(:connect).and_raise(RuntimeError, 'unexpected')
      end

      it 'does not block, and tracks the exception' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(RuntimeError))

        result = check.execute

        expect(result.status).to eq(:unreachable)
        expect(result).not_to be_blocking
      end
    end

    context 'when GEO_PUBLISHER_CONNECTION_STRING is not set' do
      let(:connection_string) { nil }

      it 'does not connect, blocks, and names both the variable and the skip flag' do
        expect(PG).not_to receive(:connect)

        result = check.execute

        expect(result.status).to eq(:not_configured)
        expect(result).to be_blocking
        expect(result.message).to include('GEO_PUBLISHER_CONNECTION_STRING', 'GEO_SKIP_WRITE_ACTIVITY_CHECK=1')
      end
    end

    context 'when no connection string is passed' do
      it 'falls back to GEO_PUBLISHER_CONNECTION_STRING, as the promotion path relies on' do
        stub_env('GEO_PUBLISHER_CONNECTION_STRING', connection_string)

        expect(described_class.execute(connect_retry_interval: 0).status).to eq(:no_writes)
        expect(PG).to have_received(:connect).with(connection_string, anything)
      end
    end
  end

  # Runs the real SQL against the test database, so a renamed pg_stat_activity column or a
  # broken statement fails here instead of silently degrading a promotion in the field.
  describe 'against the test database', :aggregate_failures do
    let(:test_db_connection_string) do
      config = ApplicationRecord.connection_db_config.configuration_hash

      PG::Connection.parse_connect_args(
        {
          host: config[:host], port: config[:port], dbname: config[:database],
          user: config[:username], password: config[:password]
        }.compact
      )
    end

    before do
      allow(PG).to receive(:connect).and_call_original
    end

    it 'runs the target assertion for real and rejects a database with no publication' do
      result = described_class.new(
        connection_string: test_db_connection_string, publication_name: 'geo_publication', connect_retry_interval: 0
      ).execute

      expect(result.status).to eq(:wrong_target)
      expect(result.message).to include('geo_publication')
    end

    it 'runs the visibility, session and maintenance mode queries for real' do
      result = described_class.new(
        connection_string: test_db_connection_string, publication_name: nil, connect_retry_interval: 0
      ).execute

      expect(result.status).to eq(:no_writes).or eq(:writes_detected).or eq(:stats_not_visible)
    end

    it 'detects a real write transaction held by another session' do
      writer = PG.connect(test_db_connection_string)
      writer.exec('BEGIN')
      writer.exec('CREATE TEMP TABLE write_activity_probe(id int)')
      # A backend_xid is only assigned once the session has written.
      writer.exec('INSERT INTO write_activity_probe VALUES (1)')

      result = described_class.new(
        connection_string: test_db_connection_string, publication_name: nil, connect_retry_interval: 0
      ).execute

      row = result.sessions.find { |session| session['pid'].to_i == writer.backend_pid }
      expect(row).to be_present
      expect(row['holds_write_transaction']).to eq('t')
      expect(result.status).to eq(:writes_detected)
      expect(result.message).to include("pid #{writer.backend_pid}")
    ensure
      writer&.exec('ROLLBACK')
      writer&.close
    end
  end
end
