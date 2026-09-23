<script>
import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import { s__ } from '~/locale';
import FilesEmptyState from './files_empty_state.vue';
import FilesTable from './files_table.vue';

export default {
  name: 'ArtifactRegistryFilesSection',
  components: {
    FilesEmptyState,
    FilesTable,
    GlAlert,
    GlSkeletonLoader,
  },
  props: {
    format: {
      type: String,
      required: true,
    },
    versionString: {
      type: String,
      required: true,
    },
    files: {
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
  },
  computed: {
    isFirstRead() {
      return this.loading && !this.files.length;
    },
    isEmpty() {
      return !this.files.length;
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
  },
};
</script>

<template>
  <gl-skeleton-loader v-if="isFirstRead" :lines="3" data-testid="files-skeleton" />

  <gl-alert v-else-if="hasError" variant="danger" :dismissible="false" data-testid="files-error">
    {{ $options.i18n.unavailable }}
  </gl-alert>

  <files-empty-state v-else-if="isEmpty" :format="format" :version-string="versionString" />

  <files-table v-else :files="files" :format="format" :is-loading="loading" />
</template>
