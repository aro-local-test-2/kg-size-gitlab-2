# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Transfer::GroupsService, :aggregate_failures, feature_category: :organization do
  let_it_be(:old_organization) { create(:organization) }
  let_it_be(:new_organization) { create(:organization) }
  let_it_be(:user) { create(:user, organization: old_organization) }
  let_it_be_with_refind(:group) { create(:group, organization: old_organization) }

  let(:service) { described_class.new(group: group, new_organization: new_organization, current_user: user) }

  before_all do
    group.add_owner(user)
    new_organization.add_owner(user)
  end

  describe '#execute' do
    context 'when transfer is successful' do
      let_it_be_with_refind(:subgroup) { create(:group, parent: group, organization: old_organization) }
      let_it_be_with_refind(:project) { create(:project, namespace: group, organization: old_organization) }

      context 'for cd environments' do
        let_it_be_with_refind(:cd_environment) do
          create(:cd_environment, organization: old_organization)
        end

        let_it_be_with_refind(:cd_environment2) do
          create(:cd_environment, organization: old_organization)
        end

        # Cd::Environment records are organization-scoped and stay with the
        # organization during a group transfer. See discussion:
        # https://gitlab.com/gitlab-org/gitlab/-/merge_requests/238712#note_3424705739
        it 'does not move organization-scoped cd environments to the new organization' do
          service.execute

          expect(cd_environment.reload.organization_id).to eq(old_organization.id)
          expect(cd_environment2.reload.organization_id).to eq(old_organization.id)
        end
      end

      context 'for seat assignment transfers' do
        let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user2) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user3) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:seat_assignment1) do
          create(:gitlab_subscription_seat_assignment,
            namespace: group,
            user: user1,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:seat_assignment2) do
          create(:gitlab_subscription_seat_assignment,
            namespace: group,
            user: user2,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:seat_assignment3) do
          create(:gitlab_subscription_seat_assignment,
            namespace: group,
            user: user3,
            organization_id: old_organization.id)
        end

        before_all do
          group.add_maintainer(user1)
          group.add_developer(user2)
          group.add_guest(user3)
        end

        it 'updates organization_id for seat assignments' do
          service.execute

          expect(seat_assignment1.reload.organization_id).to eq(new_organization.id)
          expect(seat_assignment2.reload.organization_id).to eq(new_organization.id)
          expect(seat_assignment3.reload.organization_id).to eq(new_organization.id)
        end

        it 'only updates seat assignments for the transferring group' do
          other_group = create(:group, organization: old_organization)
          other_seat_assignment = create(:gitlab_subscription_seat_assignment,
            namespace: other_group,
            user: user1,
            organization_id: old_organization.id)

          service.execute

          expect(other_seat_assignment.reload.organization_id).to eq(old_organization.id)
        end

        context 'when batching updates' do
          include_context 'with transfer batch size of 1'

          let(:execute_service) { service.execute }
          let(:expected_batch_queries) do
            { 'subscription_seat_assignments' => 3 }
          end

          it 'processes all seat assignments across multiple batches' do
            service.execute

            expect(seat_assignment1.reload.organization_id).to eq(new_organization.id)
            expect(seat_assignment2.reload.organization_id).to eq(new_organization.id)
            expect(seat_assignment3.reload.organization_id).to eq(new_organization.id)
          end

          it_behaves_like 'generates batched transfer queries'
        end
      end

      context 'for add-on purchase transfers' do
        let_it_be(:add_on) { create(:gitlab_subscription_add_on, :duo_pro) }
        let_it_be_with_refind(:add_on_purchase) do
          create(:gitlab_subscription_add_on_purchase,
            :active,
            add_on: add_on,
            namespace: group,
            organization: old_organization)
        end

        let_it_be_with_refind(:add_on_purchase_2) do
          create(:gitlab_subscription_add_on_purchase,
            :active,
            add_on: create(:gitlab_subscription_add_on, :duo_enterprise),
            namespace: group,
            organization: old_organization)
        end

        it 'updates organization_id for all add-on purchases' do
          service.execute

          expect(add_on_purchase.reload.organization_id).to eq(new_organization.id)
          expect(add_on_purchase_2.reload.organization_id).to eq(new_organization.id)
        end
      end

      context 'for user add-on assignment transfers' do
        let_it_be(:add_on) { create(:gitlab_subscription_add_on, :duo_pro) }
        let_it_be_with_refind(:add_on_purchase) do
          create(:gitlab_subscription_add_on_purchase,
            :active,
            add_on: add_on,
            namespace: group,
            organization: old_organization)
        end

        let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user2) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user3) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user_add_on_assignment1) do
          create(:gitlab_subscription_user_add_on_assignment,
            user: user1,
            add_on_purchase: add_on_purchase,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:user_add_on_assignment2) do
          create(:gitlab_subscription_user_add_on_assignment,
            user: user2,
            add_on_purchase: add_on_purchase,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:user_add_on_assignment3) do
          create(:gitlab_subscription_user_add_on_assignment,
            user: user3,
            add_on_purchase: add_on_purchase,
            organization_id: old_organization.id)
        end

        before_all do
          group.add_maintainer(user1)
          group.add_developer(user2)
          group.add_guest(user3)
        end

        it 'updates organization_id for user add-on assignments' do
          service.execute

          expect(user_add_on_assignment1.reload.organization_id).to eq(new_organization.id)
          expect(user_add_on_assignment2.reload.organization_id).to eq(new_organization.id)
          expect(user_add_on_assignment3.reload.organization_id).to eq(new_organization.id)
        end

        context 'when user add-on assignments belong to different add-on purchase' do
          let_it_be(:other_group) { create(:group, organization: old_organization) }
          let_it_be_with_refind(:other_add_on_purchase) do
            create(:gitlab_subscription_add_on_purchase,
              :active,
              add_on: add_on,
              namespace: other_group,
              organization: old_organization)
          end

          let_it_be_with_refind(:other_assignment) do
            create(:gitlab_subscription_user_add_on_assignment,
              user: user1,
              add_on_purchase: other_add_on_purchase,
              organization_id: old_organization.id)
          end

          it 'does not update assignments for other add-on purchases' do
            service.execute

            expect(user_add_on_assignment1.reload.organization_id).to eq(new_organization.id)
            expect(other_assignment.reload.organization_id).to eq(old_organization.id)
          end
        end

        it 'updates organization_id for user add-on assignment versions' do
          service.execute

          version_1 = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(purchase_id: add_on_purchase.id,
            user_id: user1.id)
          version_2 = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(purchase_id: add_on_purchase.id,
            user_id: user2.id)
          version_3 = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(purchase_id: add_on_purchase.id,
            user_id: user3.id)

          expect(version_1.organization_id).to eq(new_organization.id)
          expect(version_2.organization_id).to eq(new_organization.id)
          expect(version_3.organization_id).to eq(new_organization.id)
        end

        context 'when user add-on assignment versions belong to different add-on purchase' do
          let_it_be(:other_group) { create(:group, organization: old_organization) }
          let_it_be_with_refind(:other_add_on_purchase) do
            create(:gitlab_subscription_add_on_purchase,
              :active,
              add_on: add_on,
              namespace: other_group,
              organization: old_organization)
          end

          let_it_be_with_refind(:other_assignment) do
            create(:gitlab_subscription_user_add_on_assignment,
              user: user1,
              add_on_purchase: other_add_on_purchase,
              organization_id: old_organization.id)
          end

          it 'does not update versions for other add-on purchases' do
            service.execute

            transferring_version = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(
              purchase_id: add_on_purchase.id,
              user_id: user1.id)
            other_version = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(
              purchase_id: other_add_on_purchase.id,
              user_id: user1.id)

            expect(transferring_version.organization_id).to eq(new_organization.id)
            expect(other_version.organization_id).to eq(old_organization.id)
          end
        end
      end

      context 'for security export upload transfers' do
        let_it_be_with_refind(:dep_part_upload) do
          create(:geo_dependency_list_export_part_upload,
            parent_model: create(:dependency_list_export_part,
              dependency_list_export: create(:dependency_list_export, project: nil, group: group, organization: nil),
              organization: old_organization))
        end

        let_it_be_with_refind(:vuln_export_upload) do
          create(:geo_vulnerability_export_upload,
            parent_model: create(:vulnerability_export, :group, group: group, organization: old_organization))
        end

        let_it_be_with_refind(:vuln_part_upload) do
          create(:geo_vulnerability_export_part_upload,
            parent_model: create(:vulnerability_export_part,
              vulnerability_export: create(:vulnerability_export, project: project, organization: old_organization),
              organization: old_organization))
        end

        it 'updates organization_id for security export uploads' do
          service.execute

          expect(dep_part_upload.reload.organization_id).to eq(new_organization.id)
          expect(vuln_export_upload.reload.organization_id).to eq(new_organization.id)
          expect(vuln_part_upload.reload.organization_id).to eq(new_organization.id)
        end

        it 'fires triggers on upload state tables' do
          # Ensure state records exist and have the old org_id
          dep_state = dep_part_upload.dependency_list_export_part_upload_state
          dep_state.save! unless dep_state.persisted?
          dep_state.update_column(:organization_id, old_organization.id)

          vuln_state = vuln_export_upload.vulnerability_export_upload_state
          vuln_state.save! unless vuln_state.persisted?
          vuln_state.update_column(:organization_id, old_organization.id)

          vuln_part_state = vuln_part_upload.vulnerability_export_part_upload_state
          vuln_part_state.save! unless vuln_part_state.persisted?
          vuln_part_state.update_column(:organization_id, old_organization.id)

          service.execute

          expect(dep_state.reload.organization_id).to eq(new_organization.id)
          expect(vuln_state.reload.organization_id).to eq(new_organization.id)
          expect(vuln_part_state.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update uploads belonging to an unrelated organization' do
          unrelated_organization = create(:organization)
          unrelated_group = create(:group, organization: unrelated_organization)
          unrelated_project = create(:project, namespace: unrelated_group, organization: unrelated_organization)

          unrelated_export = create(:vulnerability_export,
            project: unrelated_project, organization: unrelated_organization)
          unrelated_upload = create(:geo_vulnerability_export_upload, parent_model: unrelated_export)

          service.execute

          expect(unrelated_upload.reload.organization_id).to eq(unrelated_organization.id)
        end

        it 'does not update state records for uploads outside the transferred group' do
          unrelated_group = create(:group, organization: new_organization)
          unrelated_project = create(:project, namespace: unrelated_group, organization: new_organization)

          unrelated_upload = create(:geo_vulnerability_export_upload,
            parent_model: create(:vulnerability_export, project: unrelated_project, organization: new_organization))

          unrelated_state = unrelated_upload.vulnerability_export_upload_state
          unrelated_state.save! unless unrelated_state.persisted?
          unrelated_state.update_column(:organization_id, old_organization.id)

          service.execute

          expect(unrelated_state.reload.organization_id).to eq(old_organization.id)
        end

        context 'when batching updates' do
          include_context 'with transfer batch size of 1'

          let_it_be_with_refind(:dep_part_upload2) do
            create(:geo_dependency_list_export_part_upload,
              parent_model: create(:dependency_list_export_part,
                dependency_list_export: create(:dependency_list_export, project: nil, group: group,
                  organization: nil),
                organization: old_organization))
          end

          let_it_be_with_refind(:dep_part_upload3) do
            create(:geo_dependency_list_export_part_upload,
              parent_model: create(:dependency_list_export_part,
                dependency_list_export: create(:dependency_list_export, project: project, organization: nil),
                organization: old_organization))
          end

          let_it_be_with_refind(:vuln_export_upload2) do
            create(:geo_vulnerability_export_upload,
              parent_model: create(:vulnerability_export, :group, group: group, organization: old_organization))
          end

          let_it_be_with_refind(:vuln_export_upload3) do
            create(:geo_vulnerability_export_upload,
              parent_model: create(:vulnerability_export, project: project, organization: old_organization))
          end

          let_it_be_with_refind(:vuln_part_upload2) do
            create(:geo_vulnerability_export_part_upload,
              parent_model: create(:vulnerability_export_part,
                vulnerability_export: create(:vulnerability_export, :group, group: group,
                  organization: old_organization),
                organization: old_organization))
          end

          let_it_be_with_refind(:vuln_part_upload3) do
            create(:geo_vulnerability_export_part_upload,
              parent_model: create(:vulnerability_export_part,
                vulnerability_export: create(:vulnerability_export, project: project,
                  organization: old_organization),
                organization: old_organization))
          end

          let(:execute_service) { service.execute }
          let(:expected_batch_queries) do
            {
              'dependency_list_export_part_uploads' => 3,
              'vulnerability_export_uploads' => 3,
              'vulnerability_export_part_uploads' => 3
            }
          end

          it 'processes all upload records across multiple batches' do
            service.execute

            expect(dep_part_upload2.reload.organization_id).to eq(new_organization.id)
            expect(dep_part_upload3.reload.organization_id).to eq(new_organization.id)
            expect(vuln_export_upload2.reload.organization_id).to eq(new_organization.id)
            expect(vuln_export_upload3.reload.organization_id).to eq(new_organization.id)
            expect(vuln_part_upload2.reload.organization_id).to eq(new_organization.id)
            expect(vuln_part_upload3.reload.organization_id).to eq(new_organization.id)
          end

          it_behaves_like 'generates batched transfer queries'
        end
      end

      context 'for security export parts async transfer' do
        it 'schedules SecurityExportsWorker after commit' do
          expect(::Organizations::Transfer::SecurityExportsWorker)
            .to receive(:perform_async)
            .with(group.id, old_organization.id, new_organization.id)

          service.execute
        end
      end

      context 'for ai catalog item transfers' do
        let_it_be_with_refind(:ai_catalog_item) do
          create(:ai_catalog_item, project: project, organization: old_organization)
        end

        it 'updates organization_id for ai catalog items linked to projects in the group' do
          service.execute

          expect(ai_catalog_item.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update ai catalog items for projects outside the group' do
          other_group = create(:group, organization: old_organization)
          other_project = create(:project, namespace: other_group, organization: old_organization)
          other_item = create(:ai_catalog_item, project: other_project, organization: old_organization)

          expect { service.execute }.not_to change { other_item.reload.organization_id }
        end

        context 'when ai catalog items are in subgroup projects' do
          let_it_be_with_refind(:nested_subgroup) { create(:group, parent: subgroup, organization: old_organization) }
          let_it_be_with_refind(:subgroup_project) do
            create(:project, namespace: nested_subgroup, organization: old_organization)
          end

          let_it_be_with_refind(:subgroup_catalog_item) do
            create(:ai_catalog_item, project: subgroup_project, organization: old_organization)
          end

          it 'updates organization_id for ai catalog items in subgroup projects' do
            service.execute

            expect(subgroup_catalog_item.reload.organization_id).to eq(new_organization.id)
          end
        end
      end

      context 'for upcoming reconciliation transfers' do
        let_it_be_with_refind(:reconciliation) do
          create(:upcoming_reconciliation, :saas, namespace: group, organization: old_organization)
        end

        let_it_be_with_refind(:subgroup_reconciliation) do
          create(:upcoming_reconciliation, :saas, namespace: subgroup, organization: old_organization)
        end

        it 'updates organization_id for reconciliations in the transferred group' do
          service.execute

          expect(reconciliation.reload.organization_id).to eq(new_organization.id)
          expect(subgroup_reconciliation.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update reconciliations for other groups' do
          other_group = create(:group, organization: old_organization)
          other_reconciliation = create(:upcoming_reconciliation, :saas,
            namespace: other_group, organization: old_organization)

          service.execute

          expect(other_reconciliation.reload.organization_id).to eq(old_organization.id)
        end
      end

      context 'for scim token transfers' do
        let_it_be_with_refind(:scim_token) do
          create(:scim_oauth_access_token, group: group, organization: old_organization)
        end

        let_it_be_with_refind(:subgroup_scim_token) do
          create(:scim_oauth_access_token, group: subgroup, organization: old_organization)
        end

        it 'updates organization_id for group-scoped SCIM tokens' do
          service.execute

          expect(scim_token.reload.organization_id).to eq(new_organization.id)
          expect(subgroup_scim_token.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update instance-level SCIM tokens' do
          instance_token = create(:scim_oauth_access_token, group: nil, organization: old_organization)

          service.execute

          expect(instance_token.reload.organization_id).to eq(old_organization.id)
        end

        it 'does not update SCIM tokens for other groups' do
          other_group = create(:group, organization: old_organization)
          other_token = create(:scim_oauth_access_token, group: other_group, organization: old_organization)

          service.execute

          expect(other_token.reload.organization_id).to eq(old_organization.id)
        end
      end

      context 'when batching fulfillment and identity table updates' do
        include_context 'with transfer batch size of 1'

        let_it_be(:nested_subgroup) { create(:group, parent: subgroup, organization: old_organization) }

        let_it_be_with_refind(:reconciliation1) do
          create(:upcoming_reconciliation, :saas, namespace: group, organization: old_organization)
        end

        let_it_be_with_refind(:reconciliation2) do
          create(:upcoming_reconciliation, :saas, namespace: subgroup, organization: old_organization)
        end

        let_it_be_with_refind(:reconciliation3) do
          create(:upcoming_reconciliation, :saas, namespace: nested_subgroup, organization: old_organization)
        end

        let_it_be_with_refind(:scim_token1) do
          create(:scim_oauth_access_token, group: group, organization: old_organization)
        end

        let_it_be_with_refind(:scim_token2) do
          create(:scim_oauth_access_token, group: subgroup, organization: old_organization)
        end

        let_it_be_with_refind(:scim_token3) do
          create(:scim_oauth_access_token, group: nested_subgroup, organization: old_organization)
        end

        let(:execute_service) { service.execute }
        let(:expected_batch_queries) do
          {
            'upcoming_reconciliations' => 3,
            'scim_oauth_access_tokens' => 3
          }
        end

        it 'processes all records across multiple batches' do
          service.execute

          expect(reconciliation1.reload.organization_id).to eq(new_organization.id)
          expect(reconciliation2.reload.organization_id).to eq(new_organization.id)
          expect(reconciliation3.reload.organization_id).to eq(new_organization.id)
          expect(scim_token1.reload.organization_id).to eq(new_organization.id)
          expect(scim_token2.reload.organization_id).to eq(new_organization.id)
          expect(scim_token3.reload.organization_id).to eq(new_organization.id)
        end

        it_behaves_like 'generates batched transfer queries'
      end

      context 'for custom dashboards transfers' do
        let_it_be_with_refind(:dashboard) do
          create(:dashboard, namespace: group, organization: old_organization)
        end

        let_it_be_with_refind(:subgroup_dashboard) do
          create(:dashboard, namespace: subgroup, organization: old_organization)
        end

        let_it_be_with_refind(:org_scoped_dashboard) do
          create(:dashboard, :organization_scoped, organization: old_organization)
        end

        let_it_be_with_refind(:dashboard_version) do
          create(:dashboard_version, dashboard: dashboard)
        end

        it 'updates organization_id for dashboards, search data, and dashboard versions' do
          service.execute

          expect(dashboard.reload.organization_id).to eq(new_organization.id)
          expect(dashboard.search_data.organization_id).to eq(new_organization.id)
          expect(dashboard_version.reload.organization_id).to eq(new_organization.id)
          expect(subgroup_dashboard.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update organization-scoped dashboards' do
          service.execute

          expect(org_scoped_dashboard.reload.organization_id).to eq(old_organization.id)
          expect(org_scoped_dashboard.search_data.organization_id).to eq(old_organization.id)
        end

        it 'does not update dashboards belonging to other groups in the old organization' do
          other_group = create(:group, organization: old_organization)
          other_dashboard = create(:dashboard, namespace: other_group, organization: old_organization)
          other_version = create(:dashboard_version, dashboard: other_dashboard)

          service.execute

          expect(other_dashboard.reload.organization_id).to eq(old_organization.id)
          expect(other_dashboard.search_data.organization_id).to eq(old_organization.id)
          expect(other_version.reload.organization_id).to eq(old_organization.id)
        end

        it 'does not update dashboards in other organizations' do
          other_organization = create(:organization)
          other_dashboard = create(:dashboard, :organization_scoped, organization: other_organization)

          expect { service.execute }.not_to change { other_dashboard.reload.organization_id }
        end
      end
    end

    context 'when transfer fails' do
      let_it_be(:add_on) { create(:gitlab_subscription_add_on, :duo_pro) }
      let_it_be_with_refind(:add_on_purchase) do
        create(:gitlab_subscription_add_on_purchase,
          :active,
          add_on: add_on,
          namespace: group,
          organization: old_organization)
      end

      let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
      let_it_be_with_refind(:seat_assignment) do
        create(:gitlab_subscription_seat_assignment,
          namespace: group,
          user: user1,
          organization_id: old_organization.id)
      end

      let_it_be_with_refind(:user_add_on_assignment) do
        create(:gitlab_subscription_user_add_on_assignment,
          user: user1,
          add_on_purchase: add_on_purchase,
          organization_id: old_organization.id)
      end

      before_all do
        group.add_maintainer(user1)
      end

      context 'when an exception occurs during transfer' do
        let(:error_message) { 'Transfer failed' }

        before do
          allow(ForkNetwork).to receive(:where).and_raise(StandardError, error_message)
        end

        it_behaves_like 'rolls back organization_id updates' do
          let(:records) { [add_on_purchase, seat_assignment, user_add_on_assignment] }
        end

        it 'returns error ServiceResponse' do
          result = service.execute

          expect(result).to be_a(ServiceResponse)
          expect(result).to be_error
          expect(result.message).to eq(error_message)
        end
      end
    end
  end
end
