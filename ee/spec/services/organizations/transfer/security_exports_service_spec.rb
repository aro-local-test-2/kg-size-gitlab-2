# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Transfer::SecurityExportsService, feature_category: :vulnerability_management do
  let_it_be(:old_organization) { create(:organization) }
  let_it_be(:new_organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: old_organization) }
  let_it_be(:subgroup) { create(:group, parent: group, organization: old_organization) }
  let_it_be(:project) { create(:project, namespace: subgroup, organization: old_organization) }

  let(:service) do
    described_class.new(
      group: group,
      old_organization: old_organization,
      new_organization: new_organization
    )
  end

  describe '#execute' do
    context 'for vulnerability exports' do
      let_it_be_with_refind(:group_vuln_export) do
        create(:vulnerability_export, :group, group: group, organization: old_organization)
      end

      let_it_be_with_refind(:project_vuln_export) do
        create(:vulnerability_export, project: project, organization: old_organization)
      end

      it 'updates organization_id for exports belonging to the group hierarchy' do
        service.execute

        expect(group_vuln_export.reload.organization_id).to eq(new_organization.id)
        expect(project_vuln_export.reload.organization_id).to eq(new_organization.id)
      end

      it 'does not update exports belonging to other groups' do
        other_group = create(:group, organization: old_organization)
        other_export = create(:vulnerability_export, :group, group: other_group,
          organization: old_organization)

        service.execute

        expect(other_export.reload.organization_id).to eq(old_organization.id)
      end

      it 'does not update exports belonging to an unrelated organization' do
        unrelated_organization = create(:organization)
        unrelated_group = create(:group, organization: unrelated_organization)
        unrelated_export = create(:vulnerability_export, :group, group: unrelated_group,
          organization: unrelated_organization)

        service.execute

        expect(unrelated_export.reload.organization_id).to eq(unrelated_organization.id)
      end
    end

    context 'for dependency list export parts' do
      let_it_be_with_refind(:group_dep_export) do
        create(:dependency_list_export, project: nil, group: group, organization: nil)
      end

      let_it_be_with_refind(:project_dep_export) do
        create(:dependency_list_export, project: project, organization: nil)
      end

      let_it_be_with_refind(:group_dep_part) do
        create(:dependency_list_export_part,
          dependency_list_export: group_dep_export,
          organization: old_organization)
      end

      let_it_be_with_refind(:project_dep_part) do
        create(:dependency_list_export_part,
          dependency_list_export: project_dep_export,
          organization: old_organization)
      end

      it 'updates organization_id for parts belonging to the group hierarchy' do
        service.execute

        expect(group_dep_part.reload.organization_id).to eq(new_organization.id)
        expect(project_dep_part.reload.organization_id).to eq(new_organization.id)
      end

      it 'does not update parts belonging to other groups' do
        other_group = create(:group, organization: old_organization)
        other_export = create(:dependency_list_export, project: nil, group: other_group,
          organization: nil)
        other_part = create(:dependency_list_export_part,
          dependency_list_export: other_export,
          organization: old_organization)

        service.execute

        expect(other_part.reload.organization_id).to eq(old_organization.id)
      end

      it 'does not update parts belonging to an unrelated organization' do
        unrelated_organization = create(:organization)
        unrelated_group = create(:group, organization: unrelated_organization)
        unrelated_export = create(:dependency_list_export, project: nil, group: unrelated_group,
          organization: nil)
        unrelated_part = create(:dependency_list_export_part,
          dependency_list_export: unrelated_export,
          organization: unrelated_organization)

        service.execute

        expect(unrelated_part.reload.organization_id).to eq(unrelated_organization.id)
      end
    end

    context 'for vulnerability export parts' do
      let_it_be_with_refind(:group_vuln_export) do
        create(:vulnerability_export, :group, group: group, organization: old_organization)
      end

      let_it_be_with_refind(:project_vuln_export) do
        create(:vulnerability_export, project: project, organization: old_organization)
      end

      let_it_be_with_refind(:group_vuln_part) do
        create(:vulnerability_export_part,
          vulnerability_export: group_vuln_export,
          organization: old_organization)
      end

      let_it_be_with_refind(:project_vuln_part) do
        create(:vulnerability_export_part,
          vulnerability_export: project_vuln_export,
          organization: old_organization)
      end

      it 'updates organization_id for parts belonging to the group hierarchy' do
        service.execute

        expect(group_vuln_part.reload.organization_id).to eq(new_organization.id)
        expect(project_vuln_part.reload.organization_id).to eq(new_organization.id)
      end

      it 'does not update parts belonging to other groups' do
        other_group = create(:group, organization: old_organization)
        other_export = create(:vulnerability_export, :group, group: other_group,
          organization: old_organization)
        other_part = create(:vulnerability_export_part,
          vulnerability_export: other_export,
          organization: old_organization)

        service.execute

        expect(other_part.reload.organization_id).to eq(old_organization.id)
      end

      it 'does not update parts belonging to an unrelated organization' do
        unrelated_organization = create(:organization)
        unrelated_group = create(:group, organization: unrelated_organization)
        unrelated_export = create(:vulnerability_export, :group, group: unrelated_group,
          organization: unrelated_organization)
        unrelated_part = create(:vulnerability_export_part,
          vulnerability_export: unrelated_export,
          organization: unrelated_organization)

        service.execute

        expect(unrelated_part.reload.organization_id).to eq(unrelated_organization.id)
      end
    end

    context 'when batching updates' do
      include_context 'with transfer batch size of 1'

      let_it_be_with_refind(:extra_vuln_export) do
        create(:vulnerability_export, :group, group: group, organization: old_organization)
      end

      let_it_be_with_refind(:extra_vuln_export2) do
        create(:vulnerability_export, project: project, organization: old_organization)
      end

      let_it_be_with_refind(:extra_vuln_export3) do
        create(:vulnerability_export, :group, group: subgroup, organization: old_organization)
      end

      let_it_be_with_refind(:extra_dep_part) do
        create(:dependency_list_export_part,
          dependency_list_export: create(:dependency_list_export, project: nil, group: group, organization: nil),
          organization: old_organization)
      end

      let_it_be_with_refind(:extra_dep_part2) do
        create(:dependency_list_export_part,
          dependency_list_export: create(:dependency_list_export, project: project, organization: nil),
          organization: old_organization)
      end

      let_it_be_with_refind(:extra_dep_part3) do
        create(:dependency_list_export_part,
          dependency_list_export: create(:dependency_list_export, project: nil, group: subgroup, organization: nil),
          organization: old_organization)
      end

      let_it_be_with_refind(:extra_vuln_part) do
        create(:vulnerability_export_part,
          vulnerability_export: create(:vulnerability_export, :group, group: group, organization: old_organization),
          organization: old_organization)
      end

      let_it_be_with_refind(:extra_vuln_part2) do
        create(:vulnerability_export_part,
          vulnerability_export: create(:vulnerability_export, project: project, organization: old_organization),
          organization: old_organization)
      end

      let_it_be_with_refind(:extra_vuln_part3) do
        create(:vulnerability_export_part,
          vulnerability_export: create(:vulnerability_export, :group, group: subgroup, organization: old_organization),
          organization: old_organization)
      end

      let(:execute_service) { service.execute }
      let(:expected_batch_queries) do
        {
          'vulnerability_exports' => 3,
          'dependency_list_export_parts' => 3,
          'vulnerability_export_parts' => 3
        }
      end

      it 'processes all records across multiple batches' do
        service.execute

        expect(extra_vuln_export.reload.organization_id).to eq(new_organization.id)
        expect(extra_vuln_export2.reload.organization_id).to eq(new_organization.id)
        expect(extra_vuln_export3.reload.organization_id).to eq(new_organization.id)
        expect(extra_dep_part.reload.organization_id).to eq(new_organization.id)
        expect(extra_dep_part2.reload.organization_id).to eq(new_organization.id)
        expect(extra_dep_part3.reload.organization_id).to eq(new_organization.id)
        expect(extra_vuln_part.reload.organization_id).to eq(new_organization.id)
        expect(extra_vuln_part2.reload.organization_id).to eq(new_organization.id)
        expect(extra_vuln_part3.reload.organization_id).to eq(new_organization.id)
      end

      it_behaves_like 'generates batched transfer queries'
    end

    context 'when hierarchy batching is exercised' do
      let_it_be_with_refind(:group_vuln_export) do
        create(:vulnerability_export, :group, group: group, organization: old_organization)
      end

      let_it_be_with_refind(:subgroup_vuln_export) do
        create(:vulnerability_export, :group, group: subgroup, organization: old_organization)
      end

      let_it_be_with_refind(:project_vuln_export) do
        create(:vulnerability_export, project: project, organization: old_organization)
      end

      let_it_be_with_refind(:group_dep_part) do
        create(:dependency_list_export_part,
          dependency_list_export: create(:dependency_list_export, project: nil, group: group, organization: nil),
          organization: old_organization)
      end

      let_it_be_with_refind(:project_dep_part) do
        create(:dependency_list_export_part,
          dependency_list_export: create(:dependency_list_export, project: project, organization: nil),
          organization: old_organization)
      end

      let_it_be_with_refind(:group_vuln_part) do
        create(:vulnerability_export_part,
          vulnerability_export: group_vuln_export,
          organization: old_organization)
      end

      let_it_be_with_refind(:project_vuln_part) do
        create(:vulnerability_export_part,
          vulnerability_export: project_vuln_export,
          organization: old_organization)
      end

      it 'transfers all records across multiple hierarchy batches' do
        service.execute

        expect(group_vuln_export.reload.organization_id).to eq(new_organization.id)
        expect(subgroup_vuln_export.reload.organization_id).to eq(new_organization.id)
        expect(project_vuln_export.reload.organization_id).to eq(new_organization.id)
        expect(group_dep_part.reload.organization_id).to eq(new_organization.id)
        expect(project_dep_part.reload.organization_id).to eq(new_organization.id)
        expect(group_vuln_part.reload.organization_id).to eq(new_organization.id)
        expect(project_vuln_part.reload.organization_id).to eq(new_organization.id)
      end
    end
  end
end
