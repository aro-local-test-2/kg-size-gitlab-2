<script>
import {
  GlAlert,
  GlBadge,
  GlPopover,
  GlSkeletonLoader,
  GlTab,
  GlTabs,
  GlTooltipDirective,
} from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { truncate } from '~/lib/utils/text_utility';
import { __, n__, s__, sprintf } from '~/locale';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import NotFound from '../../../components/not_found.vue';
import {
  MANIFEST_KIND_INDEX,
  MANIFEST_KIND_LABELS,
  PAGE_NOT_FOUND_TITLE,
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
} from '../../../constants';
import getManifestQuery from '../../../graphql/queries/get_manifest.query.graphql';
import { manifestType, shortDigest } from '../../../utils';
import FormatLogo from '../../components/format_logo.vue';
import ManifestOverview from './manifest_overview.vue';
import ManifestSidebar from './manifest_sidebar.vue';
import ReferrersSection from './referrers_section.vue';

const MAX_TAGS_SHOWN = 5;

const MAX_TAG_LENGTH = 32;

const TAB_QUERY_KEY = 'tab';

const TAB_OVERVIEW = 'overview';

const TAB_REFERRERS = 'referrers';

const TABS = [
  { value: TAB_OVERVIEW, text: __('Overview') },
  { value: TAB_REFERRERS, text: s__('ArtifactRegistry|Referrers') },
];

export default {
  name: 'ArtifactRegistryManifestDetail',
  components: {
    ClipboardButton,
    DetailLayout,
    FormatLogo,
    GlAlert,
    GlBadge,
    GlPopover,
    GlSkeletonLoader,
    GlTab,
    GlTabs,
    ManifestOverview,
    ManifestSidebar,
    NotFound,
    ReferrersSection,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['breadCrumbState', 'organizationGid'],
  data() {
    return {
      repository: undefined,
      hasError: false,
      tagsPopoverTarget: uniqueId('manifest-tags-popover-'),
    };
  },
  apollo: {
    repository: {
      query: getManifestQuery,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.repositoryName,
          artifactId: this.artifactId,
          digest: this.digest,
        };
      },
      update: ({ organization }) => organization?.artifactRegistryRepository ?? null,
      // Not redundant with `error` below: this query sets no `errorPolicy`, so vue-apollo calls
      // `result` on failure too. Clearing unconditionally here would drop the alert.
      result({ error }) {
        this.hasError = Boolean(error);
      },
      error() {
        this.hasError = true;
      },
    },
  },
  computed: {
    repositoryName() {
      return this.$route.params.id;
    },
    artifactId() {
      return this.$route.params.artifactId;
    },
    digest() {
      return this.$route.params.digest;
    },
    isLoading() {
      return this.$apollo.queries.repository.loading;
    },
    format() {
      return this.repository?.format;
    },
    formatLabel() {
      return REPOSITORY_FORMAT_LABELS[this.format];
    },
    manifest() {
      return this.repository?.manifest ?? null;
    },
    image() {
      return this.repository?.image ?? null;
    },
    imageName() {
      return this.image?.name ?? '';
    },
    shortenedDigest() {
      return shortDigest(this.manifest?.digest);
    },
    type() {
      return manifestType(this.manifest ?? {});
    },
    isIndex() {
      return this.type.kind === MANIFEST_KIND_INDEX;
    },
    isReferrer() {
      return Boolean(this.type.subjectDigest);
    },
    kindLabel() {
      if (!this.isIndex) return MANIFEST_KIND_LABELS[this.type.kind];

      const platforms = this.manifest?.childrenCount ?? 0;

      return n__(
        'ArtifactRegistry|Index · %d platform',
        'ArtifactRegistry|Index · %d platforms',
        platforms,
      );
    },
    mediaTypeLabel() {
      return sprintf(this.$options.i18n.mediaType, { mediaType: this.manifest?.mediaType });
    },
    artifactTypeLabel() {
      return sprintf(this.$options.i18n.artifactType, {
        artifactType: this.manifest?.artifactType,
      });
    },
    subjectDigestLabel() {
      return sprintf(this.$options.i18n.subjectDigest, {
        digest: this.manifest?.subjectDigest,
      });
    },
    digestLabel() {
      let message = this.$options.i18n.imageDigest;

      if (this.isIndex) message = this.$options.i18n.indexDigest;
      if (this.isReferrer) message = this.$options.i18n.manifestDigest;

      return sprintf(message, { digest: this.manifest?.digest });
    },
    tags() {
      return this.manifest?.tags ?? [];
    },
    visibleTags() {
      return this.tags.slice(0, MAX_TAGS_SHOWN);
    },
    collapsedTags() {
      return this.tags.slice(MAX_TAGS_SHOWN);
    },
    moreTagsText() {
      return sprintf(this.$options.i18n.moreTags, { count: this.collapsedTags.length });
    },
    isNotFound() {
      return !this.isLoading && !this.hasError && !this.manifest;
    },
    isPopulated() {
      return Boolean(this.manifest);
    },
    // The heading and description slots render outside the layout's content, so they carry their
    // own gate: a failed refetch would otherwise leave the header standing over the alert.
    rendersManifest() {
      return this.isPopulated && !this.isLoading && !this.hasError;
    },
    // Settling is read off the data, not `isLoading`: Vue evaluates a watcher's getter before
    // vue-apollo registers the query, so publishing early blanks the name the list resolved.
    resolvedBreadCrumbNames() {
      if (this.repository === undefined && !this.hasError) return null;

      return { artifact: this.imageName, manifest: shortDigest(this.digest) };
    },
    referrersCount() {
      return this.manifest?.referrersCount ?? null;
    },
    tabs() {
      return TABS.map((tab) => {
        const count = tab.value === TAB_REFERRERS ? this.referrersCount : null;

        return {
          ...tab,
          count,
          isOverview: tab.value === TAB_OVERVIEW,
          isReferrers: tab.value === TAB_REFERRERS,
          countSrText:
            count === null
              ? null
              : n__('ArtifactRegistry|%d referrer', 'ArtifactRegistry|%d referrers', count),
        };
      });
    },
    activeTab() {
      const requested = this.$route.query[TAB_QUERY_KEY];

      return this.tabs.some(({ value }) => value === requested) ? requested : TAB_OVERVIEW;
    },
    activeTabLabel() {
      return this.tabs.find(({ value }) => value === this.activeTab)?.text ?? '';
    },
    tabIndex: {
      get() {
        return Math.max(
          this.tabs.findIndex(({ value }) => value === this.activeTab),
          0,
        );
      },
      set(index) {
        const tab = this.tabs[index]?.value;

        if (!tab || tab === this.activeTab) return;

        this.$router.push({
          path: this.$route.path,
          query: { ...this.$route.query, [TAB_QUERY_KEY]: tab },
        });
      },
    },
    statusMessage() {
      // GlAlert renders role="alert" for the danger variant and announces the failure itself,
      // so naming it here would put the same text through a second live region.
      if (this.hasError) return '';
      if (this.isLoading) return this.$options.i18n.loading;
      if (this.isNotFound) return this.$options.i18n.notFound;

      if (!this.imageName) {
        return sprintf(this.$options.i18n.loadedWithoutImage, {
          tab: this.activeTabLabel,
          digest: this.shortenedDigest,
        });
      }

      return sprintf(this.$options.i18n.loaded, {
        tab: this.activeTabLabel,
        digest: this.shortenedDigest,
        name: this.imageName,
      });
    },
  },
  watch: {
    resolvedBreadCrumbNames(names) {
      if (!names) return;

      this.breadCrumbState.updateArtifactName(names.artifact);
      this.breadCrumbState.updateManifestName(names.manifest);
    },
  },
  methods: {
    tagTitle(tag) {
      return truncate(tag, MAX_TAG_LENGTH);
    },
    tagTooltip(tag) {
      return tag === this.tagTitle(tag) ? null : tag;
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
    loading: s__('ArtifactRegistry|Loading manifest details.'),
    loaded: s__('ArtifactRegistry|%{tab} tab for manifest %{digest} of %{name}.'),
    loadedWithoutImage: s__('ArtifactRegistry|%{tab} tab for manifest %{digest}.'),
    notFound: PAGE_NOT_FOUND_TITLE,
    mediaType: s__('ArtifactRegistry|Media type: %{mediaType}'),
    artifactType: s__('ArtifactRegistry|Artifact type: %{artifactType}'),
    subjectDigest: s__('ArtifactRegistry|Subject digest: %{digest}'),
    indexDigest: s__('ArtifactRegistry|Index digest: %{digest}'),
    imageDigest: s__('ArtifactRegistry|Image digest: %{digest}'),
    manifestDigest: s__('ArtifactRegistry|Manifest digest: %{digest}'),
    copyDigest: s__('ArtifactRegistry|Copy digest'),
    tags: s__('ArtifactRegistry|Tags'),
    moreTags: s__('ArtifactRegistry|+%{count} more'),
    allTags: s__('ArtifactRegistry|All tags'),
  },
  logoSize: REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
};
</script>

<template>
  <div>
    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="manifest-announcement"
      >{{ statusMessage }}</span
    >

    <detail-layout :loading="isLoading">
      <template #loading>
        <gl-skeleton-loader :lines="2" :width="500" />
      </template>

      <!-- The wrapper renders unconditionally: Vue 2 reads a slot whose only output is a `v-if`
           comment as empty and falls back to the layout's own empty h1. -->
      <template #heading-wrapper>
        <div class="gl-flex gl-min-w-0 gl-grow gl-flex-wrap gl-items-center gl-gap-3">
          <template v-if="rendersManifest">
            <format-logo :format="format" :size="$options.logoSize" />
            <span class="gl-sr-only" data-testid="manifest-format-name">{{ formatLabel }}</span>

            <h1 class="gl-heading-1 !gl-m-0" data-testid="page-heading">
              <span class="gl-font-monospace gl-wrap-anywhere" data-testid="manifest-digest">{{
                shortenedDigest
              }}</span>
            </h1>

            <ul
              v-if="tags.length"
              class="gl-m-0 gl-flex gl-list-none gl-flex-wrap gl-items-center gl-gap-3 gl-p-0"
              :aria-label="$options.i18n.tags"
              data-testid="manifest-tags"
            >
              <gl-badge
                v-for="tag in visibleTags"
                :key="tag"
                v-gl-tooltip="tagTooltip(tag)"
                tag="li"
                variant="info"
                class="gl-font-monospace"
                data-testid="manifest-tag"
                >{{ tagTitle(tag) }}</gl-badge
              >

              <li v-if="collapsedTags.length">
                <span
                  :id="tagsPopoverTarget"
                  role="button"
                  tabindex="0"
                  class="gl-text-sm gl-text-subtle"
                  data-testid="manifest-more-tags"
                  >{{ moreTagsText }}</span
                >

                <gl-popover :target="tagsPopoverTarget" :title="$options.i18n.allTags">
                  <div class="gl-flex gl-flex-wrap gl-gap-3">
                    <gl-badge
                      v-for="tag in collapsedTags"
                      :key="tag"
                      v-gl-tooltip="tagTooltip(tag)"
                      variant="info"
                      class="gl-font-monospace"
                      data-testid="manifest-collapsed-tag"
                      >{{ tagTitle(tag) }}</gl-badge
                    >
                  </div>
                </gl-popover>
              </li>
            </ul>

            <gl-badge data-testid="manifest-kind">{{ kindLabel }}</gl-badge>
          </template>
        </div>
      </template>

      <template v-if="rendersManifest" #description>
        <span v-if="imageName" class="gl-block gl-wrap-anywhere" data-testid="image-name">{{
          imageName
        }}</span>

        <span class="gl-block gl-text-sm gl-wrap-anywhere" data-testid="manifest-media-type">{{
          mediaTypeLabel
        }}</span>

        <span
          v-if="manifest.artifactType"
          class="gl-block gl-text-sm gl-wrap-anywhere"
          data-testid="manifest-artifact-type"
          >{{ artifactTypeLabel }}</span
        >

        <span
          v-if="isReferrer"
          class="gl-block gl-text-sm gl-wrap-anywhere"
          data-testid="manifest-subject-digest"
          >{{ subjectDigestLabel }}</span
        >

        <span class="gl-flex gl-items-center gl-gap-2">
          <span class="gl-text-sm gl-wrap-anywhere" data-testid="manifest-full-digest">{{
            digestLabel
          }}</span>
          <clipboard-button
            :text="manifest.digest"
            :title="$options.i18n.copyDigest"
            category="tertiary"
            size="small"
          />
        </span>
      </template>

      <gl-alert v-if="hasError" variant="danger" :dismissible="false">
        {{ $options.i18n.unavailable }}
      </gl-alert>

      <not-found v-else-if="isNotFound" />

      <gl-tabs v-else-if="rendersManifest" v-model="tabIndex" lazy content-class="gl-py-5">
        <gl-tab
          v-for="tab in tabs"
          :key="tab.value"
          :title="tab.text"
          :tab-count="tab.count"
          :tab-count-sr-text="tab.countSrText"
        >
          <manifest-overview
            v-if="tab.isOverview"
            :format="format"
            :name="repositoryName"
            :image-name="imageName"
            :manifest="manifest"
          />

          <referrers-section
            v-else-if="tab.isReferrers"
            :name="repositoryName"
            :artifact-id="artifactId"
            :digest="manifest.digest"
          />
        </gl-tab>
      </gl-tabs>

      <template v-if="rendersManifest" #sidebar>
        <manifest-sidebar :repository="repository" :manifest="manifest" :artifact-id="artifactId" />
      </template>
    </detail-layout>
  </div>
</template>
