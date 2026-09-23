<script>
import { uniqBy, get } from 'lodash-es';
import produce from 'immer';
import { __ } from '~/locale';
import BaseItemsDropdown from 'ee/security_orchestration/components/shared/base_items_dropdown.vue';
import ProjectsCountMessage from 'ee/security_orchestration/components/shared/projects_count_message.vue';
import {
  PROJECT_DROPDOWN_I18N,
  createDebouncedSearch,
  normalizeSearchTerm,
  projectsToListboxItems,
  getDropdownCategory,
  getDropdownVariant,
  getProjectsText,
  filterExistingSelectedIds,
  SHARED_DROPDOWN_PROPS,
} from 'ee/security_orchestration/components/shared/project_dropdown_utils';

// Source-agnostic projects selector: the caller supplies the query, the path
// to its connection in the response, and the variables identifying the
// container (a group's fullPath, an organization's id, ...). The query must
// accept `search`, `after`, `projectIds` and `withCount` the way
// get_group_projects.query.graphql does. The source props are read for the
// life of the mount — a caller that changes them in place must re-key the
// component, or stale projects from the previous source stay listed.
export default {
  i18n: PROJECT_DROPDOWN_I18N,
  name: 'BaseProjectsDropdown',
  itemTypeName: __('projects'),
  components: {
    BaseItemsDropdown,
    ProjectsCountMessage,
  },
  apollo: {
    projects: {
      query() {
        return this.query;
      },
      variables() {
        return this.reactiveVariables;
      },
      update(data) {
        // Preserve already-loaded projects so a backend search cannot drop a
        // selected item from the list.
        const nodes = get(data, `${this.responsePath}.nodes`, []);
        return uniqBy([...this.projects, ...nodes], 'id');
      },
      result({ data }) {
        this.pageInfo = get(data, `${this.responsePath}.pageInfo`, {});
        if (!this.allProjectsCountSaved) {
          this.allProjectsCount = get(data, `${this.responsePath}.count`, 0);
        }

        if (this.selectedButNotLoadedProjectIds.length > 0) {
          this.fetchProjectsByIds();
        }
      },
      error() {
        this.$emit('projects-query-error');
      },
    },
  },
  props: {
    ...SHARED_DROPDOWN_PROPS,
    query: {
      type: Object,
      required: true,
    },
    responsePath: {
      type: String,
      required: true,
    },
    pathVariables: {
      type: Object,
      required: true,
    },
    multiple: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['projects-query-error', 'select'],
  data() {
    return {
      pageInfo: {},
      searchTerm: '',
      projects: [],
      allProjectsCount: 0,
    };
  },
  computed: {
    allProjectsCountSaved() {
      return this.allProjectsCount > 0;
    },
    projectIds() {
      return this.projects.map(({ id }) => id);
    },
    selectedButNotLoadedProjectIds() {
      const selected = this.multiple ? this.selected : [this.selected];
      return selected.filter((id) => !this.projectIds.includes(id));
    },
    showFooter() {
      return this.withProjectCount && !this.loading;
    },
    allProjectsLoaded() {
      return this.projects.length === this.allProjectsCount;
    },
    projectsText() {
      return getProjectsText(this.allProjectsCount);
    },
    existingFormattedSelectedIds() {
      if (this.multiple) {
        return filterExistingSelectedIds(this.selected, this.projectIds);
      }

      return this.selected;
    },
    loading() {
      return this.$apollo.queries.projects.loading;
    },
    searching() {
      return this.loading && this.searchUsed && !this.hasNextPage;
    },
    searchUsed() {
      return this.searchTerm !== '';
    },
    hasNextPage() {
      return this.pageInfo.hasNextPage;
    },
    listBoxItems() {
      return projectsToListboxItems(this.projects, this.searchTerm);
    },
    category() {
      return getDropdownCategory(this.state);
    },
    variant() {
      return getDropdownVariant(this.state);
    },
    queryVariables() {
      return { ...this.pathVariables, withCount: this.withProjectCount };
    },
    reactiveVariables() {
      if (this.allProjectsLoaded) {
        return this.queryVariables;
      }

      return {
        ...this.queryVariables,
        search: this.searchTerm,
      };
    },
  },
  created() {
    this.debouncedSearch = createDebouncedSearch(this.setSearchTerm);
  },
  destroyed() {
    this.debouncedSearch.cancel();
  },
  methods: {
    async fetchProjectsByIds() {
      const variables = {
        after: this.pageInfo.endCursor,
        projectIds: this.selectedButNotLoadedProjectIds,
        ...this.queryVariables,
      };

      try {
        const { data } = await this.$apollo.query({
          query: this.query,
          variables,
        });
        const { nodes = [] } = get(data, this.responsePath) || {};
        this.projects = uniqBy([...this.projects, ...nodes], 'id');
      } catch {
        this.$emit('projects-query-error');
      }
    },
    fetchMoreItems() {
      const { responsePath } = this;
      const variables = {
        after: this.pageInfo.endCursor,
        ...this.queryVariables,
      };

      this.$apollo.queries.projects
        .fetchMore({
          variables,
          updateQuery(previousResult, { fetchMoreResult }) {
            return produce(fetchMoreResult, (draftData) => {
              const previousNodes = get(previousResult, `${responsePath}.nodes`, []);
              const newNodes = get(draftData, `${responsePath}.nodes`, []);

              get(draftData, responsePath).nodes = [...previousNodes, ...newNodes];
            });
          },
        })
        .catch(() => {
          this.$emit('projects-query-error');
        });
    },
    setSearchTerm(searchTerm) {
      this.searchTerm = normalizeSearchTerm(searchTerm);
    },
    selectItems(selected) {
      const ids = this.multiple ? selected : [selected];
      const selectedItems = this.projects.filter(({ id }) => ids.includes(id));
      const payload = this.multiple ? selectedItems : selectedItems[0];
      this.$emit('select', payload);
    },
  },
};
</script>

<template>
  <base-items-dropdown
    :category="category"
    :variant="variant"
    :disabled="disabled"
    :multiple="multiple"
    :loading="loading"
    :header-text="$options.i18n.projectDropdownHeader"
    :items="listBoxItems"
    :infinite-scroll="hasNextPage"
    :searching="searching"
    :selected="existingFormattedSelectedIds"
    :placement="placement"
    :item-type-name="$options.itemTypeName"
    @bottom-reached="fetchMoreItems"
    @search="debouncedSearch"
    @reset="selectItems([])"
    @select="selectItems"
    @select-all="selectItems"
  >
    <template v-if="showFooter" #footer>
      <div
        class="gl-border-t gl-flex gl-items-center gl-gap-3 gl-px-4 gl-py-3"
        data-testid="footer"
      >
        <projects-count-message
          :count="listBoxItems.length"
          :info-text="projectsText"
          :total-count="allProjectsCount"
          :show-info-icon="!allProjectsLoaded"
        />
      </div>
    </template>
  </base-items-dropdown>
</template>
