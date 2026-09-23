<script>
import {
  GlAvatar,
  GlAvatarLink,
  GlCard,
  GlDisclosureDropdown,
  GlIcon,
  GlLink,
  GlToggle,
  GlTooltipDirective,
} from '@gitlab/ui';
import { __, s__, sprintf } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import FlowTriggerEventTokens from 'ee/ai/duo_agents_platform/components/common/flow_trigger_event_tokens.vue';
import { FLOW_TRIGGERS_EDIT_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';

export default {
  name: 'FlowTriggerCard',
  components: {
    GlAvatar,
    GlAvatarLink,
    GlCard,
    GlDisclosureDropdown,
    GlIcon,
    GlLink,
    GlToggle,
    FlowTriggerEventTokens,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    trigger: {
      type: Object,
      required: true,
    },
    isToggling: {
      type: Boolean,
      required: false,
      default: false,
    },
    serviceAccountRole: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['delete', 'toggle'],
  computed: {
    editRoute() {
      return {
        name: FLOW_TRIGGERS_EDIT_ROUTE,
        params: { id: getIdFromGraphQLId(this.trigger.id) },
      };
    },
    actionItems() {
      return [
        { text: s__('DuoAgentsPlatform|Edit trigger'), to: this.editRoute },
        {
          text: s__('DuoAgentsPlatform|Delete trigger'),
          action: () => this.$emit('delete', this.trigger.id),
          variant: 'danger',
        },
      ];
    },
    // A trigger targets either a config-path file or a configured catalog item. The table
    // showed both in one "Target" column, so the card keeps that single-target idea.
    hasConfigPath() {
      return Boolean(this.trigger.configPath);
    },
    catalogItemName() {
      return this.trigger.aiCatalogItemConsumer?.item?.name ?? null;
    },
    configFileName() {
      return this.trigger.configPath?.split('/').at(-1) ?? '';
    },
    // The name of a role="switch" must stay stable across states (WAI-ARIA switch pattern);
    // GlToggle conveys on/off through aria-checked. escapeParameters=false keeps punctuation
    // in the free-text description from leaking HTML entities into the accessible name.
    statusToggleLabel() {
      return sprintf(
        s__('DuoAgentsPlatform|Turn trigger on or off: %{description}'),
        { description: this.trigger.description },
        false,
      );
    },
  },
  methods: {
    toggleStatus(active) {
      this.$emit('toggle', { id: this.trigger.id, active });
    },
  },
  i18n: {
    moreActions: __('More actions'),
    unknown: s__('DuoAgentsPlatform|Unknown'),
  },
};
</script>

<template>
  <li>
    <gl-card :class="{ 'gl-bg-subtle': !trigger.active }">
      <div class="gl-flex gl-items-start gl-justify-between gl-gap-3">
        <div class="gl-flex gl-min-w-0 gl-grow gl-flex-col gl-gap-2">
          <span class="gl-font-bold gl-text-default" data-testid="flow-trigger-description">
            {{ trigger.description }}
          </span>

          <flow-trigger-event-tokens :flow-trigger="trigger" />

          <span
            class="gl-mt-1 gl-flex gl-flex-wrap gl-items-center gl-gap-x-3 gl-gap-y-2 gl-text-subtle"
          >
            <span
              class="gl-flex gl-min-w-0 gl-items-center gl-gap-2"
              data-testid="flow-trigger-owner"
            >
              <template v-if="trigger.user">
                <gl-avatar-link
                  v-gl-tooltip
                  :href="trigger.user.webPath"
                  :title="trigger.user.username"
                >
                  <gl-avatar
                    :size="24"
                    :src="trigger.user.avatarUrl"
                    :alt="trigger.user.username"
                    class="gl-shrink-0"
                  />
                </gl-avatar-link>
                <span v-if="serviceAccountRole" class="gl-truncate" data-testid="flow-trigger-role">
                  {{ serviceAccountRole }}
                </span>
              </template>
              <span v-else>{{ $options.i18n.unknown }}</span>
            </span>

            <span aria-hidden="true">&middot;</span>

            <gl-link
              v-if="hasConfigPath"
              v-gl-tooltip="trigger.configPath"
              :href="trigger.configUrl"
              class="gl-inline-flex gl-min-w-0 gl-max-w-full gl-items-center gl-gap-2"
              data-testid="flow-trigger-config-path"
            >
              <gl-icon name="doc-text" :size="16" class="gl-shrink-0 gl-text-subtle" />
              <span class="gl-truncate">{{ configFileName }}</span>
            </gl-link>
            <span
              v-else-if="catalogItemName"
              class="gl-flex gl-min-w-0 gl-items-center gl-gap-2"
              data-testid="flow-trigger-catalog-item"
            >
              <gl-icon name="flow-ai" :size="16" class="gl-shrink-0 gl-text-subtle" />
              <span class="gl-truncate">{{ catalogItemName }}</span>
            </span>
            <span v-else class="gl-text-subtle" data-testid="flow-trigger-target-fallback">
              {{ $options.i18n.unknown }}
            </span>
          </span>
        </div>

        <div class="gl-flex gl-shrink-0 gl-items-center gl-gap-3">
          <gl-toggle
            :value="trigger.active"
            :is-loading="isToggling"
            :label="statusToggleLabel"
            label-position="hidden"
            data-testid="flow-trigger-active-toggle"
            @change="toggleStatus"
          />
          <gl-disclosure-dropdown
            :items="actionItems"
            :toggle-text="$options.i18n.moreActions"
            text-sr-only
            icon="ellipsis_v"
            category="tertiary"
            no-caret
            placement="bottom-end"
          />
        </div>
      </div>
    </gl-card>
  </li>
</template>
