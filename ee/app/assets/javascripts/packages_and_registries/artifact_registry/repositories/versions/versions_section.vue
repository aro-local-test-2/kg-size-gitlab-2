<script>
import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import { s__ } from '~/locale';
import { isContainerFormat } from '../../utils';
import ManifestsTable from './manifests_table.vue';
import VersionListEmptyState from './version_list_empty_state.vue';
import VersionsTable from './versions_table.vue';

export default {
  name: 'ArtifactRegistryVersionsSection',
  components: {
    GlAlert,
    GlSkeletonLoader,
    ManifestsTable,
    VersionListEmptyState,
    VersionsTable,
  },
  props: {
    format: {
      type: String,
      required: true,
    },
    artifact: {
      type: Object,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    rows: {
      type: Array,
      required: false,
      default: () => [],
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    hasError: {
      type: Boolean,
      required: false,
      default: false,
    },
    hiddenColumns: {
      type: Array,
      required: false,
      default: () => [],
    },
    sort: {
      type: Object,
      required: true,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['sort-changed'],
  computed: {
    rendersManifests() {
      return isContainerFormat(this.format);
    },
    // A re-read for a new sort or page keeps the table mounted and marks it busy, so only
    // the first read, which has no rows to keep, stands the skeleton in for the table.
    isFirstRead() {
      return this.loading && !this.rows.length;
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
  },
};
</script>

<template>
  <gl-skeleton-loader v-if="isFirstRead" :lines="3" data-testid="versions-skeleton" />

  <gl-alert v-else-if="hasError" variant="danger" :dismissible="false" data-testid="versions-error">
    {{ $options.i18n.unavailable }}
  </gl-alert>

  <version-list-empty-state v-else-if="!rows.length" :format="format" :name="name" />

  <manifests-table
    v-else-if="rendersManifests"
    :manifests="rows"
    :format="format"
    :artifact="artifact"
    :name="name"
    :image-id="artifact.id"
    :hidden-columns="hiddenColumns"
    :sort="sort"
    :is-loading="loading"
    :permissions="permissions"
    @sort-changed="$emit('sort-changed', $event)"
  />

  <versions-table
    v-else
    :versions="rows"
    :format="format"
    :artifact="artifact"
    :name="name"
    :hidden-columns="hiddenColumns"
    :sort="sort"
    :is-loading="loading"
    :permissions="permissions"
    @sort-changed="$emit('sort-changed', $event)"
  />
</template>
