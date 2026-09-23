# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Remove linked items from a work item', feature_category: :portfolio_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user, reporter_of: group) }
  let_it_be(:work_item) { create(:work_item, :epic, namespace: group) }
  let_it_be(:linked_work_item) { create(:work_item, :epic, namespace: group) }
  let_it_be(:link) { create(:work_item_link, source: work_item, target: linked_work_item) }

  before do
    stub_licensed_features(epics: true, related_epics: true)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
    let(:user) { current_user }
    let(:boundary_object) { group }
    let(:mutation) do
      graphql_mutation(:workItemRemoveLinkedItems,
        { id: work_item.to_gid.to_s, workItemsIds: [linked_work_item.to_gid.to_s] },
        'errors')
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
