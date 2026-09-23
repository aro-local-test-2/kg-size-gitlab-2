<script>
import { GlDrawer } from '@gitlab/ui';
import { s__ } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';

export default {
  name: 'AuditEventDetailsDrawer',
  components: {
    GlDrawer,
  },
  props: {
    event: {
      type: Object,
      required: false,
      default: null,
    },
    open: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['close'],
  computed: {
    drawerHeaderHeight() {
      return getContentWrapperHeight();
    },
    eventDetails() {
      if (!this.event?.details) {
        return {};
      }

      return this.event.details;
    },
    hasDetails() {
      return Object.keys(this.eventDetails).length > 0;
    },
    formattedDetails() {
      return Object.entries(this.eventDetails).map(([key, value]) => ({
        key,
        label: this.humanizeKey(key),
        value: this.formatValue(value),
      }));
    },
    eventAction() {
      return this.event?.action || '';
    },
  },
  methods: {
    humanizeKey(key) {
      return humanize(key);
    },
    formatValue(value) {
      if (value === null || value === undefined) {
        return '-';
      }

      if (typeof value === 'boolean') {
        return value ? s__('AuditLogs|Yes') : s__('AuditLogs|No');
      }

      if (Array.isArray(value)) {
        return value.length > 0 ? value.join(', ') : '-';
      }

      if (typeof value === 'object') {
        return JSON.stringify(value);
      }

      return String(value);
    },
  },
  DRAWER_Z_INDEX,
  i18n: {
    title: s__('AuditLogs|Audit event details'),
    noDetails: s__('AuditLogs|No additional details available for this event.'),
  },
};
</script>

<template>
  <gl-drawer
    :open="open"
    :header-height="drawerHeaderHeight"
    :z-index="$options.DRAWER_Z_INDEX"
    @close="$emit('close')"
  >
    <template #title>
      <h4 class="gl-my-0" data-testid="audit-event-drawer-title">
        {{ $options.i18n.title }}
      </h4>
    </template>
    <template #default>
      <div v-if="event" data-testid="audit-event-drawer-content">
        <div class="gl-mb-5">
          <p class="gl-mb-2 gl-font-bold">{{ s__('AuditLogs|Action') }}</p>
          <p data-testid="audit-event-drawer-action">{{ eventAction }}</p>
        </div>

        <template v-if="hasDetails">
          <div
            v-for="{ key, label, value } in formattedDetails"
            :key="key"
            class="gl-mb-4"
            data-testid="audit-event-detail-item"
          >
            <p class="gl-mb-2 gl-font-bold">{{ label }}</p>
            <p class="gl-break-words">{{ value }}</p>
          </div>
        </template>
        <p v-else class="gl-text-secondary" data-testid="audit-event-no-details">
          {{ $options.i18n.noDetails }}
        </p>
      </div>
    </template>
  </gl-drawer>
</template>
