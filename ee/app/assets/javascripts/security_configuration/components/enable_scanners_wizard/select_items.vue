<script>
import {
  GlTable,
  GlFormCheckbox,
  GlIcon,
  GlSprintf,
  GlTooltipDirective,
  GlKeysetPagination,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
} from '@gitlab/ui';
import { __, s__, n__, sprintf } from '~/locale';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_GROUP } from '~/graphql_shared/constants';
import { smoothScrollTop } from '~/lib/utils/scroll_utils';
import { createAlert } from '~/alert';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import SequentialCursorPaginator from '~/vue_shared/utils/sequential_cursor_pagination';
import groupScannerDetailsProjectsQuery from 'ee/security_configuration/graphql/scan_profiles/group_scanner_details_projects.query.graphql';
import subgroupsAndProjectsQuery from 'ee/security_inventory/graphql/subgroups_and_projects.query.graphql';
import InventoryDashboardFilteredSearchBar from 'ee/security_inventory/components/inventory_dashboard_filtered_search_bar.vue';
import NameCell from 'ee/security_inventory/components/name_cell.vue';
import CheckboxCell from 'ee/security_inventory/components/checkbox_cell.vue';
import ToolCoverageCell from 'ee/security_inventory/components/tool_coverage_cell.vue';
import AttributesCell from 'ee/security_inventory/components/attributes_cell.vue';
import { isSubGroup } from 'ee/security_inventory/utils';
import { MAX_SELECTED_COUNT } from 'ee/security_inventory/constants';

const DEFAULT_PAGE_SIZE = 20;

export default {
  name: 'EnableScannersSelectItems',
  components: {
    GlTable,
    GlFormCheckbox,
    GlIcon,
    GlSprintf,
    GlKeysetPagination,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    InventoryDashboardFilteredSearchBar,
    NameCell,
    CheckboxCell,
    ToolCoverageCell,
    AttributesCell,
    HelpPopover,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagMixin()],
  inject: ['groupFullPath', 'groupId', 'canReadAttributes', 'enableScanners'],
  i18n: {
    errorFetchingItems: s__(
      'SecurityConfiguration|An error occurred while fetching subgroups and projects. Please try again.',
    ),
  },
  apollo: {
    // Legacy pagination (combined pagination disabled)
    // Skip this query when combined pagination is enabled
    itemsData: {
      query: groupScannerDetailsProjectsQuery,
      skip() {
        return this.combinedPaginationEnabled;
      },
      variables() {
        const {
          search = '',
          securityAnalyzerFilters = [],
          vulnerabilityCountFilters = [],
          attributeFilters = [],
        } = this.filters;
        return {
          fullPath: this.groupFullPath,
          namespaceId: convertToGraphQLId(TYPENAME_GROUP, this.groupId),
          first: this.before ? null : DEFAULT_PAGE_SIZE,
          after: this.after,
          last: this.before ? DEFAULT_PAGE_SIZE : null,
          before: this.before,
          search,
          securityAnalyzerFilters,
          vulnerabilityCountFilters,
          attributeFilters,
          canReadAttributes: this.canReadAttributes,
          includeSubgroups: true,
        };
      },
      update: (data) => data?.namespaceSecurityProjects,
    },
  },
  data() {
    return {
      filters: {},

      // Legacy pagination state (combined pagination disabled)
      itemsData: {},
      after: null,
      before: null,

      // Combined pagination state (combined pagination enabled)
      currentPage: [],
      hasNextPage: false,
      hasPreviousPage: false,
      isPaginatorLoading: false,
    };
  },
  computed: {
    selectedItems() {
      return this.enableScanners.selectedItems;
    },
    combinedPaginationEnabled() {
      return this.glFeatures.combinedPaginationInScannerWizard;
    },
    hasFilters() {
      return Boolean(
        this.filters.search?.length ||
        this.filters.securityAnalyzerFilters?.length ||
        this.filters.vulnerabilityCountFilters?.length ||
        this.filters.attributeFilters?.length,
      );
    },
    variables() {
      const {
        search = '',
        securityAnalyzerFilters = [],
        vulnerabilityCountFilters = [],
        attributeFilters = [],
      } = this.filters;
      return {
        fullPath: this.groupFullPath,
        namespaceId: convertToGraphQLId(TYPENAME_GROUP, this.groupId),
        search,
        securityAnalyzerFilters,
        vulnerabilityCountFilters,
        attributeFilters,
        canReadAttributes: this.canReadAttributes,
        // Unfiltered list shows direct descendant projects only
        // Filtering searches all projects, including those in subgroups
        includeSubgroups: this.hasFilters,
      };
    },
    selectedCountMessage() {
      const selectedCount = this.selectedItems.length;
      return sprintf(
        n__(
          '%{strongStart}%{selectedCount}%{strongEnd} item selected',
          '%{strongStart}%{selectedCount}%{strongEnd} items selected',
          selectedCount,
        ),
        { selectedCount },
      );
    },
    isLoading() {
      return this.combinedPaginationEnabled
        ? this.isPaginatorLoading
        : this.$apollo.queries.itemsData.loading;
    },
    items() {
      return this.combinedPaginationEnabled ? this.currentPage : (this.itemsData?.nodes ?? []);
    },
    pageInfo() {
      return this.combinedPaginationEnabled
        ? {
            hasNextPage: this.hasNextPage,
            hasPreviousPage: this.hasPreviousPage,
            disabled: this.isLoading,
          }
        : (this.itemsData?.pageInfo ?? {});
    },
    isAnyItemSelected() {
      return this.items.some((item) => this.isItemSelected(item));
    },
    areAllItemsSelected() {
      return this.items.every((item) => this.isItemSelected(item));
    },
    isSelectedLimitReached() {
      return this.selectedItems.length >= MAX_SELECTED_COUNT;
    },
    fields() {
      return [
        {
          key: 'checkbox',
          label: '',
          thClass: 'gl-w-0',
          tdClass: '!gl-bg-default !gl-align-middle',
        },
        { key: 'name', label: __('Item'), tdClass: '!gl-bg-default', thClass: 'gl-w-1/3' },
        {
          key: 'toolCoverage',
          label: s__('SecurityConfiguration|Scanner coverage'),
          tdClass: '!gl-bg-default !gl-align-middle',
          thClass: 'gl-w-1/3',
        },
        ...(this.canReadAttributes
          ? [
              {
                key: 'securityAttributes',
                label: __('Security attributes'),
                tdClass: '!gl-bg-default !gl-align-middle',
                thClass: 'gl-w-1/3',
              },
            ]
          : []),
        {
          key: 'actions',
          label: '',
          thClass: 'gl-w-0',
          tdClass: '!gl-bg-default !gl-align-middle',
        },
      ];
    },
  },
  created() {
    // Paginator should only be initialized when combined pagination is enabled
    if (!this.combinedPaginationEnabled) return;

    const resources = [
      {
        query: subgroupsAndProjectsQuery,
        skip: () => this.hasFilters,
        first: 'subgroupsFirst',
        last: 'subgroupsLast',
        after: 'subgroupsAfter',
        before: 'subgroupsBefore',
        getNodes: (result) => result.data.group.descendantGroups.nodes,
        getPageInfo: (result) => result.data.group.descendantGroups.pageInfo,
        baseVariables: { projectsFirst: 0 },
      },
      {
        query: groupScannerDetailsProjectsQuery,
        first: 'first',
        last: 'last',
        after: 'after',
        before: 'before',
        getNodes: (result) => result.data.namespaceSecurityProjects.nodes,
        getPageInfo: (result) => result.data.namespaceSecurityProjects.pageInfo,
      },
    ];

    this.paginator = new SequentialCursorPaginator(this.$apollo, resources, DEFAULT_PAGE_SIZE);
  },
  async mounted() {
    if (!this.combinedPaginationEnabled) return;
    await this.loadPage(() => this.paginator.getNextCombinedPage(this.variables));
  },
  methods: {
    isItemSelected(item) {
      return this.selectedItems.some(({ id }) => id === item.id);
    },
    async loadPage(paginationFn) {
      this.isPaginatorLoading = true;
      try {
        smoothScrollTop();
        this.currentPage = await paginationFn();
        this.hasNextPage = this.paginator.hasNextPage();
        this.hasPreviousPage = this.paginator.hasPreviousPage();
      } catch (error) {
        createAlert({ message: this.$options.i18n.errorFetchingItems, error, captureError: true });
      } finally {
        this.isPaginatorLoading = false;
      }
    },
    handleFilter(filters) {
      this.filters = filters;
      if (this.combinedPaginationEnabled) {
        this.loadPage(() => this.paginator.reset(this.variables));
      } else {
        this.after = null;
        this.before = null;
      }
    },
    handleNext(endCursor) {
      if (this.combinedPaginationEnabled) {
        this.loadPage(() => this.paginator.getNextCombinedPage(this.variables));
      } else {
        this.after = endCursor;
        this.before = null;
        smoothScrollTop();
      }
    },
    handlePrev(startCursor) {
      if (this.combinedPaginationEnabled) {
        this.loadPage(() => this.paginator.getPreviousCombinedPage(this.variables));
      } else {
        this.before = startCursor;
        this.after = null;
        smoothScrollTop();
      }
    },
    viewItemAction(item) {
      return {
        text: isSubGroup(item) ? __('View group') : __('View project'),
        icon: 'external-link',
        href: `/${item.fullPath}`,
        extraAttrs: { target: '_blank' },
      };
    },
  },
  MAX_SELECTED_COUNT,
};
</script>
<template>
  <div>
    <inventory-dashboard-filtered-search-bar
      :namespace="groupFullPath"
      class="gl-mb-4"
      @filter-subgroups-and-projects="handleFilter"
    />

    <div
      class="gl-border-b gl-sticky gl-top-0 gl-z-2 gl-mb-5 gl-flex gl-items-center gl-justify-between gl-bg-default gl-px-3 gl-py-4"
    >
      <span>
        <gl-sprintf :message="selectedCountMessage">
          <template #strong="{ content }">
            <strong>{{ content }}</strong>
          </template>
        </gl-sprintf>
        <gl-icon
          v-if="isSelectedLimitReached"
          v-gl-tooltip="
            sprintf(__('You can select up to %{maximumCount} items at once'), {
              maximumCount: $options.MAX_SELECTED_COUNT,
            })
          "
          name="warning"
          variant="warning"
          class="gl-ml-1"
        />
      </span>
    </div>

    <gl-table
      :fields="fields"
      :items="items"
      :busy="isLoading"
      table-class="!gl-bg-strong gl-rounded-xl"
      show-empty
      borderless
    >
      <template #head(checkbox)>
        <gl-form-checkbox
          v-gl-tooltip.right
          :title="__('Select all items')"
          :checked="isAnyItemSelected"
          :indeterminate="isAnyItemSelected && !areAllItemsSelected"
          :disabled="isLoading || isSelectedLimitReached"
          class="gl-min-h-4"
          @change="(selected) => enableScanners.toggleVisibleItems(selected, items)"
        />
      </template>
      <template #head(toolCoverage)="{ label }">
        {{ label }}
        <help-popover class="gl-ml-2">
          {{
            s__(
              'SecurityConfiguration|Shows scanner coverage across all configuration methods, including security policies and CI configuration.',
            )
          }}
        </help-popover>
      </template>
      <template #cell(checkbox)="{ item }">
        <checkbox-cell
          v-if="!isLoading"
          :item="item"
          :is-selected="isItemSelected(item)"
          :is-selected-limit-reached="isSelectedLimitReached"
          @select-item="enableScanners.toggleItem"
        />
      </template>
      <template #cell(name)="{ item }">
        <name-cell :item="item" :link-subgroups="false" />
      </template>
      <template #cell(toolCoverage)="{ item }">
        <tool-coverage-cell :item="item" />
      </template>
      <template #cell(securityAttributes)="{ item, index }">
        <attributes-cell :item="item" :index="index" />
      </template>
      <template #cell(actions)="{ item }">
        <gl-disclosure-dropdown
          category="tertiary"
          size="small"
          icon="ellipsis_v"
          :toggle-text="__('More actions')"
          text-sr-only
          no-caret
        >
          <gl-disclosure-dropdown-item :item="viewItemAction(item)" />
        </gl-disclosure-dropdown>
      </template>
    </gl-table>

    <div
      v-if="pageInfo.hasNextPage || pageInfo.hasPreviousPage"
      class="gl-mt-5 gl-flex gl-justify-center"
    >
      <gl-keyset-pagination v-bind="pageInfo" @prev="handlePrev" @next="handleNext" />
    </div>
  </div>
</template>
