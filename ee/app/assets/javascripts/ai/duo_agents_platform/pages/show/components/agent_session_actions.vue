<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { s__ } from '~/locale';
import { AGENT_PLATFORM_CANCELABLE_STATUSES } from 'ee/ai/duo_agents_platform/constants';

export default {
  name: 'AgentSessionActions',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    status: {
      type: String,
      required: false,
      default: null,
    },
    canUpdateWorkflow: {
      type: Boolean,
      required: false,
      default: false,
    },
    isSidePanel: {
      type: Boolean,
      required: false,
      default: false,
    },
    showDetailsToggle: {
      type: Boolean,
      required: false,
      default: false,
    },
    detailsExpanded: {
      type: Boolean,
      required: false,
      default: true,
    },
    detailsDrawerId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['cancel-session', 'toggle-details'],
  computed: {
    canCancelSession() {
      return AGENT_PLATFORM_CANCELABLE_STATUSES.includes(this.status);
    },
    cancelSessionLabel() {
      return s__('DuoAgentsPlatform|Cancel session');
    },
    tooltip() {
      if (!this.canUpdateWorkflow) {
        return s__('DuoAgentsPlatform|You do not have permission to cancel this session.');
      }
      return this.isSidePanel ? this.cancelSessionLabel : '';
    },
  },
};
</script>
<template>
  <div class="gl-flex gl-items-center gl-gap-3">
    <span
      v-if="canCancelSession"
      v-gl-tooltip
      :title="tooltip"
      data-testid="cancel-session-wrapper"
    >
      <gl-button
        v-if="isSidePanel"
        icon="canceled-circle"
        size="small"
        :aria-label="cancelSessionLabel"
        :disabled="!canUpdateWorkflow"
        data-testid="cancel-session-icon-button"
        @click="$emit('cancel-session')"
      />
      <gl-button
        v-else
        category="secondary"
        variant="danger"
        :disabled="!canUpdateWorkflow"
        data-testid="cancel-session-button"
        @click="$emit('cancel-session')"
      >
        {{ cancelSessionLabel }}
      </gl-button>
    </span>
    <gl-button
      v-if="showDetailsToggle"
      v-gl-tooltip
      icon="chevron-double-lg-left"
      :title="s__('DuoAgentPlatform|Session details')"
      :aria-label="s__('DuoAgentPlatform|Session details')"
      :aria-expanded="detailsExpanded.toString()"
      :aria-controls="detailsDrawerId"
      data-testid="toggle-session-details-button"
      @click="$emit('toggle-details')"
    />
  </div>
</template>
