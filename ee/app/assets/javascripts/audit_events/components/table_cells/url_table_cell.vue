<script>
import { s__ } from '~/locale';

const REMOVED_TEXT = s__('AuditLogs|(removed)');

export default {
  name: 'UrlTableCell',
  props: {
    url: {
      type: String,
      required: false,
      default: '',
    },
    name: {
      type: String,
      required: true,
    },
    removed: {
      type: Boolean,
      required: false,
      default: null,
    },
  },
  REMOVED_TEXT,
  computed: {
    showRemovedHint() {
      return this.removed === null ? !this.url : this.removed;
    },
  },
};
</script>

<template>
  <a v-if="url" :href="url">{{ name }}</a>

  <span v-else data-testid="unlinked-name">
    {{ name }} <small v-if="showRemovedHint">{{ $options.REMOVED_TEXT }}</small>
  </span>
</template>
