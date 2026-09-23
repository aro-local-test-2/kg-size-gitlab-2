# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::GroupQueryBuilder, feature_category: :global_search do
  include AdminModeHelper
  include ElasticsearchHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:admin) { create(:admin) }

  describe '#build' do
    subject(:query) { described_class.new(query: search_term, options: params.merge(current_user: current_user)).build }

    let(:search_term) { 'gitlab' }
    let(:current_user) { user }
    let(:params) { {} }

    it 'includes a multi_match query on the correct fields' do
      bool_query = query[:query][:bool][:must].first
      expect(bool_query[:bool][:should]).to include(
        hash_including(
          multi_match: hash_including(
            query: 'gitlab',
            fields: %w[name^3 full_name^2 path^2 full_path description]
          )
        )
      )
    end

    it 'sets default page size' do
      expect(query[:size]).to eq(20)
    end

    context 'with pagination params' do
      let(:params) { { page: 2, per_page: 10 } }

      it 'calculates correct offset' do
        expect(query[:from]).to eq(10)
        expect(query[:size]).to eq(10)
      end
    end

    context 'with blank search term' do
      let(:search_term) { '' }

      it 'uses match_all query' do
        expect(query[:query][:bool][:must]).to eq({ match_all: {} })
      end
    end

    context 'with visibility filtering' do
      context 'for regular user' do
        it 'includes visibility permission filter' do
          assert_names_in_query(query, with: %w[filters:permissions:global])
        end
      end

      context 'for anonymous user' do
        let(:current_user) { nil }

        it 'includes visibility permission filter' do
          assert_names_in_query(query, with: %w[filters:permissions:global])
        end
      end

      context 'for admin user' do
        let(:current_user) { admin }

        before do
          enable_admin_mode!(admin)
        end

        it 'includes simplified admin filter' do
          assert_names_in_query(query,
            with: %w[filters:permissions:global:admin_all_groups:visibility_level:all])
        end
      end
    end

    context 'with parent_id filter' do
      let_it_be(:parent_group) { create(:group) }
      let(:params) { { parent_id: parent_group.id } }

      it 'includes parent_id filter' do
        assert_names_in_query(query, with: %w[filters:parent])

        parent_filter = query[:query][:bool][:filter].find { |f| f[:term]&.key?(:parent_id) }
        expect(parent_filter[:term][:parent_id][:value]).to eq(parent_group.id)
      end
    end

    context 'with group level search' do
      let_it_be(:searched_group) { create(:group) }
      let(:params) { { search_level: :group, group_ids: [searched_group.id], excluded_ids: [searched_group.id] } }

      it 'scopes the query to the group ancestry' do
        assert_names_in_query(query, with: %w[filters:level:group])
      end

      it 'excludes the searched group itself' do
        assert_names_in_query(query, with: %w[filters:excluded_ids])

        expect(query[:query][:bool][:must_not]).to include(
          hash_including(terms: hash_including(id: [searched_group.id]))
        )
      end
    end

    context 'with archived filter' do
      context 'when archived is false' do
        let(:params) { { archived: false } }

        it 'filters out archived groups' do
          assert_names_in_query(query, with: %w[filters:non_archived])
        end
      end

      context 'when include_archived is true' do
        let(:params) { { archived: false, include_archived: true } }

        it 'does not add archived filter' do
          assert_names_in_query(query, without: %w[filters:non_archived])
        end
      end
    end

    context 'with organization filter' do
      let(:params) { { organization_id: 123 } }

      it 'includes organization_id filter' do
        assert_names_in_query(query, with: %w[filters:organization])

        org_filter = query[:query][:bool][:filter].find { |f| f[:term]&.key?(:organization_id) }
        expect(org_filter[:term][:organization_id][:value]).to eq(123)
      end
    end

    describe 'sorting' do
      context 'with order_by created_at' do
        let(:params) { { order_by: 'created_at', sort: 'asc' } }

        it 'sorts by created_at' do
          expect(query[:sort]).to eq([{ created_at: { order: 'asc' } }])
        end
      end

      context 'with an unsupported order_by' do
        let(:params) { { order_by: 'name', sort: 'asc' } }

        it 'does not sort' do
          expect(query[:sort]).to eq({})
        end
      end

      context 'with order_by similarity' do
        let(:params) { { order_by: 'similarity' } }

        it 'sorts by relevance score' do
          expect(query[:sort]).to eq(['_score'])
        end
      end

      context 'with default sorting' do
        it 'sorts by updated_at desc' do
          expect(query[:sort]).to eq([{ updated_at: { order: 'desc' } }])
        end
      end
    end
  end
end
