<script>
import { GlIcon } from '@gitlab/ui';
import {
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_KIND_VIRTUAL,
} from 'ee/packages_and_registries/artifact_registry/constants';
import {
  formattedCount,
  humanSize,
  isContainerFormat,
  toCount,
} from 'ee/packages_and_registries/artifact_registry/utils';
import { localeDateFormat, newDate } from '~/lib/utils/datetime_utility';
import { n__, s__ } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import AttributedTimestamp from './attributed_timestamp.vue';
import ConnectionSection from './connection_section.vue';

export default {
  name: 'ArtifactRegistryRepositorySidebar',
  components: {
    AttributedTimestamp,
    ConnectionSection,
    GlIcon,
    TimeAgoTooltip,
  },
  props: {
    repository: {
      type: Object,
      required: true,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
    hideStats: {
      type: Boolean,
      required: false,
      default: false,
    },
    upstreamRepositoriesCount: {
      type: Number,
      required: false,
      default: null,
    },
  },
  computed: {
    isVirtual() {
      return this.repository.kind === REPOSITORY_KIND_VIRTUAL;
    },
    showStats() {
      if (this.hideStats) return false;
      if (this.isVirtual) return this.upstreamRepositoriesCount !== null;

      return true;
    },
    stats() {
      if (this.isVirtual) {
        return [
          {
            icon: 'doc-text',
            value: formattedCount(this.upstreamRepositoriesCount),
            label: this.repositoriesLabel,
            testId: 'repository-stat-repositories',
          },
        ];
      }

      const { sizeBytes, downloadsCount, artifactsCount } = this.repository;

      return [
        {
          icon: 'archive',
          value: humanSize(sizeBytes),
          label: this.$options.i18n.size,
          testId: 'repository-stat-size',
        },
        {
          icon: 'download',
          value: formattedCount(downloadsCount),
          label: this.downloadsLabel,
          testId: 'repository-stat-downloads',
        },
        {
          icon: 'package',
          value: formattedCount(artifactsCount),
          label: this.artifactsLabel,
          testId: 'repository-stat-artifacts',
        },
      ];
    },
    downloadsLabel() {
      return n__(
        'ArtifactRegistry|Download',
        'ArtifactRegistry|Downloads',
        toCount(this.repository.downloadsCount),
      );
    },
    repositoriesLabel() {
      return n__(
        'ArtifactRegistry|Repository',
        'ArtifactRegistry|Repositories',
        toCount(this.upstreamRepositoriesCount),
      );
    },
    artifactsLabel() {
      const count = toCount(this.repository.artifactsCount);
      const readsImages = isContainerFormat(this.repository.format);

      if (this.isRemote) {
        return readsImages
          ? n__('ArtifactRegistry|Image cached', 'ArtifactRegistry|Images cached', count)
          : n__('ArtifactRegistry|Package cached', 'ArtifactRegistry|Packages cached', count);
      }

      return readsImages
        ? n__('ArtifactRegistry|Image', 'ArtifactRegistry|Images', count)
        : n__('ArtifactRegistry|Package', 'ArtifactRegistry|Packages', count);
    },
    createdDate() {
      return localeDateFormat.asDate.format(newDate(this.repository.createdAt));
    },
    hasLastUpdate() {
      return Boolean(this.repository.lastUpdatedAt);
    },
    isRemote() {
      return this.repository.kind === REPOSITORY_KIND_REMOTE;
    },
    cachingPeriods() {
      const { cacheValidityHours, metadataCacheValidityHours } = this.repository.settings ?? {};

      return [
        { key: 'artifact', hours: cacheValidityHours },
        { key: 'metadata', hours: metadataCacheValidityHours },
      ]
        .filter(({ hours }) => Number.isFinite(hours))
        .map(({ key, hours }) => ({
          key,
          message:
            key === 'artifact'
              ? n__(
                  'ArtifactRegistry|Artifact: %d hour',
                  'ArtifactRegistry|Artifact: %d hours',
                  hours,
                )
              : n__(
                  'ArtifactRegistry|Metadata: %d hour',
                  'ArtifactRegistry|Metadata: %d hours',
                  hours,
                ),
        }));
    },
    hasCachingPeriods() {
      return this.isRemote && this.cachingPeriods.length > 0;
    },
  },
  i18n: {
    size: s__('ArtifactRegistry|Size'),
    createdOn: s__('ArtifactRegistry|Created on'),
    lastUpdated: s__('ArtifactRegistry|Last updated'),
    cachingPeriod: s__('ArtifactRegistry|Caching period'),
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-5">
    <connection-section
      v-if="isRemote"
      :name="repository.name"
      :settings="repository.settings"
      :permissions="permissions"
    />

    <div
      v-if="showStats"
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="repository-stats"
    >
      <div
        v-for="stat in stats"
        :key="stat.testId"
        class="gl-flex gl-items-center gl-gap-3"
        :data-testid="stat.testId"
      >
        <gl-icon :name="stat.icon" variant="subtle" />
        <span
          ><span class="gl-font-bold">{{ stat.value }}</span> {{ stat.label }}</span
        >
      </div>
    </div>

    <div
      v-if="hasCachingPeriods"
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5"
      data-testid="repository-caching"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.cachingPeriod }}</h2>

      <p
        v-for="period in cachingPeriods"
        :key="period.key"
        class="gl-mb-0 gl-text-subtle"
        :data-testid="`repository-caching-${period.key}`"
      >
        {{ period.message }}
      </p>
    </div>

    <attributed-timestamp
      :title="$options.i18n.createdOn"
      :user="repository.createdBy"
      data-testid="repository-created"
    >
      {{ createdDate }}
    </attributed-timestamp>

    <attributed-timestamp
      v-if="hasLastUpdate"
      :title="$options.i18n.lastUpdated"
      :user="repository.updatedBy"
      data-testid="repository-last-updated"
    >
      <time-ago-tooltip :time="repository.lastUpdatedAt" />
    </attributed-timestamp>
  </div>
</template>
