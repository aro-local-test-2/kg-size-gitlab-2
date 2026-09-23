<script>
import { GlBadge, GlLoadingIcon, GlTable, GlTruncate } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  MANIFEST_DETAIL_ROUTE_NAME,
  MANIFEST_KIND_LABELS,
  REFERRERS_TABLE_FIELDS,
} from '../../../constants';
import { manifestType, shortDigest } from '../../../utils';

export default {
  name: 'ArtifactRegistryReferrersTable',
  components: {
    GlBadge,
    GlLoadingIcon,
    GlTable,
    GlTruncate,
    TimeAgoTooltip,
  },
  props: {
    referrers: {
      type: Array,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    artifactId: {
      type: String,
      required: true,
    },
    subjectDigest: {
      type: String,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    rows() {
      return this.referrers.map((referrer) => {
        const shortened = shortDigest(referrer.digest);

        // `subjectDigest` is null on the list type until the referrer-inclusion argument lands.
        const { kind } = manifestType({
          ...referrer,
          subjectDigest: referrer.subjectDigest || this.subjectDigest,
        });

        return {
          ...referrer,
          shortened,
          typeLabel: referrer.artifactType || referrer.mediaType,
          kindLabel: MANIFEST_KIND_LABELS[kind],
          linkLabel: sprintf(this.$options.i18n.manifest, { digest: shortened }),
          route: {
            name: MANIFEST_DETAIL_ROUTE_NAME,
            params: { id: this.name, artifactId: this.artifactId, digest: referrer.digest },
          },
        };
      });
    },
  },
  fields: REFERRERS_TABLE_FIELDS,
  i18n: {
    manifest: s__('ArtifactRegistry|Manifest %{digest}'),
    noReferrers: s__('ArtifactRegistry|Nothing refers to this manifest.'),
  },
};
</script>

<template>
  <!-- Fixed layout: sized to its content, the table grows past the tab panel and overlaps the
       sidebar, because a media type is long. -->
  <gl-table
    :busy="isLoading"
    :fields="$options.fields"
    :items="rows"
    :empty-text="$options.i18n.noReferrers"
    show-empty
    stacked="md"
    table-class="gl-table-fixed"
  >
    <template #table-busy>
      <gl-loading-icon v-if="isLoading" size="sm" class="gl-my-5" />
    </template>

    <template #cell(digest)="{ item }">
      <span class="gl-flex gl-items-center" data-testid="referrer-digest">
        <router-link
          :to="item.route"
          :aria-label="item.linkLabel"
          class="gl-font-monospace gl-font-semibold"
          >{{ item.shortened }}</router-link
        >
      </span>
    </template>

    <template #cell(artifactType)="{ item }">
      <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-2" data-testid="referrer-type">
        <gl-truncate :text="item.typeLabel" class="gl-min-w-0" position="middle" with-tooltip />
        <gl-badge data-testid="referrer-kind">{{ item.kindLabel }}</gl-badge>
      </span>
    </template>

    <!-- Guarded because TimeAgoTooltip reads a null time as "just now", and the contract makes
         the timestamp nullable. -->
    <template #cell(createdAt)="{ item }">
      <time-ago-tooltip
        v-if="item.createdAt"
        :time="item.createdAt"
        data-testid="referrer-published"
      />
    </template>
  </gl-table>
</template>
