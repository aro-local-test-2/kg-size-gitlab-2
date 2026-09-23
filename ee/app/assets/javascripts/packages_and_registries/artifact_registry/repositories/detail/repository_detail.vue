<script>
import { GlAlert, GlButton, GlKeysetPagination, GlSkeletonLoader } from '@gitlab/ui';
import { fetchPolicies } from '~/lib/graphql';
import { __, s__ } from '~/locale';
import { getPageParams } from '~/packages_and_registries/shared/utils';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import NotFound from '../../components/not_found.vue';
import {
  GRAPHQL_PAGE_SIZE,
  REPOSITORY_EDIT_ROUTE_NAME,
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_KIND_VIRTUAL,
  REPOSITORY_PERMISSION_UPDATE_REPOSITORY,
  SETUP_INSTRUCTIONS_TITLE,
} from '../../constants';
import getRepositoryDetailQuery from '../../graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from '../../graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from '../../graphql/queries/get_repository_packages.query.graphql';
import getRepositoryUpstreamRepositoriesQuery from '../../graphql/queries/get_repository_upstream_repositories.query.graphql';
import { permissionAllows } from '../../graphql/utils/permissions';
import { buildRepositoryClientUrl, isContainerFormat } from '../../utils';
import ArtifactsSection from './artifacts_section.vue';
import RepositoryActions from './repository_actions.vue';
import RepositoryHeading from './repository_heading.vue';
import RepositorySidebar from './repository_sidebar.vue';
import SetupDrawer from './setup_instructions/setup_drawer.vue';
import UpstreamRepositoriesEmptyState from './upstream_repositories_empty_state.vue';
import UpstreamRepositoriesTable from './upstream_repositories_table.vue';

export default {
  name: 'ArtifactRegistryRepositoryDetail',
  components: {
    ArtifactsSection,
    DetailLayout,
    GlAlert,
    GlButton,
    GlKeysetPagination,
    GlSkeletonLoader,
    NotFound,
    RepositoryActions,
    RepositoryHeading,
    RepositorySidebar,
    SetupDrawer,
    UpstreamRepositoriesEmptyState,
    UpstreamRepositoriesTable,
  },
  inject: ['organizationGid', 'slug', 'clientBaseUrl'],
  data() {
    return {
      repository: undefined,
      hasError: false,
      artifactConnection: undefined,
      hasArtifactConnectionError: false,
      upstreamRepositories: undefined,
      hasUpstreamRepositoriesError: false,
      showSetupDrawer: false,
    };
  },
  apollo: {
    repository: {
      query: getRepositoryDetailQuery,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      // Without this, vue-apollo holds the cached repository back until the background read
      // returns, so a revisit falls to the skeleton instead of rendering from cache at once.
      notifyOnNetworkStatusChange: true,
      variables() {
        return { organizationId: this.organizationGid, name: this.repositoryName };
      },
      update: ({ organization }) => organization?.artifactRegistryRepository ?? null,
      // The query re-runs whenever its variables change, so each result has to speak for
      // itself: a read that succeeds after one that failed must clear the flag, or the
      // alert outlives the error it reported. `result` fires for failures too, so it
      // reads the error rather than assuming success.
      result({ error }) {
        this.hasError = Boolean(error);
      },
      error() {
        this.hasError = true;
      },
    },
    artifactConnection: {
      query() {
        return this.readsImages ? getRepositoryImagesQuery : getRepositoryPackagesQuery;
      },
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.repositoryName,
          first: GRAPHQL_PAGE_SIZE,
          ...this.pageParams,
        };
      },
      skip() {
        return !this.isPopulated || this.isVirtual;
      },
      update({ organization }) {
        const repository = organization?.artifactRegistryRepository;

        return (this.readsImages ? repository?.images : repository?.packages) ?? null;
      },
      result({ error }) {
        this.hasArtifactConnectionError = Boolean(error);
      },
      error() {
        this.hasArtifactConnectionError = true;
      },
    },
    upstreamRepositories: {
      query: getRepositoryUpstreamRepositoriesQuery,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return { organizationId: this.organizationGid, name: this.repositoryName };
      },
      skip() {
        return !this.isPopulated || !this.isVirtual;
      },
      update({ organization }) {
        return organization?.artifactRegistryRepository?.upstreamRepositories ?? null;
      },
      result({ error }) {
        this.hasUpstreamRepositoriesError = Boolean(error);
      },
      error() {
        this.hasUpstreamRepositoriesError = true;
      },
    },
  },
  computed: {
    repositoryName() {
      return this.$route.params.id;
    },
    isLoading() {
      return this.$apollo.queries.repository.loading;
    },
    // The skeleton is for the first read only. A revisit has the cached repository already,
    // so it re-reads in the background rather than dropping the page back to a skeleton.
    isInitialLoad() {
      return this.isLoading && this.repository === undefined;
    },
    readsImages() {
      return isContainerFormat(this.repository?.format);
    },
    isLoadingArtifacts() {
      if (this.hasArtifactConnectionError) return false;

      return (
        this.$apollo.queries.artifactConnection.loading || this.artifactConnection === undefined
      );
    },
    artifacts() {
      return this.artifactConnection?.nodes ?? [];
    },
    pageInfo() {
      return this.artifactConnection?.pageInfo ?? {};
    },
    pageParams() {
      return getPageParams(this.$route.query, GRAPHQL_PAGE_SIZE);
    },
    isVirtual() {
      return this.repository?.kind === REPOSITORY_KIND_VIRTUAL;
    },
    upstreamRows() {
      return this.upstreamRepositories ?? [];
    },
    upstreamRepositoriesUnavailable() {
      return this.hasUpstreamRepositoriesError || this.upstreamRepositories === null;
    },
    upstreamRepositoriesMessage() {
      return this.hasUpstreamRepositoriesError
        ? this.$options.i18n.unavailable
        : this.$options.i18n.upstreamRepositoriesFailed;
    },
    isLoadingUpstreamRepositories() {
      if (this.upstreamRepositoriesUnavailable) return false;

      return (
        this.$apollo.queries.upstreamRepositories.loading || this.upstreamRepositories === undefined
      );
    },
    upstreamRepositoriesCount() {
      if (!this.isVirtual) return null;
      if (this.isLoadingUpstreamRepositories || this.upstreamRepositoriesUnavailable) return null;

      return this.upstreamRepositories?.length ?? null;
    },
    isLoadingMainContent() {
      return this.isVirtual ? this.isLoadingUpstreamRepositories : this.isLoadingArtifacts;
    },
    hasMainContentError() {
      return this.isVirtual
        ? this.upstreamRepositoriesUnavailable
        : this.hasArtifactConnectionError;
    },
    hasNoMainContent() {
      const rows = this.isVirtual ? this.upstreamRows : this.artifacts;

      return !this.isLoadingMainContent && !this.hasMainContentError && rows.length === 0;
    },
    isNotFound() {
      if (this.repository === null) return true;
      if (this.isVirtual) return false;

      return this.artifactConnection === null && !this.hasArtifactConnectionError;
    },
    isPopulated() {
      return Boolean(this.repository);
    },
    rendersRepository() {
      return this.isPopulated && !this.isInitialLoad && !this.hasError && !this.isNotFound;
    },
    permissions() {
      return this.isLoading ? undefined : this.repository?.userPermissions;
    },
    canUpdate() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_UPDATE_REPOSITORY);
    },
    // Every page announces the same sentence, and a live region stays silent on a message
    // identical to the one it holds. The loading pass a cursor change already causes is
    // what separates one page's announcement from the next.
    artifactsMessage() {
      if (this.hasArtifactConnectionError) return this.$options.i18n.unavailable;
      if (this.isLoadingArtifacts) return this.$options.i18n.artifactsLoading;

      return this.$options.i18n.artifactsUpdated;
    },
    editRoute() {
      return { name: REPOSITORY_EDIT_ROUTE_NAME, params: { id: this.repository.name } };
    },
    isRemote() {
      return this.repository.kind === REPOSITORY_KIND_REMOTE;
    },
    clientUrl() {
      return buildRepositoryClientUrl({
        clientBaseUrl: this.clientBaseUrl,
        slug: this.slug,
        format: this.repository.format,
        name: this.repository.name,
      });
    },
    showSetupInstructions() {
      if (!this.clientUrl) return false;

      return this.isRemote || !this.hasNoMainContent;
    },
  },
  methods: {
    pageTo({ before, after }) {
      this.$router.push({ query: { ...this.$route.query, before, after } });
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
    upstreamRepositoriesFailed: s__('ArtifactRegistry|Failed to load upstream repositories.'),
    artifactsLoading: s__('ArtifactRegistry|Loading artifacts.'),
    artifactsUpdated: s__('ArtifactRegistry|Artifact list updated.'),
    edit: __('Edit'),
    setupInstructions: SETUP_INSTRUCTIONS_TITLE,
  },
};
</script>

<template>
  <div>
    <span
      v-if="isPopulated && !isVirtual"
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="artifacts-announcement"
      >{{ artifactsMessage }}</span
    >

    <detail-layout :loading="isInitialLoad">
      <template #loading>
        <gl-skeleton-loader :lines="2" :width="500" />
      </template>

      <template #heading-wrapper>
        <div class="gl-min-w-0 gl-grow">
          <repository-heading v-if="rendersRepository" :repository="repository" />
        </div>
      </template>

      <template v-if="rendersRepository" #actions>
        <gl-button
          v-if="showSetupInstructions"
          data-testid="setup-instructions"
          @click="showSetupDrawer = true"
        >
          {{ $options.i18n.setupInstructions }}
        </gl-button>

        <gl-button v-if="canUpdate" :to="editRoute" data-testid="edit-repository">
          {{ $options.i18n.edit }}
        </gl-button>

        <repository-actions :repository="repository" :permissions="permissions" />

        <setup-drawer
          :open="showSetupDrawer"
          :name="repository.name"
          :format="repository.format"
          :kind="repository.kind"
          @close="showSetupDrawer = false"
        />
      </template>

      <template v-if="rendersRepository && repository.description" #description>
        <p class="gl-mb-0" data-testid="repository-description">
          {{ repository.description }}
        </p>
      </template>

      <gl-alert v-if="hasError" variant="danger" :dismissible="false">
        {{ $options.i18n.unavailable }}
      </gl-alert>

      <not-found v-else-if="isNotFound" />

      <template v-else-if="rendersRepository && isVirtual">
        <gl-skeleton-loader
          v-if="isLoadingUpstreamRepositories"
          :lines="3"
          data-testid="upstream-repositories-skeleton"
        />

        <gl-alert
          v-else-if="upstreamRepositoriesUnavailable"
          variant="danger"
          :dismissible="false"
          data-testid="upstream-repositories-error"
        >
          {{ upstreamRepositoriesMessage }}
        </gl-alert>

        <upstream-repositories-empty-state v-else-if="hasNoMainContent" />

        <upstream-repositories-table v-else :upstream-repositories="upstreamRows" />
      </template>

      <template v-else-if="rendersRepository">
        <artifacts-section
          :name="repository.name"
          :format="repository.format"
          :kind="repository.kind"
          :artifacts="artifacts"
          :loading="isLoadingArtifacts"
          :has-error="hasArtifactConnectionError"
          :permissions="permissions"
        />

        <div class="gl-mt-3 gl-flex gl-justify-center">
          <gl-keyset-pagination
            v-bind="pageInfo"
            @prev="pageTo({ before: $event })"
            @next="pageTo({ after: $event })"
          />
        </div>
      </template>

      <template v-if="rendersRepository" #sidebar>
        <repository-sidebar
          :repository="repository"
          :permissions="permissions"
          :hide-stats="hasNoMainContent"
          :upstream-repositories-count="upstreamRepositoriesCount"
        />
      </template>
    </detail-layout>
  </div>
</template>
