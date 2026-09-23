# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Subscribe to a work item', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user, reporter_of: group) }
  let_it_be(:work_item) { create(:work_item, :epic, namespace: group) }

  before do
    stub_licensed_features(epics: true)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :subscribe_work_item do
    let(:user) { current_user }
    let(:boundary_object) { group }
    let(:mutation) do
      graphql_mutation(:workItemSubscribe,
        { id: work_item.to_gid.to_s, subscribed: true },
        'errors')
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
