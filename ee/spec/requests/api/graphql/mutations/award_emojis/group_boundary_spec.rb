# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Award emoji mutations on a group-level awardable', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user, developer_of: group) }
  let_it_be(:epic) { create(:epic, group: group) }

  let(:emoji_name) { AwardEmoji::THUMBS_UP }
  let(:awardable_id) { GitlabSchema.id_from_object(epic).to_s }

  before do
    stub_licensed_features(epics: true)
  end

  describe 'AwardEmojiAdd' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_award_emoji do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) do
        graphql_mutation(:award_emoji_add, { awardable_id: awardable_id, name: emoji_name }, 'errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  describe 'AwardEmojiRemove' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_award_emoji do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) do
        graphql_mutation(:award_emoji_remove, { awardable_id: awardable_id, name: emoji_name }, 'errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }

      before do
        create(:award_emoji, name: emoji_name, awardable: epic, user: user)
      end
    end
  end

  describe 'AwardEmojiToggle' do
    it_behaves_like 'authorizing granular token permissions for GraphQL',
      [:create_award_emoji, :delete_award_emoji] do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) do
        graphql_mutation(:award_emoji_toggle, { awardable_id: awardable_id, name: emoji_name }, 'errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
