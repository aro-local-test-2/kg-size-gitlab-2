<script>
import { s__, sprintf } from '~/locale';
import { WINDOW_DAYS } from '../../evaluations';
import StatsBarItem from './stats_bar_item.vue';

export default {
  name: 'StatsBar',
  components: {
    StatsBarItem,
  },
  props: {
    activePolicies: {
      type: Number,
      required: false,
      default: 0,
    },
    recentEvaluations: {
      type: Number,
      required: false,
      default: null,
    },
    recentEvaluationsLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  i18n: {
    activePolicies: s__('PolicyStore|Active policies'),
    recentEvaluations: sprintf(s__('PolicyStore|Evaluations (last %{days} days)'), {
      days: WINDOW_DAYS,
    }),
  },
};
</script>

<template>
  <div class="gl-flex gl-gap-5">
    <stats-bar-item :label="$options.i18n.activePolicies" :value="activePolicies" />
    <stats-bar-item
      :label="$options.i18n.recentEvaluations"
      :value="recentEvaluations"
      :loading="recentEvaluationsLoading"
    />
  </div>
</template>
