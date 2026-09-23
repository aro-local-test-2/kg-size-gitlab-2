<script>
import { GlCollapsibleListbox, GlFormGroup } from '@gitlab/ui';
import { produce } from 'immer';
import { debounce } from 'lodash-es';
import { s__ } from '~/locale';
import { SEARCH_DEBOUNCE_MS } from '~/vue_shared/components/ref/constants';
import getNamespaces from './graphql/queries/get_groups.query.graphql';
import { NAMESPACES_PAGE_SIZE } from './constants';

export default {
  name: 'NamespaceSelector',
  components: { GlCollapsibleListbox, GlFormGroup },
  props: {
    selectedNamespaceId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['select'],
  data() {
    return {
      shouldFetch: false,
      namespaces: [],
      pageInfo: null,
      isLoadingMore: false,
      searchTerm: '',
      isError: false,
    };
  },
  apollo: {
    namespaces: {
      query: getNamespaces,
      variables() {
        return { search: this.searchTerm, first: NAMESPACES_PAGE_SIZE };
      },
      // The resolver behind this query loads every matching group into memory, so
      // nothing is fetched until the listbox is actually opened.
      skip() {
        return !this.shouldFetch;
      },
      update(data) {
        this.isError = false;
        this.pageInfo = data?.adminDuoAvailabilityNamespaces?.pageInfo ?? null;

        return data?.adminDuoAvailabilityNamespaces?.nodes ?? [];
      },
      error() {
        this.isError = true;
      },
    },
  },
  computed: {
    isLoadingNamespaces() {
      return this.$apollo.queries.namespaces.loading;
    },
    hasNextPage() {
      return Boolean(this.pageInfo?.hasNextPage);
    },
    listboxItems() {
      return this.namespaces.map(({ id, name, fullPath }) => ({
        value: id,
        text: name,
        fullPath,
      }));
    },
    selectedNamespace() {
      return this.namespaces.find(({ id }) => id === this.selectedNamespaceId);
    },
    toggleText() {
      return this.selectedNamespace?.fullPath || s__('AiPowered|Select a group');
    },
    noResultsText() {
      return this.isError
        ? s__('AiPowered|Failed to load groups')
        : s__('AiPowered|No groups found');
    },
  },
  created() {
    this.debouncedSearch = debounce((searchTerm) => {
      this.searchTerm = searchTerm;
    }, SEARCH_DEBOUNCE_MS);
  },
  methods: {
    onDropdownShown() {
      this.shouldFetch = true;
    },
    onSelect(namespaceId) {
      this.$emit(
        'select',
        this.namespaces.find(({ id }) => id === namespaceId),
      );
    },
    async onBottomReached() {
      if (!this.hasNextPage || this.isLoadingMore) return;

      this.isLoadingMore = true;

      try {
        await this.$apollo.queries.namespaces.fetchMore({
          variables: {
            search: this.searchTerm,
            first: NAMESPACES_PAGE_SIZE,
            after: this.pageInfo.endCursor,
          },
          updateQuery: (previousResult, { fetchMoreResult }) =>
            produce(fetchMoreResult, (draftData) => {
              draftData.adminDuoAvailabilityNamespaces.nodes = [
                ...previousResult.adminDuoAvailabilityNamespaces.nodes,
                ...fetchMoreResult.adminDuoAvailabilityNamespaces.nodes,
              ];
            }),
        });
      } finally {
        this.isLoadingMore = false;
      }
    },
  },
};
</script>

<template>
  <gl-form-group
    :label="__('Group')"
    label-for="duo-enabled-group-selector"
    class="gl-mb-0"
    label-sr-only
  >
    <gl-collapsible-listbox
      id="duo-enabled-group-selector"
      :items="listboxItems"
      :selected="selectedNamespaceId"
      :searching="isLoadingNamespaces"
      :toggle-text="toggleText"
      :no-results-text="noResultsText"
      :header-text="s__('AiPowered|Select a group')"
      :infinite-scroll="hasNextPage"
      :infinite-scroll-loading="isLoadingMore"
      icon="group"
      fluid-width
      searchable
      data-testid="functional-verification-namespace-selector"
      @shown="onDropdownShown"
      @search="debouncedSearch"
      @select="onSelect"
      @bottom-reached="onBottomReached"
    >
      <template #list-item="{ item }">
        <div class="gl-flex gl-flex-col">
          <span class="gl-break-words gl-font-bold">{{ item.text }}</span>
          <span class="gl-truncate gl-text-sm gl-text-subtle">{{ item.fullPath }}</span>
        </div>
      </template>
    </gl-collapsible-listbox>
  </gl-form-group>
</template>
