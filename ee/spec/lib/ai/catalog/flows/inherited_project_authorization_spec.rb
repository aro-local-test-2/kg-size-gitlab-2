# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::InheritedProjectAuthorization, feature_category: :ai_abstraction_layer do
  using RSpec::Parameterized::TableSyntax

  let(:initiating_user) { create(:user) }
  let(:group) { create(:group) }
  let(:project) { create(:project, group: group) }
  let(:item) do
    create(
      :ai_catalog_flow,
      :public,
      :with_released_version,
      organization: group.organization,
      foundational_flow_reference: 'developer/v1'
    )
  end

  let(:service_account) do
    create(:service_account, provisioned_by_group: group, composite_identity_enforced: true)
  end

  let!(:parent_consumer) do
    create(:ai_catalog_item_consumer, group: group, item: item, service_account: service_account)
  end

  subject(:authorization) do
    described_class.new(
      project: project,
      item: item,
      parent_consumer: parent_consumer,
      initiating_user: initiating_user
    )
  end

  before do
    project.project_setting.update!(duo_foundational_flows_enabled: true, duo_features_enabled: true)
    create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: item)
    allow(Gitlab::Llm::StageCheck).to receive(:available?).with(project, :foundational_flows).and_return(true)
  end

  it 'authorizes the exact inherited project, item, and parent', :aggregate_failures do
    child_consumer = create(:ai_catalog_item_consumer, project: project, item: item,
      parent_item_consumer: parent_consumer)
    trigger_params = {
      description: "Foundational flow trigger for #{item.name}",
      ai_catalog_item_consumer_id: child_consumer.id,
      event_types: item.foundational_flow.triggers
    }

    expect(authorization).to be_allowed
    expect(authorization.failure_reason).to be_nil
    expect(authorization.item_consumer_failure_reason(
      container: project,
      item: item,
      parent_consumer: parent_consumer
    )).to be_nil
    expect(authorization.authorized_for_trigger?(
      project: project,
      item_consumer: child_consumer,
      params: trigger_params
    )).to be(true)
  end

  it 'refreshes write-boundary authority without taking row locks' do
    child_consumer = create(:ai_catalog_item_consumer, project: project, item: item,
      parent_item_consumer: parent_consumer)
    trigger_params = {
      description: "Foundational flow trigger for #{item.name}",
      ai_catalog_item_consumer_id: child_consumer.id,
      event_types: item.foundational_flow.triggers
    }

    recorder = ActiveRecord::QueryRecorder.new do
      authorization.item_consumer_failure_reason(
        container: project,
        item: item,
        parent_consumer: parent_consumer
      )
      authorization.authorized_for_trigger?(
        project: project,
        item_consumer: child_consumer,
        params: trigger_params
      )
    end

    expect(recorder.log).not_to include(a_string_matching(/FOR UPDATE/i))
  end

  it 'returns a stable reason when the parent consumer is deleted during refresh' do
    authorization
    parent_consumer.delete

    expect(authorization.item_consumer_failure_reason(
      container: project,
      item: item,
      parent_consumer: parent_consumer
    )).to eq(:parent_consumer_missing)
  end

  it 'rejects trigger authorization when the parent consumer is deleted during refresh' do
    child_consumer = create(:ai_catalog_item_consumer, project: project, item: item,
      parent_item_consumer: parent_consumer)
    trigger_params = {
      description: "Foundational flow trigger for #{item.name}",
      ai_catalog_item_consumer_id: child_consumer.id,
      event_types: item.foundational_flow.triggers
    }
    authorization
    parent_consumer.delete

    expect(authorization.authorized_for_trigger?(
      project: project,
      item_consumer: child_consumer,
      params: trigger_params
    )).to be(false)
  end

  it 'uses system audit attribution with initiating and hierarchy context', :aggregate_failures do
    expect(authorization.audit_author).to be_a(Gitlab::Audit::UnauthenticatedAuthor)
    expect(authorization.audit_author.name).to eq('(System)')
    expect(authorization.audit_details).to eq(
      provisioning_source: 'inherited_project',
      initiating_user_id: initiating_user.id,
      parent_item_consumer_id: parent_consumer.id,
      root_group_id: group.id
    )
  end

  context 'with invalid hierarchy state' do
    where(:invalid_state, :expected_reason) do
      :unpersisted_project        | :invalid_project
      :flows_disabled             | :foundational_flows_disabled
      :flows_unavailable          | :foundational_flows_unavailable
      :catalog_provisioning_locked | :catalog_provisioning_disabled
      :custom_item                | :item_not_foundational
      :unavailable_item           | :item_unavailable
      :organization_mismatch      | :organization_mismatch
      :item_not_enabled           | :item_not_enabled
      :missing_parent             | :parent_consumer_missing
      :mismatched_parent          | :parent_consumer_mismatch
      :missing_service_account    | :parent_service_account_missing
      :mismatched_service_account | :parent_service_account_mismatch
    end

    with_them do
      before do
        case invalid_state
        when :unpersisted_project
          allow(project).to receive(:persisted?).and_return(false)
        when :flows_disabled
          project.project_setting.update!(duo_foundational_flows_enabled: false)
        when :flows_unavailable
          allow(Gitlab::Llm::StageCheck).to receive(:available?).with(project, :foundational_flows).and_return(false)
        when :catalog_provisioning_locked
          allow(project).to receive(:duo_features_enabled).and_return(false)
          allow(project.project_setting).to receive(:duo_features_enabled_locked?).and_return(true)
        when :custom_item
          allow(item).to receive(:foundational_flow?).and_return(false)
        when :unavailable_item
          allow(item.foundational_flow).to receive(:available_for?).with(group).and_return(false)
        when :organization_mismatch
          allow(item).to receive(:organization_id).and_return(non_existing_record_id)
        when :item_not_enabled
          allow(project).to receive(:enabled_flow_catalog_item_ids).and_return([])
        when :missing_parent
          allow(authorization).to receive(:parent_consumer).and_return(nil)
        when :mismatched_parent
          other_group = create(:group, organization: group.organization)
          other_service_account = create(:service_account, provisioned_by_group: other_group)
          other_parent = build_stubbed(:ai_catalog_item_consumer, group: other_group, item: item,
            service_account: other_service_account)
          allow(authorization).to receive(:parent_consumer).and_return(other_parent)
        when :missing_service_account
          allow(parent_consumer).to receive(:active_service_account).and_return(nil)
        when :mismatched_service_account
          other_group = create(:group, organization: group.organization)
          other_service_account = create(:service_account, provisioned_by_group: other_group)
          allow(parent_consumer).to receive(:active_service_account).and_return(other_service_account)
        end
      end

      it 'fails closed with a stable reason' do
        expect(authorization.failure_reason).to eq(expected_reason)
      end
    end
  end

  it 'rejects a substituted child consumer' do
    other_project = create(:project, group: group)
    child_consumer = build(:ai_catalog_item_consumer, project: other_project, item: item,
      parent_item_consumer: parent_consumer)

    expect(authorization.authorized_for_trigger?(
      project: project,
      item_consumer: child_consumer,
      params: {}
    )).to be(false)
  end

  it 'returns a stable reason for substituted consumer arguments' do
    other_project = create(:project, group: group)

    expect(authorization.item_consumer_failure_reason(
      container: other_project,
      item: item,
      parent_consumer: parent_consumer
    )).to eq(:authorization_context_mismatch)
  end

  it 'rejects arbitrary trigger parameters for the exact child consumer' do
    child_consumer = create(:ai_catalog_item_consumer, project: project, item: item,
      parent_item_consumer: parent_consumer)

    expect(authorization.authorized_for_trigger?(
      project: project,
      item_consumer: child_consumer,
      params: {
        description: 'Arbitrary trigger',
        ai_catalog_item_consumer_id: child_consumer.id,
        event_types: [non_existing_record_id]
      }
    )).to be(false)
  end

  it 'authorizes computed triggers while Duo features are disabled but unlocked' do
    project.project_setting.update!(duo_features_enabled: false)
    child_consumer = create(:ai_catalog_item_consumer, project: project, item: item,
      parent_item_consumer: parent_consumer)
    trigger_params = {
      description: "Foundational flow trigger for #{item.name}",
      ai_catalog_item_consumer_id: child_consumer.id,
      event_types: item.foundational_flow.triggers
    }

    expect(authorization.item_consumer_failure_reason(
      container: project,
      item: item,
      parent_consumer: parent_consumer
    )).to be_nil
    expect(authorization.authorized_for_trigger?(
      project: project,
      item_consumer: child_consumer,
      params: trigger_params
    )).to be(true)
  end
end
