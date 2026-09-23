# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTrigger, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:user) { create(:service_account) }

  subject(:flow_trigger) { build(:ai_flow_trigger, project: project) }

  describe 'associations' do
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to belong_to(:group).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:ai_catalog_item_consumer).class_name('Ai::Catalog::ItemConsumer').optional }
  end

  describe 'AUTONOMOUS_EVENT_TYPE_IDS' do
    it 'contains only the scheduled event type' do
      expect(described_class::AUTONOMOUS_EVENT_TYPE_IDS)
        .to contain_exactly(described_class::EVENT_TYPES[:scheduled])
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_types) }
    it { is_expected.to validate_presence_of(:description) }

    it { is_expected.to validate_length_of(:description).is_at_most(255) }
    it { is_expected.to validate_length_of(:config_path).is_at_most(255) }

    it { is_expected.to allow_value(true, false).for(:active) }
    it { is_expected.not_to allow_value(nil).for(:active) }

    describe 'exactly one of project or group' do
      it 'is invalid when both project and group are set' do
        flow_trigger = build(:ai_flow_trigger, project: project, group: create(:group))

        expect(flow_trigger).not_to be_valid
      end

      it 'is invalid when neither project nor group is set' do
        flow_trigger = build(:ai_flow_trigger, project: nil, group: nil)

        expect(flow_trigger).not_to be_valid
      end

      it 'is valid for a group-scoped trigger' do
        flow_trigger = build(:ai_flow_trigger, :for_inheritance_consumer)

        expect(flow_trigger).to be_valid
      end
    end

    describe 'group_trigger_belongs_to_inheritance_consumer' do
      it 'is valid when the group matches an inheritance consumer for the same group' do
        flow_trigger = build(:ai_flow_trigger, :for_inheritance_consumer)

        expect(flow_trigger).to be_valid
      end

      it 'is invalid when the consumer is not an inheritance consumer' do
        group = create(:group)
        consumer = create(:ai_catalog_item_consumer, :parent_item_consumer, group: group)
        flow_trigger = build(:ai_flow_trigger, project: nil, group: group, config_path: nil, user: nil,
          ai_catalog_item_consumer: consumer)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base])
          .to include('A group trigger must belong to an inheritance consumer of the same group')
      end

      it 'is invalid when the consumer belongs to a different group' do
        group = create(:group)
        other_group = create(:group)
        consumer = create(:ai_catalog_item_consumer, :inheritance, group: other_group)
        flow_trigger = build(:ai_flow_trigger, project: nil, group: group, config_path: nil, user: nil,
          ai_catalog_item_consumer: consumer)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base])
          .to include('A group trigger must belong to an inheritance consumer of the same group')
      end
    end

    describe 'filter' do
      it 'validates json_schema when filter changes' do
        flow_trigger.filter = { 'pipeline_hooks' => { 'unexpected' => true } }

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to be_present
      end

      it 'validates size limit when filter changes' do
        flow_trigger.filter = {
          'pipeline_hooks' => { 'rules' => [{ 'field' => 'a', 'operator' => 'eq', 'value' => 'b' * 9000 }] }
        }

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to be_present
      end
    end

    describe 'event_types_are_valid' do
      it 'rejects empty event_types array' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: [])

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:event_types]).to include("can't be blank")
      end

      it 'rejects nil event_types' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: nil)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:event_types]).to include("can't be blank")
      end

      it 'allows valid event_types array' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: [0])

        expect(flow_trigger).to be_valid
      end

      it 'allows the scheduled event type' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [described_class::EVENT_TYPES[:scheduled]])

        expect(flow_trigger).to be_valid
      end
    end

    describe 'scheduled_event_type_available' do
      let(:flow_trigger) do
        build(:ai_flow_trigger, project: project, event_types: [described_class::EVENT_TYPES[:scheduled]])
      end

      it 'is valid when the feature flag is enabled' do
        expect(flow_trigger).to be_valid
      end

      it 'is invalid when the feature flag is disabled' do
        stub_feature_flags(autonomous_service_account_execution: false)

        expect(flow_trigger).to be_invalid
        expect(flow_trigger.errors[:event_types]).to include('scheduled events are not available')
      end

      it 'ignores the feature flag for other event types' do
        stub_feature_flags(autonomous_service_account_execution: false)
        flow_trigger.event_types = [described_class::EVENT_TYPES[:mention]]

        expect(flow_trigger).to be_valid
      end

      context 'when the trigger already has scheduled persisted' do
        let!(:persisted_flow_trigger) do
          create(:ai_flow_trigger, project: project, event_types: [described_class::EVENT_TYPES[:scheduled]])
        end

        it 'allows saving unrelated changes after the flag is disabled' do
          stub_feature_flags(autonomous_service_account_execution: false)

          expect(persisted_flow_trigger.update(active: false)).to be true
        end

        it 'still rejects adding scheduled to a trigger that did not have it before', :aggregate_failures do
          other_trigger = create(:ai_flow_trigger, project: project,
            event_types: [described_class::EVENT_TYPES[:mention]])
          stub_feature_flags(autonomous_service_account_execution: false)

          other_trigger.event_types = [described_class::EVENT_TYPES[:scheduled]]

          expect(other_trigger).to be_invalid
          expect(other_trigger.errors[:event_types]).to include('scheduled events are not available')
        end
      end
    end

    describe 'filter_keys_match_event_types' do
      it 'allows filter keys that match event_types' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: { 'pipeline_hooks' => { 'rules' => [] } })

        expect(flow_trigger).to be_valid
      end

      it 'rejects filter keys that are not present in event_types' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
          filter: { 'pipeline_hooks' => { 'rules' => [] } })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains filters for event types not in event_types: pipeline_hooks'
        )
      end

      it 'allows a blank filter regardless of event_types' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
          filter: {})

        expect(flow_trigger).to be_valid
      end

      where(:non_hash_filter) { [123, 'a string', [1, 2, 3], true] }

      with_them do
        it 'falls through to the JSON schema validator without raising' do
          flow_trigger = build(:ai_flow_trigger,
            project: project,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
            filter: non_hash_filter)

          expect { flow_trigger.valid? }.not_to raise_error
          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include('must be a valid json schema')
        end
      end
    end

    describe 'scheduled filter schema' do
      def scheduled_trigger(config)
        build(:ai_flow_trigger,
          project: project,
          event_types: [described_class::EVENT_TYPES[:scheduled]],
          filter: { 'scheduled' => config })
      end

      it 'allows a full schedule config' do
        trigger = scheduled_trigger(
          'frequency' => 'WEEKLY', 'minute' => 30, 'hour' => 14, 'dayOfWeek' => 3, 'timezone' => 'America/New_York'
        )

        expect(trigger).to be_valid
      end

      it 'allows a config with only a frequency' do
        expect(scheduled_trigger('frequency' => 'HOURLY')).to be_valid
      end

      where(:invalid_config) do
        [
          [{ 'frequency' => 'SOMETIMES' }],
          [{ 'minute' => 30 }],
          [{ 'frequency' => 'DAILY', 'minute' => 60 }],
          [{ 'frequency' => 'DAILY', 'hour' => 24 }],
          [{ 'frequency' => 'WEEKLY', 'dayOfWeek' => 7 }],
          [{ 'frequency' => 'MONTHLY', 'dayOfMonth' => 29 }],
          [{ 'frequency' => 'DAILY', 'unknown' => 'key' }]
        ]
      end

      with_them do
        it 'rejects the config' do
          trigger = scheduled_trigger(invalid_config)

          expect(trigger).not_to be_valid
          expect(trigger.errors[:filter]).to include('must be a valid json schema')
        end
      end
    end

    describe 'filter_action_values_allowed' do
      it 'allows valid merge_request action values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'any',
              'rules' => [
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'approved' },
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'merged' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows the created merge_request action value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'created' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows valid work_item action values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'match' => 'any',
              'rules' => [
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'created' },
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'status_changed' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects a typo in merge_request action value', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'approveed' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for merge_request: approveed. Allowed values are: approved, created, merged'
        )
      end

      it 'rejects invalid work_item action values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'updated' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for work_item: updated. Allowed values are: created, status_changed'
        )
      end

      it 'validates action values inside nested groups', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [
                {
                  'type' => 'group',
                  'match' => 'any',
                  'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'invalid_action' }]
                }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for merge_request: invalid_action. ' \
            'Allowed values are: approved, created, merged'
        )
      end

      it 'validates action values in array form for in operator', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => %w[created invalid_action] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for work_item: invalid_action. Allowed values are: created, status_changed'
        )
      end

      it 'does not add action value errors for event types without an action allowlist' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'failed' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects nil action values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => nil }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "action values for merge_request can't be blank"
        )
      end

      it 'stops collecting action values beyond MAX_DEPTH', :aggregate_failures do
        deeply_nested = { 'field' => 'action', 'operator' => 'eq', 'value' => 'deep_action' }
        Gitlab::FilterEvaluator::MAX_DEPTH.times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'still validates action values at exactly MAX_DEPTH', :aggregate_failures do
        deeply_nested = { 'field' => 'action', 'operator' => 'eq', 'value' => 'invalid_deep_action' }
        (Gitlab::FilterEvaluator::MAX_DEPTH - 1).times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for merge_request: invalid_deep_action. ' \
            'Allowed values are: approved, created, merged'
        )
      end

      it 'allows a blank filter' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {})

        expect(flow_trigger).to be_valid
      end
    end

    describe 'filter_fields_and_values_allowed' do
      it 'allows the filter shape the frontend writes' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'rules' => [
                {
                  'field' => 'object_attributes.status',
                  'operator' => 'in',
                  'value' => %w[running success failed canceled]
                }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows a single valid status value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'failed' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows source rules with a valid pipeline source' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'failed' },
                { 'field' => 'object_attributes.source', 'operator' => 'eq', 'value' => 'merge_request_event' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows merge_request title rules with any value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'merge_request.title', 'operator' => 'not_contains', 'value' => 'Draft:' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows ref rules with any value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.ref', 'operator' => 'eq', 'value' => 'main' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows default_branch rules with true values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.default_branch', 'operator' => 'eq', 'value' => true }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows default_branch rules with false values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.default_branch', 'operator' => 'eq', 'value' => false }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects non-boolean default_branch values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.default_branch', 'operator' => 'eq', 'value' => 'yes' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.default_branch values for pipeline_hooks: yes. ' \
            'Allowed values are: true, false'
        )
      end

      it 'rejects nil values even for fields without a value allowlist', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'merge_request.title', 'operator' => 'eq', 'value' => nil }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "merge_request.title values for pipeline_hooks can't be blank"
        )
      end

      it 'rejects invalid status values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'rejects invalid source values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.source', 'operator' => 'eq', 'value' => 'marge_request_event' }
              ]
            }
          })

        allowed_sources = described_class::ALLOWED_FILTER_FIELDS['pipeline_hooks']['object_attributes.source']

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.source values for pipeline_hooks: marge_request_event. ' \
            "Allowed values are: #{allowed_sources.join(', ')}"
        )
      end

      it 'rejects unknown fields', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.not_a_real_field', 'operator' => 'eq', 'value' => 'main' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid fields for pipeline_hooks: object_attributes.not_a_real_field. ' \
            'Allowed fields are: object_attributes.status, object_attributes.source, ' \
            'object_attributes.ref, object_attributes.default_branch, merge_request.title'
        )
      end

      it 'rejects an invalid field and an invalid value together', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.not_a_real_field', 'operator' => 'eq', 'value' => 'main' },
                { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid fields for pipeline_hooks: object_attributes.not_a_real_field. ' \
            'Allowed fields are: object_attributes.status, object_attributes.source, ' \
            'object_attributes.ref, object_attributes.default_branch, merge_request.title'
        )
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'validates fields and values inside nested groups', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                {
                  'type' => 'group',
                  'match' => 'any',
                  'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }]
                }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'rejects invalid status values in array form for in operator', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'in', 'value' => %w[failed passed] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'rejects empty array values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'in', 'value' => [] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "object_attributes.status values for pipeline_hooks can't be blank"
        )
      end

      it 'rejects blank values inside arrays', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'in', 'value' => ['failed', ''] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "object_attributes.status values for pipeline_hooks can't be blank"
        )
      end

      it 'rejects nil status values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => nil }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "object_attributes.status values for pipeline_hooks can't be blank"
        )
      end

      it 'stops collecting rules beyond MAX_DEPTH' do
        deeply_nested = { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }
        Gitlab::FilterEvaluator::MAX_DEPTH.times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'still validates rules at exactly MAX_DEPTH', :aggregate_failures do
        deeply_nested = { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }
        (Gitlab::FilterEvaluator::MAX_DEPTH - 1).times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'allows a blank filter' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {})

        expect(flow_trigger).to be_valid
      end

      it 'skips validation for event types without a field allowlist' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
          filter: {
            'mention' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'anything', 'operator' => 'eq', 'value' => 'whatever' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'does not add field errors for merge_request action filters' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'approved' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows a work_item filter with a status.name rule' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'status.name', 'operator' => 'in', 'value' => ['In progress', 'Done'] }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows a work_item filter with only an action rule and no status.name rule' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects a work_item filter with an unknown field', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'status.category', 'operator' => 'eq', 'value' => 'started' }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid fields for work_item: status.category. Allowed fields are: action, status.name'
        )
      end

      it 'reports a blank work_item action value once', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => [''] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter].count("action values for work_item can't be blank")).to eq(1)
      end

      it 'rejects a blank status.name value for work_item', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'status.name', 'operator' => 'in', 'value' => ['In progress', ''] }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include("status.name values for work_item can't be blank")
      end
    end

    describe 'user_is_service_account' do
      it 'rejects regular user' do
        regular_user = create(:user)
        flow_trigger = build(:ai_flow_trigger, project: project, user: regular_user)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:user]).to include('user must be a service account')
      end
    end

    describe 'exactly_one_config_source' do
      let_it_be(:item_consumer) do
        create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: create(:ai_catalog_flow))
      end

      context 'when using config_path only' do
        it 'is valid' do
          flow_trigger = build(:ai_flow_trigger, project: project, config_path: 'path/to/config.yml')

          expect(flow_trigger).to be_valid
        end
      end

      context 'when using ai_catalog_item_consumer only' do
        it 'is valid' do
          flow_trigger =
            build(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).to be_valid
        end
      end

      context 'when using both config_path and ai_catalog_item_consumer' do
        it 'is invalid' do
          error_message = 'Exactly one of config_path, ai_catalog_item_consumer must be present'
          flow_trigger = build(:ai_flow_trigger,
            project: project,
            config_path: 'path/to/config.yml',
            ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include(error_message)
        end
      end

      context 'when using neither config_path nor ai_catalog_item_consumer' do
        it 'is invalid' do
          error_message = 'Exactly one of config_path, ai_catalog_item_consumer must be present'
          flow_trigger = build(:ai_flow_trigger, config_path: nil)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include(error_message)
        end
      end
    end

    describe 'supported_events_match_foundational_flow' do
      let_it_be(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: item) }

      context 'when event types and filter keys match supported events' do
        it 'is valid' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
            filter: { 'pipeline_hooks' => { 'match' => 'all', 'rules' => [] } })

          expect(flow_trigger).to be_valid
        end
      end

      context 'when event types are not supported by the foundational flow' do
        it 'is invalid' do
          flow_trigger = build(:ai_flow_trigger,
            project: project,
            config_path: nil,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:event_types]).to include(
            'contains event types not supported by this foundational flow'
          )
        end
      end

      context 'when filter contains unsupported event type keys' do
        it 'is invalid' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
            filter: { 'mention' => { 'match' => 'all', 'rules' => [] } })

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(
            'contains filters for unsupported event types: mention'
          )
        end
      end

      context 'when the foundational flow has no supported_events' do
        let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'code_review/v1') }

        it 'allows any event types and filter keys' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
            filter: { 'mention' => { 'match' => 'all', 'rules' => [] } })

          expect(flow_trigger).to be_valid
        end
      end

      context 'when the foundational flow disallows events' do
        using RSpec::Parameterized::TableSyntax

        where(:foundational_flow_reference) do
          %w[resolve_sast_vulnerability/v1 sast_fp_detection/v1 secrets_fp_detection/v1]
        end

        with_them do
          let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: foundational_flow_reference) }

          it 'is invalid when event_types are present' do
            flow_trigger = build(:ai_flow_trigger,
              :for_catalog_consumer,
              project: project,
              ai_catalog_item_consumer: item_consumer,
              event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:event_types]).to include(
              'contains event types not supported by this foundational flow'
            )
          end
        end
      end

      context 'when the foundational flow reference does not match a defined flow' do
        let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'unknown/v1') }

        it 'allows any event types' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

          expect(flow_trigger).to be_valid
        end
      end

      context 'when the item is not a foundational flow' do
        let(:item) { create(:ai_catalog_flow) }

        it 'allows any event types and filter keys' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

          expect(flow_trigger).to be_valid
        end
      end
    end

    describe 'catalog_item_valid' do
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }

      let(:item) { create(:ai_catalog_flow) }

      context 'when item consumer project does not match the project' do
        let(:project) { create(:project) }

        it 'is invalid' do
          error_message = 'Exactly one of config_path, ai_catalog_item_consumer must be present'
          flow_trigger = build(:ai_flow_trigger, project: project, ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include(error_message)
        end
      end

      context 'when item is not a flow' do
        let(:item) { create(:ai_catalog_agent) }

        it 'is invalid' do
          flow_trigger = build(:ai_flow_trigger, project: project, ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include('ai_catalog_item_consumer is not a flow')
        end
      end
    end

    context 'when ai_catalog_item_consumer is nil' do
      subject(:flow_trigger) do
        build(:ai_flow_trigger, project: project, ai_catalog_item_consumer: nil)
      end

      it { is_expected.to validate_presence_of(:user) }
    end

    context 'when ai_catalog_item_consumer is present' do
      let_it_be(:ai_catalog_item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }

      subject(:flow_trigger) do
        build(
          :ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: ai_catalog_item_consumer
        )
      end

      it { is_expected.to validate_absence_of(:user) }
      it { is_expected.to be_valid }

      context 'when ai_catalog_item_consumer does not have an active service account' do
        let_it_be(:ai_catalog_item_consumer) { create(:ai_catalog_item_consumer, project:) }

        it 'is invalid' do
          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:ai_catalog_item_consumer_id]).to include('must have an active service account')
        end
      end
    end
  end

  describe '#foundational_flow' do
    subject(:foundational_flow) { trigger.foundational_flow }

    context 'when flow trigger has a catalog item consumer with a foundational flow' do
      let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
      end

      it { is_expected.to eq(::Ai::Catalog::FoundationalFlow.fix_pipeline_v1) }
    end

    context 'when flow trigger has no catalog item consumer' do
      let(:trigger) { build(:ai_flow_trigger, project: project, config_path: 'path/to/config.yml') }

      it { is_expected.to be_nil }
    end

    context 'when catalog item has no foundational flow reference' do
      let(:item) { create(:ai_catalog_flow) }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer)
      end

      it { is_expected.to be_nil }
    end
  end

  describe '#foundational_flow_precondition' do
    subject(:foundational_flow) { trigger.foundational_flow_precondition }

    context 'when foundational flow has a precondition' do
      let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
      end

      it { is_expected.to eq(::Ai::Catalog::FoundationalFlow.fix_pipeline_v1.precondition) }
    end

    context 'when there is no foundational flow' do
      let(:trigger) { build(:ai_flow_trigger, project: project, config_path: 'path/to/config.yml') }

      it { is_expected.to be_nil }
    end

    context 'when foundational flow has no precondition' do
      let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'code_review/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer)
      end

      it { is_expected.to be_nil }
    end
  end

  describe 'database constraints' do
    it 'has correct table name' do
      expect(described_class.table_name).to eq('ai_flow_triggers')
    end

    context 'when using loose foreign key on users.id' do
      it_behaves_like 'cleanup by a loose foreign key' do
        let(:lfk_column) { :user_id }
        let!(:model) { create(:ai_flow_trigger, project: project) }
        let!(:parent) { model.user }
      end
    end

    context 'when using loose foreign key on users.id for the autonomous service account' do
      it_behaves_like 'cleanup by a loose foreign key' do
        let(:lfk_column) { :autonomous_service_account_id }
        let!(:model) do
          create(:ai_flow_trigger, :for_catalog_consumer,
            event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
            autonomous_service_account: create(:service_account))
        end

        let!(:parent) { model.autonomous_service_account }
      end
    end

    context 'when using loose foreign key on projects.id' do
      it_behaves_like 'cleanup by a loose foreign key' do
        let!(:model) { create(:ai_flow_trigger, project: project) }
        let!(:parent) { model.project }
      end
    end
  end

  describe 'factory' do
    it 'creates a valid flow trigger' do
      flow_trigger = build(:ai_flow_trigger,
        project: project,
        user: user,
        description: 'Test flow trigger',
        event_types: [0])

      expect(flow_trigger).to be_valid
    end

    it 'can be created and persisted' do
      expect do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          description: 'Test flow trigger',
          event_types: [0])
      end.to change { described_class.count }.by(1)
    end
  end

  describe 'event_types_are_valid validation' do
    it 'allows multiple valid event types' do
      valid_types = Ai::FlowTrigger::EVENT_TYPES.values - Ai::FlowTrigger::AUTONOMOUS_EVENT_TYPE_IDS
      flow_trigger = build(:ai_flow_trigger, project: project, event_types: valid_types)

      expect(flow_trigger).to be_valid
    end

    # The list above drops the autonomous types because they cannot be mixed,
    # not because they are invalid.
    it 'allows an autonomous event type on its own' do
      flow_trigger = build(:ai_flow_trigger, project: project,
        event_types: Ai::FlowTrigger::AUTONOMOUS_EVENT_TYPE_IDS)

      expect(flow_trigger).to be_valid
    end

    it 'rejects invalid event types' do
      flow_trigger = build(:ai_flow_trigger, project: project, event_types: [99])

      expect(flow_trigger).not_to be_valid
      expect(flow_trigger.errors[:event_types]).to include('contains invalid event types: 99')
    end

    it 'rejects mixed valid and invalid event types' do
      flow_trigger = build(:ai_flow_trigger, project: project, event_types: [0, 99, 100])

      expect(flow_trigger).not_to be_valid
      expect(flow_trigger.errors[:event_types]).to include('contains invalid event types: 99, 100')
    end
  end

  describe 'timestamps' do
    let_it_be_with_reload(:flow_trigger) do
      create(:ai_flow_trigger, project: project, user: user, description: 'Test flow trigger')
    end

    it 'sets created_at and updated_at on creation' do
      expect(flow_trigger.created_at).to be_present
      expect(flow_trigger.updated_at).to be_present
    end

    it 'updates updated_at on modification' do
      original_updated_at = flow_trigger.updated_at

      travel_to(1.minute.from_now) do
        flow_trigger.update!(description: 'Updated description')

        expect(flow_trigger.updated_at).to be > original_updated_at
      end
    end
  end

  describe '.registered_for?' do
    let_it_be(:project) { create(:project) }
    let_it_be(:service_account) { create(:service_account) }

    context 'when project_id is nil' do
      it 'returns false' do
        expect(described_class.registered_for?(nil, :work_item)).to be false
      end
    end

    context 'when no flow triggers exist for the project' do
      it 'returns false' do
        expect(described_class.registered_for?(project.id, :work_item)).to be false
      end
    end

    context 'when a flow trigger exists but for a different event type' do
      before do
        create(:ai_flow_trigger, project: project, user: service_account,
          event_types: [described_class::EVENT_TYPES[:mention]])
      end

      it 'returns false' do
        expect(described_class.registered_for?(project.id, :work_item)).to be false
      end
    end

    context 'when a matching flow trigger exists' do
      before do
        create(:ai_flow_trigger, project: project, user: service_account,
          event_types: [described_class::EVENT_TYPES[:work_item]])
      end

      it 'returns true' do
        expect(described_class.registered_for?(project.id, :work_item)).to be true
      end
    end

    context 'when the only matching flow trigger is inactive' do
      before do
        create(:ai_flow_trigger, :inactive, project: project, user: service_account,
          event_types: [described_class::EVENT_TYPES[:work_item]])
      end

      it 'returns false' do
        expect(described_class.registered_for?(project.id, :work_item)).to be false
      end
    end
  end

  describe '.inherited_for_project' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    it "returns none when the project's root ancestor is not a group" do
      personal_project = create(:project)
      consumer = create(:ai_catalog_item_consumer, :inheritance, group: group)
      create(:ai_flow_trigger, project: nil, group: group, config_path: nil, user: nil,
        ai_catalog_item_consumer: consumer)

      expect(described_class.inherited_for_project(personal_project)).to be_empty
    end

    it 'returns triggers for an inheritance consumer of the root group' do
      consumer = create(:ai_catalog_item_consumer, :inheritance, group: group)
      trigger = create(:ai_flow_trigger, project: nil, group: group, config_path: nil, user: nil,
        ai_catalog_item_consumer: consumer)

      expect(described_class.inherited_for_project(project)).to contain_exactly(trigger)
    end

    it 'excludes triggers from a different group' do
      other_group = create(:group)
      other_consumer = create(:ai_catalog_item_consumer, :inheritance, group: other_group)
      create(:ai_flow_trigger, project: nil, group: other_group, config_path: nil, user: nil,
        ai_catalog_item_consumer: other_consumer)

      expect(described_class.inherited_for_project(project)).to be_empty
    end
  end

  describe '.applicable_to_project' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:project_trigger) do
      create(:ai_flow_trigger, project: project, event_types: [described_class::EVENT_TYPES[:mention]])
    end

    let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
    let_it_be(:group_trigger) do
      create(:ai_flow_trigger, project: nil, group: group, config_path: nil, user: nil,
        ai_catalog_item_consumer: inheritance_consumer, event_types: [described_class::EVENT_TYPES[:mention]])
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)
      end

      it "returns only the project's own triggers" do
        result = described_class.applicable_to_project(project, triggered_on: :mention)

        expect(result).to contain_exactly(project_trigger)
      end
    end

    context 'when the feature flag is enabled' do
      it "returns the project's own triggers and the group's inherited trigger" do
        result = described_class.applicable_to_project(project, triggered_on: :mention)

        expect(result).to contain_exactly(project_trigger, group_trigger)
      end
    end

    context 'when by_service_accounts is given' do
      it 'returns only triggers matching those service accounts' do
        result = described_class.applicable_to_project(
          project, triggered_on: :mention, by_service_accounts: [project_trigger.user_id]
        )

        expect(result).to contain_exactly(project_trigger)
      end
    end
  end

  describe '.event_type_from_id' do
    it 'returns the event type symbol for a known id' do
      expect(described_class.event_type_from_id(0)).to eq(:mention)
      expect(described_class.event_type_from_id(1)).to eq(:assign)
      expect(described_class.event_type_from_id(2)).to eq(:assign_reviewer)
      expect(described_class.event_type_from_id(3)).to eq(:pipeline_hooks)
      expect(described_class.event_type_from_id(4)).to eq(:merge_request_ready)
      expect(described_class.event_type_from_id(5)).to eq(:merge_request_code_conflict)
      expect(described_class.event_type_from_id(6)).to eq(:merge_request)
      expect(described_class.event_type_from_id(7)).to eq(:work_item)
      expect(described_class.event_type_from_id(9)).to eq(:scheduled)
    end

    it 'returns nil for an unknown id' do
      expect(described_class.event_type_from_id(99)).to be_nil
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active triggers' do
        active_trigger = create(:ai_flow_trigger, project: project)
        create(:ai_flow_trigger, :inactive, project: project)

        expect(described_class.active).to contain_exactly(active_trigger)
      end
    end

    describe '.with_ids' do
      it 'filters triggers by id' do
        triggers = create_list(:ai_flow_trigger, 3, project: project)

        expect(project.ai_flow_triggers.with_ids([triggers[0].id, triggers[1].id])).to contain_exactly(
          triggers[0], triggers[1]
        )
      end
    end

    describe '.by_item_consumer_ids' do
      let_it_be(:item_consumer1) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }
      let_it_be(:item_consumer2) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }
      let_it_be(:item_consumer3) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }

      let_it_be(:trigger1) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer1)
      end

      let_it_be(:trigger2) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer2)
      end

      let_it_be(:trigger3) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer3)
      end

      let_it_be(:trigger_not_for_consumer) do
        create(:ai_flow_trigger, project: project, ai_catalog_item_consumer: nil, config_path: 'bla')
      end

      it 'returns triggers filtered by item_consumer_ids' do
        expect(described_class.by_item_consumer_ids([item_consumer1.id, item_consumer2.id]))
          .to contain_exactly(trigger1, trigger2)

        expect(described_class.by_item_consumer_ids([item_consumer1.id])).to contain_exactly(trigger1)
        expect(described_class.by_item_consumer_ids([])).to be_empty
        expect(described_class.by_item_consumer_ids(nil)).to contain_exactly(trigger_not_for_consumer)
      end
    end

    describe '.ordered_by_id' do
      let_it_be(:consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }
      let_it_be(:first) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: consumer)
      end

      let_it_be(:second) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
      end

      it 'returns triggers ordered by id ascending' do
        expect(described_class.by_item_consumer_ids([consumer.id]).ordered_by_id).to eq([first, second])
      end
    end

    describe '.by_service_accounts' do
      subject(:by_service_accounts) do
        described_class.by_service_accounts(
          [
            trigger_for_consumer_with_included_service_account.service_account,
            trigger_for_included_service_account.user
          ]
        )
      end

      let_it_be(:trigger_for_included_service_account) do
        create(:ai_flow_trigger, project: project)
      end

      let_it_be(:trigger_for_excluded_service_account) do
        create(:ai_flow_trigger, project: project)
      end

      let_it_be(:trigger_for_consumer_with_included_service_account) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project)
      end

      let_it_be(:trigger_for_consumer_with_excluded_service_account) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project)
      end

      it 'returns the triggers filtered by service_account' do
        expect(by_service_accounts).to contain_exactly(
          trigger_for_included_service_account, trigger_for_consumer_with_included_service_account
        )
      end

      it 'does not use a subquery' do
        expect(by_service_accounts.to_sql).not_to include('IN (SELECT "users"."id" FROM "users"')
      end

      context 'with an autonomous trigger holding a dedicated account' do
        let_it_be(:autonomous_account) { create(:service_account, composite_identity_enforced: false) }
        let_it_be(:autonomous_trigger) do
          create(:ai_flow_trigger, :for_catalog_consumer, project: project,
            event_types: [described_class::EVENT_TYPES[:scheduled]],
            autonomous_service_account: autonomous_account)
        end

        it 'leaves it out, because the account answers no interactive event' do
          expect(described_class.by_service_accounts([autonomous_account])).to be_empty
        end
      end

      context 'when querying for nil as well' do
        subject(:by_service_accounts) do
          described_class.by_service_accounts(
            [
              trigger_for_consumer_with_included_service_account.service_account,
              nil
            ]
          )
        end

        it 'filters out the nils' do
          expect(by_service_accounts).to contain_exactly(trigger_for_consumer_with_included_service_account)
        end
      end

      context 'when passing in a relation' do
        subject(:by_service_accounts) do
          described_class.by_service_accounts(
            User.where(id: [trigger_for_consumer_with_included_service_account.service_account.id])
          )
        end

        it 'uses a subquery to get the results' do
          expect(by_service_accounts.to_sql).to include('IN (SELECT "users"."id" FROM "users"')
          expect(by_service_accounts).to contain_exactly(trigger_for_consumer_with_included_service_account)
        end
      end
    end

    describe '.include_parent_item_consumer' do
      let_it_be(:trigger) { create(:ai_flow_trigger, :for_catalog_consumer, project: project) }

      it 'preloads the association' do
        loaded_trigger = described_class.where(id: [trigger.id]).include_parent_item_consumer.first

        expect(loaded_trigger.association(:parent_item_consumer)).to be_loaded
      end
    end
  end

  describe '.triggered_on' do
    before do
      stub_const("#{described_class}::EVENT_TYPES", {
        mention: 0,
        comment: 1,
        issue_created: 2
      })
    end

    context 'when filtering by mention event type' do
      let_it_be(:mention_trigger) do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          event_types: [0],
          description: 'Mention trigger')
      end

      let_it_be(:multiple_types_trigger) do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          event_types: [0, 1],
          description: 'Multiple types trigger')
      end

      let_it_be(:other_type_trigger) do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          event_types: [1, 2],
          description: 'Other type trigger')
      end

      it 'returns triggers that contain the mention event type' do
        result = described_class.triggered_on(:mention)

        expect(result).to contain_exactly(mention_trigger, multiple_types_trigger)
      end

      it 'returns triggers that contain the comment event type' do
        result = described_class.triggered_on(:comment)

        expect(result).to contain_exactly(multiple_types_trigger, other_type_trigger)
      end
    end
  end

  describe 'autonomous trigger validations' do
    let_it_be(:autonomous_account) { create(:service_account, composite_identity_enforced: false) }

    def autonomous_trigger(**attrs)
      build(:ai_flow_trigger, :for_catalog_consumer,
        event_types: [described_class::EVENT_TYPES[:scheduled]],
        autonomous_service_account: autonomous_account, **attrs)
    end

    it 'accepts an autonomous trigger with a non-composite account' do
      expect(autonomous_trigger).to be_valid
    end

    it 'rejects an autonomous trigger whose account enforces composite identity' do
      trigger = autonomous_trigger(
        autonomous_service_account: create(:service_account, composite_identity_enforced: true)
      )

      expect(trigger).to be_invalid
      expect(trigger.errors[:base])
        .to include('The service account for an autonomous trigger must not have composite identity enforced')
    end

    it 'rejects mixing autonomous and interactive event types' do
      trigger = autonomous_trigger(
        event_types: [described_class::EVENT_TYPES[:scheduled], described_class::EVENT_TYPES[:mention]]
      )

      expect(trigger).to be_invalid
      expect(trigger.errors[:event_types].join)
        .to include('cannot combine autonomous event types (scheduled) with other event types')
    end

    it 'rejects an autonomous service account on a non-autonomous trigger' do
      trigger = autonomous_trigger(event_types: [described_class::EVENT_TYPES[:mention]])

      expect(trigger).to be_invalid
      expect(trigger.errors[:autonomous_service_account]).to include('must be blank')
    end

    it 'reports only the missing event types when they are blank' do
      trigger = autonomous_trigger(event_types: [])

      expect(trigger).to be_invalid
      expect(trigger.errors[:event_types]).to include("can't be blank")
      expect(trigger.errors[:autonomous_service_account]).to be_empty
    end

    it 'rejects a composite account set by id, without the association loaded' do
      account = create(:service_account, composite_identity_enforced: true)
      trigger = build(:ai_flow_trigger, :for_catalog_consumer,
        event_types: [described_class::EVENT_TYPES[:scheduled]],
        autonomous_service_account_id: account.id)

      expect(trigger.association(:autonomous_service_account)).not_to be_loaded
      expect(trigger).to be_invalid
      expect(trigger.errors[:base])
        .to include('The service account for an autonomous trigger must not have composite identity enforced')
    end

    context 'with a config_path trigger, which runs as its user' do
      def config_path_trigger(composite:)
        build(:ai_flow_trigger,
          event_types: [described_class::EVENT_TYPES[:scheduled]],
          user: create(:service_account, composite_identity_enforced: composite))
      end

      it 'accepts a user without composite identity' do
        expect(config_path_trigger(composite: false)).to be_valid
      end

      it 'rejects a user who enforces composite identity' do
        trigger = config_path_trigger(composite: true)

        expect(trigger).to be_invalid
        expect(trigger.errors[:base])
          .to include('The service account for an autonomous trigger must not have composite identity enforced')
      end
    end
  end

  describe '#container' do
    context 'when project is set' do
      let(:flow_trigger) { build(:ai_flow_trigger, project: project) }

      it 'returns the project' do
        expect(flow_trigger.container).to eq(project)
      end
    end

    context 'when group is set' do
      let(:flow_trigger) { build(:ai_flow_trigger, :for_inheritance_consumer) }

      it 'returns the group' do
        expect(flow_trigger.container).to eq(flow_trigger.group)
      end
    end
  end

  describe '#service_account' do
    subject(:service_account) { flow_trigger.service_account }

    context 'when user is set' do
      let(:flow_trigger) { build(:ai_flow_trigger) }

      it { is_expected.to eq(flow_trigger.user).and(be_a_kind_of(User)) }
    end

    context 'when ai_catalog_item_consumer is set' do
      let(:flow_trigger) { build(:ai_flow_trigger, :for_catalog_consumer, project: project) }

      it { is_expected.to eq(flow_trigger.ai_catalog_item_consumer.active_service_account).and(be_a_kind_of(User)) }
    end

    # This case shouldn't happen. The code is written in a way to return nil,
    # so that we don't silently fall back to the user association.
    context 'when ai_catalog_item_consumer and user are set, but there is no active service account' do
      let(:ai_catalog_item_consumer) { build(:ai_catalog_item_consumer) }
      let(:user) { build(:user) }

      let(:flow_trigger) { build(:ai_flow_trigger, user:, project:, ai_catalog_item_consumer:) }

      it { is_expected.to be_nil }
    end

    context 'when the trigger has its own autonomous service account' do
      let(:autonomous_service_account) { build(:service_account) }

      let(:flow_trigger) do
        build(:ai_flow_trigger, :for_catalog_consumer,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          autonomous_service_account: autonomous_service_account)
      end

      it { is_expected.to eq(autonomous_service_account) }
    end

    context 'when ai_catalog_item_consumer has no parent_item_consumer' do
      let_it_be(:consumer_with_no_parent) do
        create(:ai_catalog_item_consumer, :for_flow, project: project, parent_item_consumer: nil)
      end

      let_it_be(:flow_trigger) do
        build(
          :ai_flow_trigger, :for_catalog_consumer,
          project: project, ai_catalog_item_consumer: consumer_with_no_parent
        )
      end

      it { is_expected.to be_nil }
    end
  end

  describe '#service_account_id' do
    subject(:service_account_id) { flow_trigger.service_account_id }

    context 'when user is set' do
      let(:flow_trigger) { create(:ai_flow_trigger) }

      it { is_expected.to eq(flow_trigger.user_id).and(be_an(Integer)) }
    end

    context 'when ai_catalog_item_consumer is set' do
      let(:flow_trigger) { create(:ai_flow_trigger, :for_catalog_consumer) }

      it { is_expected.to eq(flow_trigger.parent_item_consumer.service_account_id).and(be_an(Integer)) }
    end

    context 'when ai_catalog_item_consumer and user are set, but there is no active service account' do
      let(:ai_catalog_item_consumer) { build(:ai_catalog_item_consumer) }
      let(:user) { build(:user) }

      let(:flow_trigger) { build(:ai_flow_trigger, user:, project:, ai_catalog_item_consumer:) }

      it { is_expected.to be_nil }
    end

    context 'when the trigger has its own autonomous service account' do
      let(:autonomous_service_account) { create(:service_account) }

      let(:flow_trigger) do
        build(:ai_flow_trigger, :for_catalog_consumer,
          event_types: [described_class::EVENT_TYPES[:scheduled]],
          autonomous_service_account: autonomous_service_account)
      end

      it 'wins over the consumer shared account' do
        expect(service_account_id).to eq(autonomous_service_account.id)
        expect(service_account_id).not_to eq(flow_trigger.parent_item_consumer&.service_account_id)
      end
    end

    context 'when ai_catalog_item_consumer has no parent_item_consumer' do
      let_it_be(:consumer_with_no_parent) do
        create(:ai_catalog_item_consumer, :for_flow, project: project, parent_item_consumer: nil)
      end

      let_it_be(:flow_trigger) do
        build(
          :ai_flow_trigger, :for_catalog_consumer,
          project: project, ai_catalog_item_consumer: consumer_with_no_parent
        )
      end

      it { is_expected.to be_nil }
    end

    context 'when ai_catalog_item_consumer_id references a record that no longer exists' do
      let(:flow_trigger) do
        build(:ai_flow_trigger, project: project, ai_catalog_item_consumer_id: non_existing_record_id)
      end

      it { is_expected.to be_nil }
    end

    context 'when ai_catalog_item_consumer is an inheritance consumer with its own service account' do
      let(:flow_trigger) { create(:ai_flow_trigger, :for_inheritance_consumer) }

      it { is_expected.to eq(flow_trigger.ai_catalog_item_consumer.service_account_id).and(be_an(Integer)) }
    end
  end

  describe '#autonomous_only?' do
    using RSpec::Parameterized::TableSyntax

    where(:event_types, :autonomous_only) do
      [Ai::FlowTrigger::EVENT_TYPES[:scheduled]]                                         | true
      [Ai::FlowTrigger::EVENT_TYPES[:scheduled], Ai::FlowTrigger::EVENT_TYPES[:mention]] | false
      [Ai::FlowTrigger::EVENT_TYPES[:mention]]                                           | false
      []                                                                                 | false
      nil                                                                                | false
    end

    with_them do
      it 'returns true only when all event types are autonomous' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: event_types)

        expect(flow_trigger.autonomous_only?).to eq(autonomous_only)
      end
    end
  end
end
