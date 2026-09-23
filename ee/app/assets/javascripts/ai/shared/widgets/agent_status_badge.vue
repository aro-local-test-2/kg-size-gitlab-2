<script>
import { GlBadge } from '@gitlab/ui';
import { getAgentStatusBadge } from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'AgentStatusBadge',
  components: {
    GlBadge,
  },
  props: {
    status: {
      required: true,
      type: String,
    },
    humanStatus: {
      required: true,
      type: String,
    },
  },
  computed: {
    badge() {
      return getAgentStatusBadge(this.status);
    },
  },
};
</script>

<template>
  <gl-badge :icon="badge.icon" :variant="badge.variant" class="gl-self-start">
    {{ humanStatus }}
  </gl-badge>
</template>
