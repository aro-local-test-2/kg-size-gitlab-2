import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlFormCheckbox, GlKeysetPagination, GlTable } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import EnableScannersSelectItems from 'ee/security_configuration/components/enable_scanners_wizard/select_items.vue';
import CheckboxCell from 'ee/security_inventory/components/checkbox_cell.vue';
import InventoryDashboardFilteredSearchBar from 'ee/security_inventory/components/inventory_dashboard_filtered_search_bar.vue';
import groupScannerDetailsProjectsQuery from 'ee/security_configuration/graphql/scan_profiles/group_scanner_details_projects.query.graphql';
import subgroupsAndProjectsQuery from 'ee/security_inventory/graphql/subgroups_and_projects.query.graphql';

jest.mock('~/alert');

Vue.use(VueApollo);

describe('EnableScannersSelectItems', () => {
  let wrapper;
  let enableScanners;

  const pageInfo = ({ hasNextPage = false, hasPreviousPage = false } = {}) => ({
    __typename: 'PageInfo',
    hasNextPage,
    hasPreviousPage,
    startCursor: hasPreviousPage ? 'start' : null,
    endCursor: hasNextPage ? 'end' : null,
  });

  const mockSubgroup = (id) => ({
    __typename: 'Group',
    id: `gid://gitlab/Group/${id}`,
    name: `Subgroup ${id}`,
    path: `subgroup-${id}`,
    fullPath: `group/subgroup-${id}`,
    avatarUrl: null,
    webUrl: `/group/subgroup-${id}`,
    updatedAt: null,
    descendantGroupsCount: 0,
    projectsCount: 1,
    analyzerStatuses: [],
    vulnerabilityNamespaceStatistic: null,
  });

  const mockProject = (id) => ({
    id: `gid://gitlab/Project/${id}`,
    avatarUrl: null,
    name: `Project ${id}`,
    fullPath: `group/project-${id}`,
    group: { id: 'gid://gitlab/Group/1', name: 'Group', webPath: '/group' },
    securityConfigurationPath: `/group/project-${id}/-/security/configuration`,
    securityScanProfiles: [],
    analyzerStatuses: [],
    scanProfileStatuses: [],
    securityAttributes: { nodes: [] },
    __typename: 'Project',
  });

  const subgroups = [mockSubgroup(1), mockSubgroup(2)];
  const projects = [mockProject(1), mockProject(2)];

  const projectsResponse = ({ nodes = projects, projectsPageInfo = pageInfo() } = {}) => ({
    data: {
      namespaceSecurityProjects: {
        __typename: 'NamespaceSecurityProjectConnection',
        pageInfo: projectsPageInfo,
        nodes,
      },
    },
  });

  const subgroupsResponse = ({ nodes = subgroups, groupsPageInfo = pageInfo() } = {}) => ({
    data: {
      group: {
        __typename: 'Group',
        id: 'gid://gitlab/Group/1',
        descendantGroups: {
          __typename: 'GroupConnection',
          pageInfo: groupsPageInfo,
          nodes,
        },
        projects: {
          __typename: 'ProjectConnection',
          pageInfo: pageInfo(),
          nodes: [],
        },
      },
    },
  });

  const createComponent = ({
    canReadAttributes = true,
    combinedPaginationEnabled = true,
    selectedItems = [],
    toggleItem = jest.fn(),
    toggleVisibleItems = jest.fn(),
    subgroupsHandler = jest.fn().mockResolvedValue(subgroupsResponse()),
    projectsHandler = jest.fn().mockResolvedValue(projectsResponse()),
  } = {}) => {
    enableScanners = { selectedItems, toggleItem, toggleVisibleItems };

    wrapper = mountExtended(EnableScannersSelectItems, {
      apolloProvider: createMockApollo([
        [subgroupsAndProjectsQuery, subgroupsHandler],
        [groupScannerDetailsProjectsQuery, projectsHandler],
      ]),
      provide: {
        groupFullPath: 'group/path',
        groupId: 1,
        canReadAttributes,
        enableScanners,
        glFeatures: { combinedPaginationInScannerWizard: combinedPaginationEnabled },
      },
      stubs: {
        GlTable: stubComponent(GlTable, {
          props: ['items', 'fields', 'busy'],
          template: `
            <div>
              <slot name="head(checkbox)" />
              <div v-for="(item, index) in items" :key="index">
                <slot name="cell(checkbox)" :item="item" />
              </div>
            </div>
          `,
        }),
        GlDisclosureDropdown: true,
        GlDisclosureDropdownItem: true,
        InventoryDashboardFilteredSearchBar: true,
        NameCell: true,
        ToolCoverageCell: true,
        AttributesCell: true,
      },
    });
  };

  const findSearchBar = () => wrapper.findComponent(InventoryDashboardFilteredSearchBar);
  const findSelectAllCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findItemCheckboxes = () => wrapper.findAllComponents(CheckboxCell);
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findWarningIcon = () => wrapper.findByTestId('warning-icon');

  describe.each`
    combinedPaginationEnabled | visibleItems                   | includeSubgroups | subgroupsRequested
    ${true}                   | ${[...subgroups, ...projects]} | ${false}         | ${true}
    ${false}                  | ${projects}                    | ${true}          | ${false}
  `(
    'with combinedPaginationInScannerWizard = $combinedPaginationEnabled',
    ({ combinedPaginationEnabled, visibleItems, includeSubgroups, subgroupsRequested }) => {
      it('lists the visible items in order', async () => {
        createComponent({ combinedPaginationEnabled });
        await waitForPromises();

        const checkboxIds = findItemCheckboxes().wrappers.map(
          (checkbox) => checkbox.props('item').id,
        );

        expect(checkboxIds).toEqual(visibleItems.map((item) => item.id));
      });

      it('requests projects with the correct subgroup scope while browsing', async () => {
        const projectsHandler = jest.fn().mockResolvedValue(projectsResponse());
        createComponent({ combinedPaginationEnabled, projectsHandler });
        await waitForPromises();

        expect(projectsHandler).toHaveBeenCalledWith(expect.objectContaining({ includeSubgroups }));
      });

      it('only fetches subgroups when combined pagination is enabled', async () => {
        const subgroupsHandler = jest.fn().mockResolvedValue(subgroupsResponse());
        createComponent({ combinedPaginationEnabled, subgroupsHandler });
        await waitForPromises();

        if (subgroupsRequested) {
          expect(subgroupsHandler).toHaveBeenCalled();
        } else {
          expect(subgroupsHandler).not.toHaveBeenCalled();
        }
      });
    },
  );

  describe('filtering', () => {
    const filters = {
      search: 'my term',
      securityAnalyzerFilters: [{ analyzerType: 'SAST' }],
      vulnerabilityCountFilters: [{ severity: 'HIGH' }],
      attributeFilters: [{ id: 'gid://gitlab/Attribute/1' }],
    };

    it('passes the active search and filter values as query variables', async () => {
      const projectsHandler = jest.fn().mockResolvedValue(projectsResponse());
      createComponent({ projectsHandler });
      await waitForPromises();

      findSearchBar().vm.$emit('filter-subgroups-and-projects', filters);
      await waitForPromises();

      expect(projectsHandler).toHaveBeenLastCalledWith(expect.objectContaining(filters));
    });

    it('skips subgroups and searches all descendants when a filter is active', async () => {
      const subgroupsHandler = jest.fn().mockResolvedValue(subgroupsResponse());
      const projectsHandler = jest.fn().mockResolvedValue(projectsResponse());
      createComponent({ subgroupsHandler, projectsHandler });
      await waitForPromises();

      subgroupsHandler.mockClear();
      findSearchBar().vm.$emit('filter-subgroups-and-projects', filters);
      await waitForPromises();

      expect(subgroupsHandler).not.toHaveBeenCalled();
      expect(projectsHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ includeSubgroups: true }),
      );
    });
  });

  describe('pagination', () => {
    it('is hidden when there are no further pages', async () => {
      createComponent();
      await waitForPromises();

      expect(findPagination().exists()).toBe(false);
    });

    it('is shown when a resource has a next page', async () => {
      const projectsHandler = jest
        .fn()
        .mockResolvedValue(projectsResponse({ projectsPageInfo: pageInfo({ hasNextPage: true }) }));
      createComponent({ projectsHandler });
      await waitForPromises();

      expect(findPagination().props('hasNextPage')).toBe(true);
    });

    it('fetches the next page on next', async () => {
      const projectsHandler = jest
        .fn()
        .mockResolvedValue(projectsResponse({ projectsPageInfo: pageInfo({ hasNextPage: true }) }));
      createComponent({ projectsHandler });
      await waitForPromises();

      projectsHandler.mockClear();
      findPagination().vm.$emit('next');
      await waitForPromises();

      expect(projectsHandler).toHaveBeenCalled();
    });
  });

  describe('error handling', () => {
    it('shows an alert when fetching fails', async () => {
      const subgroupsHandler = jest.fn().mockRejectedValue(new Error('nope'));
      createComponent({ subgroupsHandler });
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'An error occurred while fetching subgroups and projects. Please try again.',
        }),
      );
    });
  });

  describe('selection summary', () => {
    it('shows a count of selected items', () => {
      createComponent({ selectedItems: [projects[0], projects[1]] });

      expect(wrapper.text()).toContain('2 items selected');
      expect(findWarningIcon().exists()).toBe(false);
    });

    it('shows a warning icon when the selection limit is reached', () => {
      const selectedItems = Array.from({ length: 100 }, (_, i) => mockProject(i));
      createComponent({ selectedItems });

      expect(findWarningIcon().exists()).toBe(true);
    });
  });

  describe('select-all checkbox', () => {
    it('calls toggleVisibleItems with the visible items on change', async () => {
      const toggleVisibleItems = jest.fn();

      createComponent({ toggleVisibleItems });
      await waitForPromises();

      findSelectAllCheckbox().vm.$emit('change', true);

      expect(toggleVisibleItems).toHaveBeenCalledWith(true, [...subgroups, ...projects]);
    });
  });

  describe('item checkbox', () => {
    it('calls toggleItem on change', async () => {
      const toggleItem = jest.fn();

      createComponent({ toggleItem });
      await waitForPromises();

      const checkbox = findItemCheckboxes().at(0);
      const item = checkbox.props('item');

      checkbox.vm.$emit('select-item', item, true);

      expect(toggleItem).toHaveBeenCalledWith(item, true);
    });

    it('is checked when the item is in selectedItems', async () => {
      createComponent({ selectedItems: [{ id: subgroups[0].id }] });
      await waitForPromises();

      expect(findItemCheckboxes().at(0).props('isSelected')).toBe(true);
    });

    it('is disabled when the selection limit is reached', async () => {
      const selectedItems = Array.from({ length: 100 }, (_, i) => mockProject(i));
      createComponent({ selectedItems });
      await waitForPromises();

      expect(findItemCheckboxes().at(0).props('isSelectedLimitReached')).toBe(true);
    });
  });
});
