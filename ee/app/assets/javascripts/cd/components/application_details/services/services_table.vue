<script>
import { GlTableLite } from '@gitlab/ui';
import { s__ } from '~/locale';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import { TH_CLASS, TD_CLASS, ROW_SELECTED_CLASS } from 'ee/cd/constants';
import { buildRowClass } from 'ee/cd/utils';

const NAME_FIELD = {
  key: 'name',
  label: s__('ContinuousDeployment|Service'),
  tdClass: TD_CLASS,
  thClass: TH_CLASS,
};
const DEPLOYED_FIELD = {
  key: 'lastDeployedAt',
  label: s__('ContinuousDeployment|Deployed'),
  tdClass: `${TD_CLASS} gl-whitespace-nowrap gl-text-right !gl-text-secondary`,
  thClass: `${TH_CLASS} gl-whitespace-nowrap gl-text-right`,
};

export default {
  name: 'ServicesTable',
  components: {
    GlTableLite,
    TimeAgo,
  },
  props: {
    services: {
      type: Array,
      required: true,
    },
    selectedId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['select'],
  computed: {
    serviceRows() {
      return this.services.map((service) => ({
        id: service.id,
        name: service.name,
        lastDeployedAt: service.lastDeployedAt,
      }));
    },
    fields() {
      return [NAME_FIELD, DEPLOYED_FIELD];
    },
  },
  methods: {
    rowClass(item) {
      return buildRowClass(item?.id, [[this.selectedId, ROW_SELECTED_CLASS]]);
    },
  },
};
</script>

<template>
  <gl-table-lite
    :items="serviceRows"
    :fields="fields"
    :tbody-tr-class="rowClass"
    stacked="sm"
    borderless
    data-testid="services-table"
    @row-clicked="$emit('select', $event)"
  >
    <template #cell(lastDeployedAt)="{ item }">
      <time-ago v-if="item.lastDeployedAt" :time="item.lastDeployedAt" />
    </template>
  </gl-table-lite>
</template>
