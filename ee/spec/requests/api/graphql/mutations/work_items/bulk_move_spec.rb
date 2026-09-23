# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Bulk move work items', feature_category: :team_planning do
  include GraphqlHelpers

  context 'when source and target namespace are a group' do
    let_it_be(:source_group) { create(:group) }
    let_it_be(:source_subgroup) { create(:group, parent: source_group) }
    let_it_be(:target_group) { create(:group) }
    let_it_be(:target_subgroup) { create(:group, parent: target_group) }
    let_it_be(:user) { create(:user, developer_of: [source_group, target_group]) }

    let_it_be(:group_work_item_1) { create(:work_item, :epic, namespace: source_group) }
    let_it_be(:group_work_item_2) { create(:work_item, :epic, namespace: source_group) }
    let_it_be(:subgroup_work_item) { create(:work_item, :epic, namespace: source_subgroup) }

    let(:mutation) do
      graphql_mutation(:work_item_bulk_move, {
        'ids' => [group_work_item_1.to_gid.to_s, group_work_item_2.to_gid.to_s],
        'sourceFullPath' => source_group.full_path,
        'targetFullPath' => target_group.full_path
      })
    end

    let(:mutation_response) { graphql_mutation_response(:work_item_bulk_move) }

    context 'when epics are enabled' do
      before do
        stub_licensed_features(epics: true)
      end

      it 'moves work items from one group to another' do
        expect { post_graphql_mutation(mutation, current_user: user) }
          .to change { target_group.work_items.count }
          .from(0).to(2)

        expect(mutation_response).to include('movedWorkItemCount' => 2)
      end

      context 'when source and target are subgroups' do
        let(:mutation) do
          graphql_mutation(:work_item_bulk_move, {
            'ids' => [subgroup_work_item.to_gid.to_s],
            'sourceFullPath' => source_subgroup.full_path,
            'targetFullPath' => target_subgroup.full_path
          })
        end

        it 'moves work items from one subgroup to another' do
          expect { post_graphql_mutation(mutation, current_user: user) }
            .to change { target_subgroup.work_items.count }
           .from(0).to(1)

          expect(mutation_response).to include('movedWorkItemCount' => 1)
        end
      end
    end

    context 'when epics are disabled' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'does not move work items from one group to another' do
        expect { post_graphql_mutation(mutation, current_user: user) }
          .not_to change { target_group.work_items.count }
          .from(0)

        expect(graphql_data.dig('workItemBulkMove', 'errors'))
          .to contain_exactly('You do not have permission to move items to this namespace.')
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:boundary_object) { source_group }

      let(:mutation) do
        graphql_mutation(:work_item_bulk_move,
          {
            ids: [group_work_item_1.to_gid.to_s, group_work_item_2.to_gid.to_s],
            source_full_path: source_group.full_path,
            target_full_path: target_group.full_path
          },
          'errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }

      before do
        stub_licensed_features(epics: true)
        # Moving two epics costs about 175 queries and granular authorization adds about 35 (measured 210).
        # The other examples pass unstubbed only because all_graphql_fields_for raises the limit to 1000.
        allow(Gitlab::QueryLimiting::Transaction).to receive(:threshold).and_return(225)
      end
    end
  end
end
