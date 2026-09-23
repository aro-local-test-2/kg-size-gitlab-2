<script>
import emptyStateSvgPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-package-md.svg';
import { GlEmptyState } from '@gitlab/ui';
import {
  filesEmptyDescription,
  filesEmptyTitle,
} from 'ee/packages_and_registries/artifact_registry/utils';

export default {
  name: 'ArtifactRegistryFilesEmptyState',
  components: {
    GlEmptyState,
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
  },
  computed: {
    title() {
      return filesEmptyTitle(this.format, this.versionString);
    },
    description() {
      return filesEmptyDescription(this.format);
    },
  },
  emptyStateSvgPath,
};
</script>

<template>
  <gl-empty-state
    :svg-path="$options.emptyStateSvgPath"
    :title="title"
    :description="description"
    data-testid="files-empty-state"
  />
</template>
