<script>
import { GlButton, GlButtonGroup, GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import { VIEW_GRID, VIEW_LIST, VIEW_MODE_KEY } from '../constants';
import cdApplicationsQuery from '../graphql/applications/cd_applications.query.graphql';
import ApplicationCard from './application_card.vue';
import ManageAccessPanel from './manage_access_panel.vue';
import NewApplicationPanel from './new_application_panel.vue';
import FilterBar from './shared/filter_bar.vue';

export default {
  name: 'ApplicationsIndex',
  components: {
    ApplicationCard,
    FilterBar,
    GlButton,
    GlButtonGroup,
    GlEmptyState,
    GlLoadingIcon,
    ManageAccessPanel,
    NewApplicationPanel,
    PageHeading,
  },
  data() {
    return {
      organization: null,
      isManageAccessPanelOpen: false,
      isPanelOpen: false,
      searchTerm: '',
      selectedApplication: null,
      viewMode: localStorage.getItem(VIEW_MODE_KEY) ?? VIEW_GRID,
    };
  },
  apollo: {
    organization: {
      query: cdApplicationsQuery,
      variables() {
        return {
          search: this.searchTerm.trim(),
        };
      },
    },
  },
  computed: {
    applications() {
      return this.organization?.cdApplications.nodes || [];
    },
    isGridView() {
      return this.viewMode === VIEW_GRID;
    },
    isLoading() {
      return this.$apollo.queries.organization.loading;
    },
    organizationId() {
      return this.organization?.id;
    },
    showFilterEmptyState() {
      return this.searchTerm;
    },
  },
  methods: {
    clearFilters() {
      this.searchTerm = '';
    },
    handleManageAccess(application) {
      this.selectedApplication = application;
      this.isPanelOpen = false;
      this.isManageAccessPanelOpen = true;
    },
    refetchQuery() {
      this.$apollo.queries.organization.refetch();
    },
    setGridView() {
      this.viewMode = VIEW_GRID;
      localStorage.setItem(VIEW_MODE_KEY, VIEW_GRID);
    },
    setListView() {
      this.viewMode = VIEW_LIST;
      localStorage.setItem(VIEW_MODE_KEY, VIEW_LIST);
    },
  },
};
</script>

<template>
  <div>
    <page-heading :heading="s__('ContinuousDeployment|Applications')">
      <template #actions>
        <gl-button-group>
          <gl-button
            icon="applications"
            :selected="isGridView"
            :aria-label="s__('ContinuousDeployment|Grid view')"
            data-testid="grid-view-button"
            @click="setGridView"
          />
          <gl-button
            icon="list-bulleted"
            :selected="!isGridView"
            :aria-label="s__('ContinuousDeployment|List view')"
            data-testid="list-view-button"
            @click="setListView"
          />
        </gl-button-group>
        <gl-button
          variant="confirm"
          data-testid="new-application-button"
          @click="isPanelOpen = true"
        >
          {{ s__('ContinuousDeployment|New application') }}
        </gl-button>
      </template>
    </page-heading>

    <filter-bar
      :search-placeholder="s__('ContinuousDeployment|Search by name or description')"
      :search-term="searchTerm"
      @search="searchTerm = $event"
    />

    <gl-loading-icon v-if="isLoading" size="lg" class="gl-mt-5" />

    <template v-else-if="applications.length">
      <!-- eslint-disable tailwindcss/no-arbitrary-value -->
      <div
        class="gl-mt-5 gl-gap-3"
        :class="{
          'gl-grid': isGridView,
          'gl-grid-cols-[repeat(auto-fill,minmax(16rem,1fr))]': isGridView,
        }"
      >
        <!-- eslint-enable tailwindcss/no-arbitrary-value -->
        <application-card
          v-for="application in applications"
          :key="application.id"
          :class="{ 'gl-mb-3': !isGridView }"
          :application="application"
          :is-grid-view="isGridView"
          @manage-access="handleManageAccess(application)"
        />
      </div>
    </template>

    <gl-empty-state
      v-else-if="showFilterEmptyState"
      illustration-name="empty-search-md"
      :title="s__('ContinuousDeployment|No applications match your filters')"
      :description="__('To widen your search, change or remove filters above.')"
    >
      <template #actions>
        <gl-button variant="confirm" @click="clearFilters">
          {{ s__('ContinuousDeployment|Clear filters') }}
        </gl-button>
      </template>
    </gl-empty-state>

    <gl-empty-state
      v-else
      illustration-name="empty-dashboard-md"
      :title="s__('ContinuousDeployment|No applications yet')"
      :description="
        s__(
          'ContinuousDeployment|Create applications to track them and deploy them to environments',
        )
      "
    >
      <template #actions>
        <gl-button variant="confirm" @click="isPanelOpen = true">
          {{ s__('ContinuousDeployment|New application') }}
        </gl-button>
      </template>
    </gl-empty-state>

    <new-application-panel
      :open="isPanelOpen"
      :organization-id="organizationId"
      @close="isPanelOpen = false"
      @create="refetchQuery"
    />

    <manage-access-panel
      :application="selectedApplication"
      :open="isManageAccessPanelOpen"
      @close="isManageAccessPanelOpen = false"
    />
  </div>
</template>
