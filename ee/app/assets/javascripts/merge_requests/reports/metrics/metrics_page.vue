<script>
import MetricsProvider from './metrics_provider.vue';
import MetricsContent from './metrics_content.vue';

export default {
  name: 'MetricsPage',
  components: {
    MetricsProvider,
    MetricsContent,
  },
  props: {
    mr: {
      type: Object,
      required: true,
    },
  },
};
</script>

<template>
  <metrics-provider :mr="mr">
    <metrics-content />
  </metrics-provider>
</template>
