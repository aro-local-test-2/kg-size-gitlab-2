<script>
import {
  GlAlert,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlKeysetPagination,
  GlSkeletonLoader,
  GlTab,
  GlTabs,
  GlToastMixin,
} from '@gitlab/ui';
import { isEqual, isNil, omit, omitBy } from 'lodash-es';
import { fetchPolicies } from '~/lib/graphql';
import { getPageParams } from '~/packages_and_registries/shared/utils';
import { __, n__, s__, sprintf } from '~/locale';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import NotFound from '../../../components/not_found.vue';
import {
  ARTIFACT_VERSIONS_ROUTE_NAME,
  GRAPHQL_PAGE_SIZE,
  PAGE_NOT_FOUND_TITLE,
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
  REPOSITORY_FORMAT_MAVEN,
  REPOSITORY_FORMAT_NPM,
} from '../../../constants';
import deleteVersionMutation from '../../../graphql/mutations/delete_version.mutation.graphql';
import getVersionQuery from '../../../graphql/queries/get_version.query.graphql';
import getVersionFilesQuery from '../../../graphql/queries/get_version_files.query.graphql';
import { executeDeleteMutation } from '../../../graphql/utils/delete_mutation';
import { artifactDisplayName, filesEmptyTitle } from '../../../utils';
import DeleteConfirmationModal from '../../components/delete_confirmation_modal.vue';
import FormatLogo from '../../components/format_logo.vue';
import FilesSection from './files_section.vue';
import VersionOverview from './version_overview.vue';
import VersionSidebar from './version_sidebar.vue';

const TAB_QUERY_KEY = 'tab';
const CURSOR_QUERY_KEYS = ['after', 'before'];

const TAB_OVERVIEW = 'overview';

const TAB_FILES = 'files';

// An npm version holds one file, so the same tab is named in the singular there.
const TABS = {
  [REPOSITORY_FORMAT_MAVEN]: [
    { value: TAB_OVERVIEW, text: __('Overview') },
    { value: TAB_FILES, text: __('Files') },
  ],
  [REPOSITORY_FORMAT_NPM]: [
    { value: TAB_OVERVIEW, text: __('Overview') },
    { value: TAB_FILES, text: __('File') },
  ],
};

export default {
  name: 'ArtifactRegistryVersionDetail',
  components: {
    DeleteConfirmationModal,
    DetailLayout,
    FilesSection,
    FormatLogo,
    GlAlert,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlKeysetPagination,
    GlSkeletonLoader,
    GlTab,
    GlTabs,
    NotFound,
    VersionOverview,
    VersionSidebar,
  },
  mixins: [GlToastMixin],
  inject: ['breadCrumbState', 'organizationGid'],
  data() {
    return {
      repository: undefined,
      filesRepository: undefined,
      hasError: false,
      hasFilesReadError: false,
      versionToDelete: null,
      isDeleting: false,
    };
  },
  apollo: {
    repository: {
      query: getVersionQuery,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.repositoryName,
          artifactId: this.artifactId,
          versionId: this.versionId,
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
    filesRepository: {
      query: getVersionFilesQuery,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.repositoryName,
          artifactId: this.artifactId,
          versionId: this.versionId,
          first: GRAPHQL_PAGE_SIZE,
          // A backward page asks for `last` and carries `first: undefined`, so the page
          // params have to land after the default rather than beside it.
          ...this.filesPageParams,
        };
      },
      skip() {
        return this.activeTab !== TAB_FILES;
      },
      update: ({ organization }) => organization?.artifactRegistryRepository ?? null,
      result({ error }) {
        this.hasFilesReadError = Boolean(error);
      },
      error() {
        this.hasFilesReadError = true;
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
    versionId() {
      return this.$route.params.versionId;
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
    version() {
      return this.repository?.version ?? null;
    },
    versionString() {
      return this.version?.version ?? '';
    },
    toggleText() {
      return sprintf(this.$options.i18n.moreActions, { name: this.versionString });
    },
    deleteItem() {
      return {
        text: this.$options.i18n.deleteVersionLabel,
        variant: 'danger',
        action: () => {
          this.versionToDelete = this.version;
        },
      };
    },
    deleteModalCopy() {
      const { deleteTitle, deleteBody, deleteVersionLabel } = this.$options.i18n;

      return {
        title: deleteTitle,
        body: deleteBody,
        name: this.versionString,
        actionText: deleteVersionLabel,
      };
    },
    artifact() {
      return this.repository?.package ?? null;
    },
    artifactName() {
      return artifactDisplayName(this.artifact, this.format);
    },
    isNotFound() {
      return !this.isLoading && !this.hasError && !this.version;
    },
    isPopulated() {
      return Boolean(this.version);
    },
    rendersVersion() {
      return this.isPopulated && !this.isLoading && !this.hasError;
    },
    // Publishing before the read settles blanks the name the version list resolved, which the
    // trail renders as the opaque id. Settling is read off the data, not `isLoading`: Vue
    // evaluates a watcher's getter before vue-apollo registers the query, so it would cache that.
    resolvedBreadCrumbNames() {
      if (this.repository === undefined && !this.hasError) return null;

      return { artifact: this.artifactName, version: this.versionString };
    },
    // Not `?? null`: `undefined` until the read settles, so a version that resolves to null
    // stays distinguishable from one still in flight.
    filesVersion() {
      return this.filesRepository === undefined
        ? undefined
        : (this.filesRepository?.version ?? null);
    },
    isLoadingFiles() {
      if (this.activeTab !== TAB_FILES || !this.isPopulated || this.hasFilesError) return false;

      return this.$apollo.queries.filesRepository.loading || this.filesVersion === undefined;
    },
    files() {
      return this.filesVersion?.files?.nodes ?? [];
    },
    hasFilesError() {
      return this.isPopulated && (this.hasFilesReadError || this.filesVersion === null);
    },
    // vue-apollo keeps the last good result on error, so without this the pager would stay
    // live on the failed page's cursors, and Next would rebuild the query that just failed.
    filesPageInfo() {
      if (this.hasFilesError) return {};

      return this.filesVersion?.files?.pageInfo ?? {};
    },
    filesPageParams() {
      return getPageParams(this.$route.query, GRAPHQL_PAGE_SIZE);
    },
    hasNoFiles() {
      return (
        this.isPopulated &&
        this.activeTab === TAB_FILES &&
        !this.isLoadingFiles &&
        !this.hasFilesError &&
        !this.files.length
      );
    },
    filesCount() {
      const count = this.version?.statistics?.filesCount;

      if (isNil(count)) return null;

      const number = Number(count);

      return Number.isFinite(number) ? number : null;
    },
    tabs() {
      return (TABS[this.format] ?? []).map((tab) => {
        const count =
          tab.value === TAB_FILES && this.format === REPOSITORY_FORMAT_MAVEN
            ? this.filesCount
            : null;

        return {
          ...tab,
          count,
          countSrText: count === null ? null : n__('%d file', '%d files', count),
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

        this.pushQuery({
          ...omit(this.$route.query, CURSOR_QUERY_KEYS),
          [TAB_QUERY_KEY]: tab,
        });
      },
    },
    statusMessage() {
      // GlAlert renders role="alert" for the danger variant and announces the failure itself,
      // so naming it here would put the same text through a second live region.
      if (this.hasError) return '';
      if (this.isLoading) return this.$options.i18n.loading;
      if (this.isNotFound) return this.$options.i18n.notFound;
      if (this.activeTab === TAB_FILES && this.hasFilesError) return '';
      if (this.isLoadingFiles) return this.$options.i18n.filesLoading;

      if (this.hasNoFiles) {
        return filesEmptyTitle(this.format, this.versionString);
      }

      if (!this.artifactName) {
        return sprintf(this.$options.i18n.loadedWithoutArtifact, {
          tab: this.activeTabLabel,
          version: this.versionString,
        });
      }

      return sprintf(this.$options.i18n.loaded, {
        tab: this.activeTabLabel,
        version: this.versionString,
        name: this.artifactName,
      });
    },
  },
  watch: {
    resolvedBreadCrumbNames(names) {
      if (!names) return;

      this.breadCrumbState.updateArtifactName(names.artifact);
      this.breadCrumbState.updateVersionName(names.version);
    },
  },
  methods: {
    pushQuery(query) {
      if (isEqual(query, this.$route.query)) return;

      this.$router.push({ path: this.$route.path, query });
    },
    pageTo(cursor) {
      const remainder = omit(this.$route.query, CURSOR_QUERY_KEYS);

      this.pushQuery(omitBy({ ...remainder, ...cursor }, isNil));
    },
    async deleteVersion() {
      if (this.isDeleting) return;

      this.isDeleting = true;

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: deleteVersionMutation,
          input: { name: this.repositoryName, id: this.versionId },
        });

        if (!accepted) return;

        this.$toast.show(this.$options.i18n.deletionScheduled);
        this.$router.push({
          name: ARTIFACT_VERSIONS_ROUTE_NAME,
          params: { id: this.repositoryName, artifactId: this.artifactId },
        });
      } finally {
        this.isDeleting = false;
      }
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
    loading: s__('ArtifactRegistry|Loading version details.'),
    loaded: s__('ArtifactRegistry|%{tab} tab for version %{version} of %{name}.'),
    loadedWithoutArtifact: s__('ArtifactRegistry|%{tab} tab for version %{version}.'),
    filesLoading: s__('ArtifactRegistry|Loading files.'),
    notFound: PAGE_NOT_FOUND_TITLE,
    moreActions: s__('ArtifactRegistry|More actions for %{name}'),
    deleteVersionLabel: s__('ArtifactRegistry|Delete version'),
    deleteTitle: s__('ArtifactRegistry|Delete version?'),
    deleteBody: s__(
      'ArtifactRegistry|This action permanently deletes version %{name} and all of its files. This action cannot be undone.',
    ),
    deletionScheduled: s__('ArtifactRegistry|Version successfully scheduled for deletion.'),
  },
  logoSize: REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
  overviewTab: TAB_OVERVIEW,
  filesTab: TAB_FILES,
};
</script>

<template>
  <div>
    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="version-announcement"
      >{{ statusMessage }}</span
    >

    <detail-layout :loading="isLoading">
      <template #loading>
        <gl-skeleton-loader :lines="2" :width="500" />
      </template>

      <template #heading-wrapper>
        <div class="gl-min-w-0 gl-grow">
          <h1 v-if="rendersVersion" class="gl-heading-1 !gl-m-0" data-testid="page-heading">
            <span class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
              <format-logo :format="format" :size="$options.logoSize" />
              <span class="gl-sr-only" data-testid="version-format-name">{{ formatLabel }}</span>
              <span class="gl-wrap-anywhere" data-testid="version-name">{{ versionString }}</span>
            </span>
          </h1>
        </div>
      </template>

      <template v-if="rendersVersion" #actions>
        <gl-disclosure-dropdown
          icon="ellipsis_v"
          :toggle-text="toggleText"
          :loading="isDeleting"
          text-sr-only
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="version-actions"
        >
          <gl-disclosure-dropdown-item :item="deleteItem" data-testid="delete-version" />
        </gl-disclosure-dropdown>
      </template>

      <template v-if="rendersVersion && artifactName" #description>
        <span class="gl-wrap-anywhere" data-testid="artifact-name">{{ artifactName }}</span>
      </template>

      <gl-alert v-if="hasError" variant="danger" :dismissible="false">
        {{ $options.i18n.unavailable }}
      </gl-alert>

      <not-found v-else-if="isNotFound" />

      <gl-tabs v-else-if="rendersVersion" v-model="tabIndex" lazy content-class="gl-py-5">
        <gl-tab
          v-for="tab in tabs"
          :key="tab.value"
          :title="tab.text"
          :tab-count="tab.count"
          :tab-count-sr-text="tab.countSrText"
        >
          <version-overview
            v-if="tab.value === $options.overviewTab"
            :format="format"
            :name="repository.name"
            :artifact="artifact"
            :version="version"
          />

          <template v-else-if="tab.value === $options.filesTab">
            <files-section
              :format="format"
              :files="files"
              :version-string="versionString"
              :loading="isLoadingFiles"
              :has-error="hasFilesError"
            />

            <div class="gl-mt-3 gl-flex gl-justify-center">
              <gl-keyset-pagination
                v-bind="filesPageInfo"
                :disabled="isLoadingFiles"
                @prev="pageTo({ before: $event })"
                @next="pageTo({ after: $event })"
              />
            </div>
          </template>
        </gl-tab>
      </gl-tabs>

      <template v-if="rendersVersion" #sidebar>
        <version-sidebar :repository="repository" :version="version" />
      </template>
    </detail-layout>

    <delete-confirmation-modal
      v-model="versionToDelete"
      v-bind="deleteModalCopy"
      @confirm="deleteVersion"
    />
  </div>
</template>
