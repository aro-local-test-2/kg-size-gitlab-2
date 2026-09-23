<script>
import { GlBadge, GlIcon, GlLink, GlSprintf } from '@gitlab/ui';
import {
  REPOSITORY_DETAIL_ROUTE_NAME,
  REPOSITORY_KIND_LABELS,
  REPOSITORY_KIND_REMOTE,
} from 'ee/packages_and_registries/artifact_registry/constants';
import { humanSize } from 'ee/packages_and_registries/artifact_registry/utils';
import { localeDateFormat, newDate } from '~/lib/utils/datetime_utility';
import { s__ } from '~/locale';
import { hasSource, sourceOf } from '../version_source';

export default {
  name: 'ArtifactRegistryVersionSidebar',
  components: {
    GlBadge,
    GlIcon,
    GlLink,
    GlSprintf,
  },
  props: {
    repository: {
      type: Object,
      required: true,
    },
    version: {
      type: Object,
      required: true,
    },
  },
  computed: {
    kindLabel() {
      return REPOSITORY_KIND_LABELS[this.repository.kind];
    },
    repositoryRoute() {
      return { name: REPOSITORY_DETAIL_ROUTE_NAME, params: { id: this.repository.name } };
    },
    // A remote repository never writes a size, so its stored zero is a placeholder, not a fact.
    // A hosted zero is real, so it still renders as "0 B".
    rendersSize() {
      const { sizeBytes } = this.version;

      return (
        sizeBytes != null &&
        Number.isFinite(Number(sizeBytes)) &&
        this.repository.kind !== REPOSITORY_KIND_REMOTE
      );
    },
    size() {
      return humanSize(this.version.sizeBytes);
    },
    publishedDate() {
      const createdAt = newDate(this.version.createdAt);

      return createdAt ? localeDateFormat.asDate.format(createdAt) : null;
    },
    source() {
      return sourceOf(this.version);
    },
    // A cached remote row nulls every attribution field, so no attribution reads as unknown
    // rather than as the bare "Published" line versions_table.vue falls back to.
    hasAttribution() {
      return hasSource(this.version);
    },
  },
  i18n: {
    repository: s__('ArtifactRegistry|Repository'),
    size: s__('ArtifactRegistry|Size'),
    published: s__('ArtifactRegistry|Published'),
    source: s__('ArtifactRegistry|Source'),
    unknown: s__('ArtifactRegistry|Unknown'),
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-5">
    <div
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="version-repository"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.repository }}</h2>

      <p class="gl-mb-0 gl-flex gl-flex-wrap gl-items-center gl-gap-2">
        <router-link :to="repositoryRoute" class="gl-wrap-anywhere">{{
          repository.name
        }}</router-link>
        <gl-badge>{{ kindLabel }}</gl-badge>
      </p>
    </div>

    <div
      v-if="rendersSize"
      class="gl-border-t gl-flex gl-items-center gl-gap-4 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="version-size"
    >
      <gl-icon name="archive" variant="subtle" />
      <span class="gl-font-bold">{{ size }}</span>
      <span class="gl-text-subtle">{{ $options.i18n.size }}</span>
    </div>

    <div
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="version-published"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.published }}</h2>

      <p v-if="publishedDate" class="gl-mb-0">{{ publishedDate }}</p>

      <p v-else class="gl-mb-0 gl-text-subtle" data-testid="version-published-unknown">
        {{ $options.i18n.unknown }}
      </p>
    </div>

    <div
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="version-source"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.source }}</h2>

      <template v-if="hasAttribution">
        <span v-if="source.sha" class="gl-flex gl-items-center gl-gap-2">
          <gl-icon name="commit" />
          <gl-link
            v-if="source.commitPath"
            :href="source.commitPath"
            class="gl-font-monospace"
            data-testid="version-commit"
            >{{ source.sha }}</gl-link
          >
          <span v-else class="gl-font-monospace" data-testid="version-commit">{{
            source.sha
          }}</span>
        </span>

        <span v-else data-testid="version-published-by">
          <gl-sprintf :message="source.originMessage">
            <template v-if="source.author" #author>{{ source.author }}</template>
          </gl-sprintf>
        </span>

        <span
          v-if="source.attributionMessage"
          class="gl-flex gl-flex-wrap gl-items-center gl-gap-1"
          data-testid="version-attribution"
        >
          <gl-sprintf :message="source.attributionMessage">
            <template v-if="source.project" #project>
              <gl-link :href="source.project.webPath">{{ source.project.name }}</gl-link>
            </template>
            <template v-if="source.author" #author>{{ source.author }}</template>
          </gl-sprintf>
        </span>
      </template>

      <span v-else class="gl-text-subtle" data-testid="version-source-unknown">{{
        $options.i18n.unknown
      }}</span>
    </div>
  </div>
</template>
