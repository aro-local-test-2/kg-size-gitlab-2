<script>
import emptyStateSvgPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-package-md.svg';
import { GlEmptyState, GlLink, GlSprintf } from '@gitlab/ui';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import {
  VIRTUAL_UPSTREAMS_EMPTY_TITLE,
  VIRTUAL_UPSTREAMS_EMPTY_DESCRIPTION,
  VIRTUAL_UPSTREAMS_DOCS_URL,
} from '../../constants';

export default {
  name: 'ArtifactRegistryUpstreamRepositoriesEmptyState',
  components: {
    GlEmptyState,
    GlLink,
    GlSprintf,
  },
  mixins: [glSlotsMixin],
  i18n: {
    title: VIRTUAL_UPSTREAMS_EMPTY_TITLE,
    description: VIRTUAL_UPSTREAMS_EMPTY_DESCRIPTION,
  },
  helpPath: VIRTUAL_UPSTREAMS_DOCS_URL,
  emptyStateSvgPath,
};
</script>

<template>
  <gl-empty-state
    :svg-path="$options.emptyStateSvgPath"
    :title="$options.i18n.title"
    data-testid="upstream-repositories-empty-state"
  >
    <template #description>
      <gl-sprintf :message="$options.i18n.description">
        <template #link="{ content }">
          <gl-link :href="$options.helpPath">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </template>

    <template v-if="glSlots().actions" #actions>
      <slot name="actions"></slot>
    </template>
  </gl-empty-state>
</template>
