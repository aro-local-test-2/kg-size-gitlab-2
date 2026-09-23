<script>
import { GlCollapsibleListbox, GlFormGroup } from '@gitlab/ui';
import { isEqual, omit, uniqBy, uniqueId } from 'lodash-es';
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import { getStatuses } from 'ee/work_items/utils';
import {
  FILTER_FIELD_ACTION,
  FILTER_FIELD_WORK_ITEM_STATUS_NAME,
  FILTER_OPERATOR_IN,
  FLOW_TRIGGER_TYPE_WORK_ITEM,
  WORK_ITEM_ACTION_STATUS_CHANGED,
  WORK_ITEM_ACTIONS,
} from 'ee/ai/duo_agents_platform/constants';
import {
  parseWorkItemActionFilter,
  parseWorkItemStatusNamesFilter,
} from 'ee/ai/duo_agents_platform/utils';
import EventActionsConfiguration from './event_actions_configuration.vue';

const SCOPE = FLOW_TRIGGER_TYPE_WORK_ITEM.value;

const hasStatusChangedAction = (filter) =>
  parseWorkItemActionFilter(filter).includes(WORK_ITEM_ACTION_STATUS_CHANGED.value);

// Rules in a scope are AND-ed, so a status rule next to a "created" action would block
// creation events (they carry no status). Only allow it when "Status changed" is the sole action.
const allowsStatusFilter = (filter) =>
  isEqual(parseWorkItemActionFilter(filter), [WORK_ITEM_ACTION_STATUS_CHANGED.value]);

export default {
  name: 'WorkItemEventsConfiguration',
  components: {
    EventActionsConfiguration,
    GlCollapsibleListbox,
    GlFormGroup,
  },
  inject: ['projectPath'],
  props: {
    value: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    invalidFeedback: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
  apollo: {
    workItemTypes: {
      query: namespaceWorkItemTypesQuery,
      variables() {
        return { fullPath: this.projectPath };
      },
      update(data) {
        this.statusesFailedToLoad = false;
        return data.namespace?.workItemTypes?.nodes ?? [];
      },
      skip() {
        return !this.showStatusListbox;
      },
      error(error) {
        this.statusesFailedToLoad = true;
        createAlert({
          message: s__(
            'DuoAgentsPlatform|Something went wrong while fetching work item statuses. Please try again.',
          ),
          captureError: true,
          error,
        });
      },
    },
  },
  data() {
    return {
      workItemTypes: [],
      statusesFailedToLoad: false,
      statusToggleId: uniqueId('work-item-status-toggle-'),
    };
  },
  computed: {
    showStatusListbox() {
      return hasStatusChangedAction(this.value);
    },
    statusFilterEnabled() {
      return allowsStatusFilter(this.value);
    },
    isLoadingStatuses() {
      return this.$apollo.queries.workItemTypes.loading;
    },
    // Statuses are defined per work item type; the trigger matches by name across all types.
    statusOptions() {
      return uniqBy(getStatuses(this.workItemTypes), 'name').map(({ name }) => ({
        value: name,
        text: name,
      }));
    },
    selectedStatusNames() {
      return parseWorkItemStatusNamesFilter(this.value);
    },
    // Undefined falls back to the listbox's own "No results found" text.
    noResultsText() {
      return this.statusesFailedToLoad
        ? s__('DuoAgentsPlatform|Could not load statuses. Refresh the page to try again.')
        : undefined;
    },
    toggleText() {
      return this.selectedStatusNames.length
        ? this.selectedStatusNames.join(', ')
        : s__('DuoAgentsPlatform|Any status');
    },
    statusDescription() {
      return this.statusFilterEnabled
        ? s__(
            'DuoAgentsPlatform|Run only when the work item changes to one of the selected statuses. Leave empty to run on any status change.',
          )
        : s__('DuoAgentsPlatform|Available only when Status changed is the only selected action.');
    },
  },
  methods: {
    onActionsInput(filter) {
      this.$emit('input', allowsStatusFilter(filter) ? filter : this.withStatusNames(filter, []));
    },
    onStatusSelect(statusNames) {
      this.$emit('input', this.withStatusNames(this.value, statusNames));
    },
    withStatusNames(filter, statusNames) {
      // This form owns every status.name rule; API-authored variants are replaced, not AND-ed.
      const rules = (filter?.[SCOPE]?.rules ?? []).filter(
        (rule) => rule.field !== FILTER_FIELD_WORK_ITEM_STATUS_NAME,
      );

      if (statusNames.length) {
        rules.push({
          field: FILTER_FIELD_WORK_ITEM_STATUS_NAME,
          operator: FILTER_OPERATOR_IN,
          value: statusNames,
        });
      }

      if (!rules.length) return omit(filter, SCOPE);

      return { ...filter, [SCOPE]: { ...filter[SCOPE], rules } };
    },
  },
  WORK_ITEM_ACTIONS,
  FILTER_FIELD_ACTION,
  SCOPE,
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-4">
    <event-actions-configuration
      :scope="$options.SCOPE"
      :field="$options.FILTER_FIELD_ACTION"
      :actions="$options.WORK_ITEM_ACTIONS"
      :listbox-header-text="s__('DuoAgentsPlatform|Select work item actions')"
      :value="value"
      :invalid-feedback="invalidFeedback"
      @input="onActionsInput"
    />

    <gl-form-group
      v-if="showStatusListbox"
      :label="s__('DuoAgentsPlatform|Status')"
      :label-for="statusToggleId"
      :description="statusDescription"
      class="!gl-mb-0"
      data-testid="status-form-group"
    >
      <gl-collapsible-listbox
        :toggle-id="statusToggleId"
        :items="statusOptions"
        :selected="selectedStatusNames"
        :toggle-text="toggleText"
        :header-text="s__('DuoAgentsPlatform|Select statuses')"
        :loading="isLoadingStatuses"
        :no-results-text="noResultsText"
        :disabled="!statusFilterEnabled"
        multiple
        block
        data-testid="status-listbox"
        @select="onStatusSelect"
      />
    </gl-form-group>
  </div>
</template>
