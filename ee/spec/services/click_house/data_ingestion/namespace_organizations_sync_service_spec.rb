# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::DataIngestion::NamespaceOrganizationsSyncService, :click_house,
  feature_category: :value_stream_management do
  let(:connection) { ::ClickHouse::Connection.new(:main) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:root_group) { create(:group, organization: organization) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  subject(:execute) { described_class.new.execute }

  def synced
    connection
      .select('SELECT root_namespace_id, organization_id FROM namespace_organizations FINAL')
      .to_h { |row| [row['root_namespace_id'], row['organization_id']] }
  end

  it 'copies root namespaces with their organization' do
    expect(execute).to be_success

    expect(synced[root_group.id]).to eq(organization.id)
  end

  # The rebuild derives the prefix from the first path component, which is always a root namespace,
  # so syncing descendants would be dead weight in the lookup.
  it 'does not copy descendant namespaces' do
    execute

    expect(synced).not_to have_key(subgroup.id)
  end

  it 'is idempotent, keeping one row per root namespace' do
    # Deliberately not the memoized subject: a second call has to actually re-run the service.
    described_class.new.execute
    described_class.new.execute

    rows = connection
      .select("SELECT count() AS count FROM namespace_organizations FINAL WHERE root_namespace_id = #{root_group.id}")
      .first['count']

    expect(rows).to eq(1)
  end

  context 'when a namespace moves to another organization' do
    let!(:moving_group) { create(:group, organization: organization) }

    it 'keeps the latest assignment' do
      described_class.new.execute
      expect(synced[moving_group.id]).to eq(organization.id)

      other_organization = create(:organization)
      moving_group.update!(organization: other_organization)
      described_class.new.execute

      expect(synced[moving_group.id]).to eq(other_organization.id)
    end
  end

  context 'when ClickHouse is not configured' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:configured?).and_return(false)
    end

    it 'returns an error without writing' do
      expect(execute).to be_error
      expect(execute.reason).to eq(:db_not_configured)
    end
  end

  context 'when another job holds the lease' do
    it 'skips rather than running concurrently' do
      expect_next_instance_of(described_class) do |service|
        allow(service).to receive(:in_lock)
          .and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      end

      response = described_class.new.execute

      expect(response).to be_error
      expect(response.reason).to eq(:skipped)
    end
  end
end
