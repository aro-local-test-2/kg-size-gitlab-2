<script>
import emptyStateSvgPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-package-md.svg';
import { GlButton, GlEmptyState } from '@gitlab/ui';
import { s__ } from '~/locale';
import { REPOSITORY_DETAIL_ROUTE_NAME } from '../../constants';
import { isContainerFormat } from '../../utils';

export default {
  name: 'ArtifactRegistryVersionListEmptyState',
  components: {
    GlButton,
    GlEmptyState,
  },
  props: {
    format: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
  },
  computed: {
    rendersManifests() {
      return isContainerFormat(this.format);
    },
    title() {
      const { versionsTitle, manifestsTitle } = this.$options.i18n;

      return this.rendersManifests ? manifestsTitle : versionsTitle;
    },
    description() {
      const { versionsDescription, manifestsDescription } = this.$options.i18n;

      return this.rendersManifests ? manifestsDescription : versionsDescription;
    },
    repositoryRoute() {
      return { name: REPOSITORY_DETAIL_ROUTE_NAME, params: { id: this.name } };
    },
  },
  i18n: {
    versionsTitle: s__('ArtifactRegistry|There are no versions of this package yet'),
    manifestsTitle: s__('ArtifactRegistry|There are no manifests in this image yet'),
    versionsDescription: s__('ArtifactRegistry|Publish your first version to get started.'),
    manifestsDescription: s__('ArtifactRegistry|Push your first manifest to get started.'),
    goToRepository: s__('ArtifactRegistry|Go to repository'),
  },
  emptyStateSvgPath,
};
</script>

<template>
  <gl-empty-state
    :svg-path="$options.emptyStateSvgPath"
    :title="title"
    :description="description"
    data-testid="version-list-empty-state"
  >
    <template #actions>
      <gl-button :to="repositoryRoute" variant="confirm" data-testid="go-to-repository">
        {{ $options.i18n.goToRepository }}
      </gl-button>
    </template>
  </gl-empty-state>
</template>
