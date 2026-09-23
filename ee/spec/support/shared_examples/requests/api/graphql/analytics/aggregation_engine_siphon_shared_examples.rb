# frozen_string_literal: true

# Both shared examples require a `siphon_query` querying the engine under test.
RSpec.shared_examples 'a Siphon-dependent aggregation engine' do
  using RSpec::Parameterized::TableSyntax

  # ClickHouse is reported ahead of Siphon when both are missing: configuring ClickHouse is the
  # prerequisite, so naming it first keeps the error actionable.
  where(:clickhouse_configured, :siphon_enabled, :expected_message, :expected_code) do
    false | true  | 'ClickHouse is not configured on this instance.' | 'CLICKHOUSE_NOT_CONFIGURED'
    false | false | 'ClickHouse is not configured on this instance.' | 'CLICKHOUSE_NOT_CONFIGURED'
    true  | false | 'Siphon replication is not enabled on this instance.' | 'SIPHON_REPLICATION_DISABLED'
  end

  with_them do
    before do
      allow(Gitlab::ClickHouse).to receive_messages(
        configured?: clickhouse_configured,
        siphon_enabled?: siphon_enabled
      )
    end

    it 'returns a resource not available error naming the missing dependency' do
      post_graphql(siphon_query, current_user: current_user)

      expect(graphql_errors).to match([hash_including(
        'message' => expected_message,
        'extensions' => hash_including('code' => expected_code)
      )])
    end
  end
end

RSpec.shared_examples 'an aggregation engine that does not require Siphon' do
  before do
    allow(Gitlab::ClickHouse).to receive(:siphon_enabled?).and_return(false)
  end

  it 'resolves when Siphon replication is not enabled' do
    post_graphql(siphon_query, current_user: current_user)

    expect(graphql_errors).to be_nil
  end
end
