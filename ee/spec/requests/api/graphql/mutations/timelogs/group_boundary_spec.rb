# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Timelog mutations on a group-level issuable', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:author) { create(:user, developer_of: group) }
  # `with_reload` (freeze: false) because `Timelog belongs_to :issue, touch: true`:
  # `create(:timelog, issue: work_item)` below touches this instance, which
  # raises FrozenError on a default (frozen) `let_it_be` record.
  let_it_be_with_reload(:work_item) { create(:work_item, :epic, namespace: group) }

  before do
    stub_licensed_features(epics: true)
  end

  describe 'TimelogCreate' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_timelog do
      let(:user) { author }
      let(:boundary_object) { group }
      # Explicit selection without `timelog.project`: it is non-nullable in
      # GraphQL but null for a timelog on a group-level work item, so the
      # default all-fields selection errors on any successful mutation.
      let(:mutation) do
        graphql_mutation(:timelog_create, {
          time_spent: '1h',
          summary: 'Test summary',
          issuable_id: work_item.to_global_id.to_s
        }, 'timelog { id } errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  describe 'TimelogDelete' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_timelog do
      let(:user) { author }
      let(:boundary_object) { group }
      # Created per example rather than shared: each example destroys it.
      let(:timelog) { create(:timelog, user: author, issue: work_item, time_spent: 3600) }
      # Explicit selection without `timelog.project`, for the same reason as
      # TimelogCreate above.
      let(:mutation) do
        graphql_mutation(:timelog_delete, { id: timelog.to_global_id.to_s }, 'timelog { id } errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
