<script>
import { GlAlert, GlKeysetPagination, GlSkeletonLoader } from '@gitlab/ui';
import { isEqual, isNil, mapValues, omit, omitBy } from 'lodash-es';
import { fetchPolicies } from '~/lib/graphql';
import { getStorageValue } from '~/lib/utils/local_storage';
import { s__, sprintf } from '~/locale';
import { getPageParams } from '~/packages_and_registries/shared/utils';
import LocalStorageSync from '~/vue_shared/components/local_storage_sync.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import NotFound from '../../components/not_found.vue';
import {
  ARTIFACT_SORT_DEFAULT,
  GRAPHQL_PAGE_SIZE,
  MANIFEST_SORT_COLUMNS,
  MANIFEST_SORT_VALUES,
  PAGE_NOT_FOUND_TITLE,
  REFERRERS_EXCLUDED_QUERY_VALUE,
  REFERRERS_QUERY_KEY,
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
  VERSION_LIST_COLUMNS_STORAGE_KEY,
  VERSION_LIST_OPTIONAL_COLUMNS,
  VERSION_SORT_COLUMNS,
  VERSION_SORT_VALUES,
} from '../../constants';
import getArtifactQuery from '../../graphql/queries/get_artifact.query.graphql';
import getArtifactManifestsQuery from '../../graphql/queries/get_artifact_manifests.query.graphql';
import getArtifactVersionsQuery from '../../graphql/queries/get_artifact_versions.query.graphql';
import {
  artifactDisplayName,
  isContainerFormat,
  toFilterEnumValue,
  toFilterQueryValue,
  toSortEnumValue,
  toTableSort,
  versionListFamily,
} from '../../utils';
import FormatLogo from '../components/format_logo.vue';
import ArtifactActions from './artifact_actions.vue';
import VersionsSection from './versions_section.vue';
import ViewOptions from './view_options.vue';

// A stored selection is filtered to the columns the family actually offers a switch for, so a
// column that has since gone, or a hand-edited entry, cannot hide one the popover cannot restore.
const storedHiddenColumns = (storageKey, family) => {
  const { value } = getStorageValue(storageKey);

  return Array.isArray(value)
    ? value.filter((column) => VERSION_LIST_OPTIONAL_COLUMNS[family].includes(column))
    : [];
};

const CURSOR_QUERY_KEYS = ['after', 'before'];

export default {
  name: 'ArtifactRegistryVersionList',
  components: {
    ArtifactActions,
    FormatLogo,
    GlAlert,
    GlKeysetPagination,
    GlSkeletonLoader,
    LocalStorageSync,
    NotFound,
    PageHeading,
    VersionsSection,
    ViewOptions,
  },
  inject: ['breadCrumbState', 'organizationGid'],
  data() {
    return {
      repository: undefined,
      hasError: false,
      artifactConnection: undefined,
      hasArtifactConnectionError: false,
      hiddenColumns: [],
    };
  },
  apollo: {
    repository: {
      query: getArtifactQuery,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      notifyOnNetworkStatusChange: true,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.repositoryName,
          artifactId: this.artifactId,
        };
      },
      update: ({ organization }) => organization?.artifactRegistryRepository ?? null,
      result({ error }) {
        this.hasError = Boolean(error);
      },
      error() {
        this.hasError = true;
      },
    },
    artifactConnection: {
      query() {
        return this.readsManifests ? getArtifactManifestsQuery : getArtifactVersionsQuery;
      },
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.repositoryName,
          artifactId: this.artifactId,
          sort: this.sortValue,
          // Only the manifests document declares it, so the versions read must not carry it.
          ...(this.readsManifests ? { includeReferrers: this.includeReferrers } : {}),
          first: GRAPHQL_PAGE_SIZE,
          // A backward page asks for `last` and carries `first: undefined`, so the page
          // params have to land after the default rather than beside it.
          ...this.pageParams,
        };
      },
      skip() {
        return !this.isPopulated;
      },
      update({ organization }) {
        const repository = organization?.artifactRegistryRepository;

        return (
          (this.readsManifests ? repository?.image?.manifests : repository?.package?.versions) ??
          null
        );
      },
      result({ error }) {
        this.hasArtifactConnectionError = Boolean(error);
      },
      error() {
        this.hasArtifactConnectionError = true;
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
    isLoading() {
      return this.$apollo.queries.repository.loading;
    },
    isInitialLoad() {
      return this.isLoading && this.repository === undefined;
    },
    permissions() {
      return this.isLoading ? undefined : this.repository?.userPermissions;
    },
    format() {
      return this.repository?.format;
    },
    artifact() {
      return this.repository?.image ?? this.repository?.package ?? null;
    },
    displayName() {
      return artifactDisplayName(this.artifact, this.format);
    },
    formatLabel() {
      return REPOSITORY_FORMAT_LABELS[this.format];
    },
    // A missing repository and a missing artifact render one outcome, so the view never
    // confirms that an artifact the viewer cannot see exists.
    isNotFound() {
      return !this.isInitialLoad && !this.hasError && !this.artifact;
    },
    isPopulated() {
      return Boolean(this.artifact);
    },
    readsManifests() {
      return isContainerFormat(this.format);
    },
    // The format arrives with the artifact read, so the key the selection lives under is not
    // knowable at init: it settles once the repository resolves.
    columnsStorageKey() {
      if (!this.format) return null;

      return `${VERSION_LIST_COLUMNS_STORAGE_KEY}-${versionListFamily(this.format)}`;
    },
    rows() {
      return this.artifactConnection?.nodes ?? [];
    },
    pageInfo() {
      return this.artifactConnection?.pageInfo ?? {};
    },
    pageParams() {
      return getPageParams(this.$route.query, GRAPHQL_PAGE_SIZE);
    },
    // The format decides which columns sort, so a sort the route names is validated against
    // the set the active table offers rather than against both.
    sortColumns() {
      return this.readsManifests ? MANIFEST_SORT_COLUMNS : VERSION_SORT_COLUMNS;
    },
    sortValues() {
      return this.readsManifests ? MANIFEST_SORT_VALUES : VERSION_SORT_VALUES;
    },
    sortValue() {
      return toFilterEnumValue(this.$route.query.sort, this.sortValues) ?? ARTIFACT_SORT_DEFAULT;
    },
    sort() {
      return toTableSort(this.sortValue, this.sortColumns);
    },
    includeReferrers() {
      return this.$route.query[REFERRERS_QUERY_KEY] !== REFERRERS_EXCLUDED_QUERY_VALUE;
    },
    hasRowsError() {
      return (
        this.isPopulated && (this.hasArtifactConnectionError || this.artifactConnection === null)
      );
    },
    isLoadingRows() {
      if (!this.isPopulated || this.hasRowsError) return false;

      return (
        this.$apollo.queries.artifactConnection.loading || this.artifactConnection === undefined
      );
    },
    emptyMessage() {
      const { emptyManifests, emptyVersions } = this.$options.i18n;

      return this.readsManifests ? emptyManifests : emptyVersions;
    },
    statusMessage() {
      if (this.hasError || this.hasRowsError) return this.$options.i18n.unavailable;
      if (this.isInitialLoad) return this.$options.i18n.loading;
      if (this.isNotFound) return this.$options.i18n.notFound;
      if (this.isLoadingRows) return this.$options.i18n.versionsLoading;
      if (!this.rows.length) return sprintf(this.emptyMessage, { name: this.displayName });

      return sprintf(this.$options.i18n.versionsLoaded, { name: this.displayName });
    },
  },
  watch: {
    columnsStorageKey(storageKey) {
      this.hiddenColumns = storedHiddenColumns(storageKey, versionListFamily(this.format));
    },
    displayName: {
      immediate: true,
      handler(name) {
        this.breadCrumbState.updateArtifactName(name);
      },
    },
  },
  methods: {
    pushQuery(query) {
      if (isEqual(query, this.$route.query)) return;

      this.$router.push({ path: this.$route.path, query });
    },
    applyQueryParams(params) {
      const remainder = omit(this.$route.query, CURSOR_QUERY_KEYS);
      const applied = mapValues(params, toFilterQueryValue);
      const query = omitBy({ ...remainder, ...applied }, isNil);

      if (isEqual(query, remainder)) return;

      this.pushQuery(query);
    },
    applySort(sort) {
      this.applyQueryParams({ sort: toSortEnumValue(sort, this.sortColumns) });
    },
    applyIncludeReferrers(includeReferrers) {
      this.applyQueryParams({
        [REFERRERS_QUERY_KEY]: includeReferrers ? null : REFERRERS_EXCLUDED_QUERY_VALUE,
      });
    },
    pageTo(cursor) {
      const remainder = omit(this.$route.query, CURSOR_QUERY_KEYS);

      this.pushQuery(omitBy({ ...remainder, ...cursor }, isNil));
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
    loading: s__('ArtifactRegistry|Loading artifact details.'),
    versionsLoading: s__('ArtifactRegistry|Loading versions.'),
    versionsLoaded: s__('ArtifactRegistry|Version list for %{name} updated.'),
    emptyVersions: s__('ArtifactRegistry|No versions found for %{name}.'),
    emptyManifests: s__('ArtifactRegistry|No manifests found for %{name}.'),
    notFound: PAGE_NOT_FOUND_TITLE,
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
      data-testid="versions-announcement"
      >{{ statusMessage }}</span
    >

    <gl-skeleton-loader v-if="isInitialLoad" :lines="2" :width="500" class="gl-mt-4" />

    <gl-alert v-else-if="hasError" variant="danger" :dismissible="false">
      {{ $options.i18n.unavailable }}
    </gl-alert>

    <not-found v-else-if="isNotFound" />

    <template v-else-if="isPopulated">
      <page-heading>
        <template #heading>
          <span class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
            <format-logo :format="format" :size="$options.logoSize" />
            <span class="gl-sr-only" data-testid="artifact-format-name">{{ formatLabel }}</span>
            <span class="gl-wrap-anywhere" data-testid="artifact-name">{{ displayName }}</span>
          </span>
        </template>

        <template #actions>
          <artifact-actions
            :artifact="artifact"
            :format="format"
            :name="repositoryName"
            :permissions="permissions"
          />
        </template>
      </page-heading>

      <!-- Keyed on the storage key so each format family gets its own instance: one instance
           spanning a family change could write the arriving selection under the leaving key. -->
      <local-storage-sync
        :key="columnsStorageKey"
        :storage-key="columnsStorageKey"
        :value="hiddenColumns"
      />

      <div class="gl-mb-3 gl-flex gl-justify-end">
        <view-options
          :format="format"
          :hidden-columns="hiddenColumns"
          :include-referrers="includeReferrers"
          @input="hiddenColumns = $event"
          @referrers-changed="applyIncludeReferrers"
        />
      </div>

      <versions-section
        :format="format"
        :artifact="artifact"
        :name="repositoryName"
        :rows="rows"
        :loading="isLoadingRows"
        :has-error="hasRowsError"
        :hidden-columns="hiddenColumns"
        :sort="sort"
        :permissions="permissions"
        @sort-changed="applySort"
      />

      <div class="gl-mt-3 gl-flex gl-justify-center">
        <gl-keyset-pagination
          v-bind="pageInfo"
          :disabled="isLoadingRows"
          @prev="pageTo({ before: $event })"
          @next="pageTo({ after: $event })"
        />
      </div>
    </template>
  </div>
</template>
