# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AiCatalogItemStar mutation', :with_current_organization, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be_with_reload(:item) { create(:ai_catalog_item, :public, organization: current_organization) }

  let(:starred) { true }

  let(:mutation) do
    graphql_mutation(:ai_catalog_item_star, { id: item.to_global_id.to_s, starred: starred })
  end

  def mutation_response
    graphql_mutation_response(:ai_catalog_item_star)
  end

  before do
    enable_ai_catalog
  end

  context 'when the user is not authenticated' do
    it 'returns a top-level access error' do
      post_graphql_mutation(mutation, current_user: nil)

      expect_graphql_errors_to_include(/you don't have permission/)
    end
  end

  context 'when the user does not have access to the item' do
    let_it_be(:item) { create(:ai_catalog_item, :private, organization: current_organization) }

    it 'returns a top-level access error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(/you don't have permission/)
    end
  end

  context 'when the user is authenticated' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :star_ai_catalog_item do
      let_it_be(:project) { create(:project, :in_group, maintainers: current_user) }
      # The item must belong to the boundary project so the mutation's
      # directive can extract the project boundary from the `id` argument.
      # `item` stays `let` (not `let_it_be`) because the star mutation under
      # test mutates its star state, which would leak across examples.
      let(:item) { create(:ai_catalog_item, :public, organization: current_organization, project: project) }

      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:authz_mutation) do
        graphql_mutation(:ai_catalog_item_star, { id: item.to_global_id.to_s, starred: starred }, 'errors')
      end

      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end

    # Foundational items have no project, so no project boundary resolves and the
    # user boundary applies instead.
    it_behaves_like 'authorizing granular token permissions for GraphQL', :star_ai_catalog_item do
      let(:item) { create(:ai_catalog_item, :public, organization: current_organization, project: nil) }

      let(:user) { current_user }
      let(:boundary_object) { :user }
      let(:authz_mutation) do
        graphql_mutation(:ai_catalog_item_star, { id: item.to_global_id.to_s, starred: starred }, 'errors')
      end

      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end

    context 'when starring an item' do
      let(:starred) { true }

      it 'stars the item and returns the updated star_count' do
        expect do
          post_graphql_mutation(mutation, current_user: current_user)
        end.to change { item.reload.star_count }.by(1)

        expect(mutation_response['starCount']).to eq(1)
        expect(mutation_response['errors']).to be_empty
      end

      context 'when the item is already starred' do
        before do
          item.star(current_user)
        end

        it 'is a no-op and returns the current star_count' do
          expect do
            post_graphql_mutation(mutation, current_user: current_user)
          end.not_to change { item.reload.star_count }

          expect(mutation_response['starCount']).to eq(1)
          expect(mutation_response['errors']).to be_empty
        end
      end
    end

    context 'when unstarring an item' do
      let(:starred) { false }

      before do
        item.star(current_user)
      end

      it 'unstars the item and returns the updated star_count' do
        expect do
          post_graphql_mutation(mutation, current_user: current_user)
        end.to change { item.reload.star_count }.by(-1)

        expect(mutation_response['starCount']).to eq(0)
        expect(mutation_response['errors']).to be_empty
      end
    end
  end
end
