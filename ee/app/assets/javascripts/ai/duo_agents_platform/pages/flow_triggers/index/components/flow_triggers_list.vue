<script>
import FlowTriggerCard from './flow_trigger_card.vue';

export default {
  name: 'FlowTriggersList',
  components: {
    FlowTriggerCard,
  },
  props: {
    aiFlowTriggers: {
      type: Array,
      required: true,
    },
    togglingIds: {
      type: Array,
      required: false,
      default: () => [],
    },
    serviceAccountRoles: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['delete-trigger', 'toggle-trigger'],
  methods: {
    isToggling(id) {
      return this.togglingIds.includes(id);
    },
    roleFor(trigger) {
      return this.serviceAccountRoles[trigger.user?.id] ?? null;
    },
  },
};
</script>

<template>
  <ul class="gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
    <flow-trigger-card
      v-for="trigger in aiFlowTriggers"
      :key="trigger.id"
      :trigger="trigger"
      :is-toggling="isToggling(trigger.id)"
      :service-account-role="roleFor(trigger)"
      @delete="$emit('delete-trigger', $event)"
      @toggle="$emit('toggle-trigger', $event)"
    />
  </ul>
</template>
