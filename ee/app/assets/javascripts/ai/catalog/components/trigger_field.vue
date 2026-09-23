<script>
import { GlDisclosureDropdown, GlLink, GlSprintf, GlToggle, GlToastMixin } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import { createAlert } from '~/alert';
import { parseErrorMessage } from '~/lib/utils/error_message';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import ConfirmActionModal from '~/vue_shared/components/confirm_action_modal.vue';
import FlowTriggerEventTokens from 'ee/ai/duo_agents_platform/components/common/flow_trigger_event_tokens.vue';
import updateAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import deleteAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/delete_ai_flow_trigger.mutation.graphql';
import aiCatalogFlowQuery from 'ee/ai/catalog/graphql/queries/ai_catalog_flow.query.graphql';
import {
  FLOW_TRIGGERS_NEW_ROUTE,
  FLOW_TRIGGERS_EDIT_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { canManageAiFlowTriggers } from '../permissions';
import { getRegistryItem } from '../item_type_registry';
import AiCatalogItemField from './ai_catalog_item_field.vue';

export default {
  name: 'TriggerFieldEE',
  components: {
    GlDisclosureDropdown,
    GlLink,
    GlSprintf,
    GlToggle,
    ConfirmActionModal,
    AiCatalogItemField,
    FlowTriggerEventTokens,
  },
  mixins: [glAbilitiesMixin(), GlToastMixin],
  props: {
    item: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      togglingIds: [],
      triggerIdToDelete: null,
    };
  },
  computed: {
    itemRegistry() {
      return getRegistryItem(this.item.itemType);
    },
    flowTriggers() {
      return this.item.configurationForProject?.flowTriggers ?? [];
    },
    itemTypeLabel() {
      return this.itemRegistry.label;
    },
    canManageTriggers() {
      return canManageAiFlowTriggers({ glAbilities: this.glAbilities });
    },
  },
  methods: {
    triggerEditPath(triggerId) {
      return {
        name: FLOW_TRIGGERS_EDIT_ROUTE,
        params: { id: getIdFromGraphQLId(triggerId) },
      };
    },
    dropdownItems(flowTrigger) {
      return [
        {
          text: __('Edit'),
          to: this.triggerEditPath(flowTrigger.id),
        },
        {
          text: __('Delete'),
          extraAttrs: { class: '!gl-text-danger' },
          action: () => {
            this.triggerIdToDelete = flowTrigger.id;
          },
        },
      ];
    },
    isToggling(id) {
      return this.togglingIds.includes(id);
    },
    async toggleTrigger(id, active) {
      this.togglingIds = [...this.togglingIds, id];

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateAiFlowTrigger,
          variables: { input: { id, active } },
        });

        const { errors } = data.aiFlowTriggerUpdate;

        if (errors.length > 0) {
          createAlert({ message: errors.join(' ') });
          return;
        }

        this.$toast.show(
          active
            ? s__('DuoAgentsPlatform|Trigger turned on')
            : s__('DuoAgentsPlatform|Trigger turned off'),
        );
      } catch (error) {
        createAlert({
          message: parseErrorMessage(error, s__('DuoAgentsPlatform|Failed to update trigger.')),
          error,
          captureError: true,
        });
      } finally {
        this.togglingIds = this.togglingIds.filter((togglingId) => togglingId !== id);
      }
    },
    async deleteTrigger() {
      try {
        const { data } = await this.$apollo.mutate({
          mutation: deleteAiFlowTrigger,
          variables: { id: this.triggerIdToDelete },
          refetchQueries: [aiCatalogFlowQuery],
          awaitRefetchQueries: true,
        });

        const { errors } = data.aiFlowTriggerDelete;

        if (errors.length > 0) {
          createAlert({ message: errors.join(' ') });
          return;
        }

        this.$toast.show(s__('DuoAgentsPlatform|Trigger deleted successfully.'));
      } catch (error) {
        createAlert({
          message: parseErrorMessage(error, s__('DuoAgentsPlatform|Failed to delete trigger.')),
          error,
          captureError: true,
        });
      } finally {
        this.triggerIdToDelete = null;
      }
    },
  },
  FLOW_TRIGGERS_NEW_ROUTE,
};
</script>

<template>
  <ai-catalog-item-field :title="s__('DuoAgentsPlatform|Trigger conditions')">
    <div
      v-for="flowTrigger in flowTriggers"
      :key="flowTrigger.id"
      class="gl-mt-3 gl-flex gl-items-center gl-justify-between"
    >
      <flow-trigger-event-tokens :flow-trigger="flowTrigger" />
      <div
        v-if="flowTrigger.id && !item.foundational && canManageTriggers"
        class="gl-flex gl-items-center gl-gap-3 gl-whitespace-nowrap"
      >
        <gl-toggle
          :value="flowTrigger.active"
          :is-loading="isToggling(flowTrigger.id)"
          :label="s__('DuoAgentsPlatform|Trigger active')"
          label-position="hidden"
          data-testid="flow-trigger-active-toggle"
          @change="(active) => toggleTrigger(flowTrigger.id, active)"
        />
        <gl-disclosure-dropdown
          :items="dropdownItems(flowTrigger)"
          :toggle-text="s__('DuoAgentsPlatform|Trigger actions')"
          text-sr-only
          icon="ellipsis_v"
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="flow-trigger-actions-dropdown"
        />
      </div>
    </div>
    <div v-if="!flowTriggers.length" class="gl-text-subtle">
      <gl-sprintf
        v-if="canManageTriggers"
        :message="
          s__(
            'AICatalog|No triggers configured. %{linkStart}Add a trigger%{linkEnd} to make this %{itemType} available.',
          )
        "
      >
        <template #link="{ content }">
          <gl-link :to="{ name: $options.FLOW_TRIGGERS_NEW_ROUTE }">{{ content }}</gl-link>
        </template>
        <template #itemType>{{ itemTypeLabel }}</template>
      </gl-sprintf>
      <template v-else>
        {{ s__('AICatalog|No triggers configured.') }}
      </template>
    </div>
    <confirm-action-modal
      v-if="triggerIdToDelete"
      modal-id="delete-flow-trigger-modal"
      variant="danger"
      :title="s__('DuoAgentsPlatform|Delete trigger')"
      :action-fn="deleteTrigger"
      :action-text="__('Delete')"
      @close="triggerIdToDelete = null"
    >
      {{
        s__(
          'DuoAgentsPlatform|Are you sure you want to delete this trigger? This action cannot be undone.',
        )
      }}
    </confirm-action-modal>
  </ai-catalog-item-field>
</template>
