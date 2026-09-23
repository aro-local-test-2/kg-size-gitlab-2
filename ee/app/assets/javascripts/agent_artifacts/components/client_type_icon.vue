<script>
import { GlAvatar, GlIcon } from '@gitlab/ui';

export default {
  name: 'ClientTypeIcon',
  components: {
    GlAvatar,
    GlIcon,
  },
  props: {
    clientType: {
      type: Object,
      required: true,
    },
  },
};
</script>

<template>
  <gl-icon v-if="clientType.icon" :name="clientType.icon" :size="16" class="gl-shrink-0" />
  <gl-avatar v-else :entity-name="clientType.name" :size="16" class="gl-shrink-0" />
</template>
