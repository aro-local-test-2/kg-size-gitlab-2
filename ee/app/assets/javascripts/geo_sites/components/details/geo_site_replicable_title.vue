<script>
import { GlLink } from '@gitlab/ui';

export default {
  name: 'GeoSiteReplicableTitle',
  components: {
    GlLink,
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
  },
};
</script>

<template>
  <gl-link v-if="item.replicationView" :href="item.replicationView">{{ item.titlePlural }}</gl-link>
  <span v-else>{{ item.titlePlural }}</span>
</template>
