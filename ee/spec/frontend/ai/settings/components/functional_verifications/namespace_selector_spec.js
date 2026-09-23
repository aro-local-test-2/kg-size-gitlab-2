import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import NamespaceSelector from 'ee/ai/settings/components/functional_verifications/namespace_selector.vue';
import getNamespacesQuery from 'ee/ai/settings/components/functional_verifications/graphql/queries/get_groups.query.graphql';
import { NAMESPACES_PAGE_SIZE } from 'ee/ai/settings/components/functional_verifications/constants';

Vue.use(VueApollo);

const mockGroup1 = { id: 'gid://gitlab/Group/1', name: 'Group A', fullPath: 'group-a' };
const mockGroup2 = { id: 'gid://gitlab/Group/2', name: 'Group B', fullPath: 'group-b' };

const pageInfo = (overrides = {}) => ({
  __typename: 'PageInfo',
  hasNextPage: false,
  hasPreviousPage: false,
  startCursor: null,
  endCursor: null,
  ...overrides,
});

const mockGroupsResponse = {
  data: {
    adminDuoAvailabilityNamespaces: {
      nodes: [mockGroup1, mockGroup2],
      pageInfo: pageInfo(),
    },
  },
};

const groupsSuccessHandler = jest.fn().mockResolvedValue(mockGroupsResponse);

describe('NamespaceSelector', () => {
  let wrapper;

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);

  const createComponent = ({ groupsHandler = groupsSuccessHandler, propsData = {} } = {}) => {
    wrapper = shallowMount(NamespaceSelector, {
      apolloProvider: createMockApollo([[getNamespacesQuery, groupsHandler]]),
      propsData,
    });
  };

  const triggerDropdown = async () => {
    findListbox().vm.$emit('shown');
    await nextTick();
  };

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the collapsible listbox', () => {
      expect(findListbox().exists()).toBe(true);
    });

    it('renders the listbox with correct initial toggle text', () => {
      expect(findListbox().props('toggleText')).toBe('Select a group');
    });
  });

  describe('group search', () => {
    it('fetches groups when dropdown is shown', async () => {
      createComponent();
      await triggerDropdown();

      expect(groupsSuccessHandler).toHaveBeenCalledWith({
        search: '',
        first: NAMESPACES_PAGE_SIZE,
      });
    });

    it('includes the search term in query variables', async () => {
      createComponent();
      await triggerDropdown();

      findListbox().vm.$emit('search', 'test');
      await waitForPromises();

      expect(groupsSuccessHandler).toHaveBeenCalledWith({
        search: 'test',
        first: NAMESPACES_PAGE_SIZE,
      });
    });
  });

  describe('when no groups are found', () => {
    it('displays no results text', async () => {
      const emptyHandler = jest.fn().mockResolvedValue({
        data: { adminDuoAvailabilityNamespaces: { nodes: [], pageInfo: pageInfo() } },
      });

      createComponent({ groupsHandler: emptyHandler });
      await triggerDropdown();
      await waitForPromises();

      expect(findListbox().props('noResultsText')).toBe('No groups found');
    });
  });

  describe('listbox items', () => {
    beforeEach(async () => {
      createComponent();
      await triggerDropdown();
      await waitForPromises();
    });

    it('renders listbox items with correct structure', () => {
      expect(findListbox().props('items')).toEqual([
        { value: mockGroup1.id, text: mockGroup1.name, fullPath: mockGroup1.fullPath },
        { value: mockGroup2.id, text: mockGroup2.name, fullPath: mockGroup2.fullPath },
      ]);
    });
  });

  describe('selecting a group', () => {
    beforeEach(async () => {
      createComponent();
      await triggerDropdown();
      await waitForPromises();
    });

    it('emits select with the selected group', async () => {
      findListbox().vm.$emit('select', mockGroup1.id);
      await nextTick();

      expect(wrapper.emitted('select')).toEqual([[mockGroup1]]);
    });
  });

  describe('selectedNamespaceId prop', () => {
    it('shows the selected group fullPath as toggle text', async () => {
      createComponent({ propsData: { selectedNamespaceId: mockGroup2.id } });
      await triggerDropdown();
      await waitForPromises();

      expect(findListbox().props('toggleText')).toBe(mockGroup2.fullPath);
    });
  });

  describe('pagination', () => {
    const firstPageResponse = {
      data: {
        adminDuoAvailabilityNamespaces: {
          nodes: [mockGroup1],
          pageInfo: pageInfo({ hasNextPage: true, endCursor: 'cursor-1' }),
        },
      },
    };
    const secondPageResponse = {
      data: {
        adminDuoAvailabilityNamespaces: {
          nodes: [mockGroup2],
          pageInfo: pageInfo({ hasNextPage: false, endCursor: 'cursor-2' }),
        },
      },
    };

    const createPaginatedComponent = () => {
      const handler = jest
        .fn()
        .mockResolvedValueOnce(firstPageResponse)
        .mockResolvedValueOnce(secondPageResponse);

      createComponent({ groupsHandler: handler });

      return handler;
    };

    it('enables infinite scroll when there is a next page', async () => {
      createPaginatedComponent();
      await triggerDropdown();
      await waitForPromises();

      expect(findListbox().props('infiniteScroll')).toBe(true);
    });

    it('fetches the next page with the endCursor when bottom-reached fires', async () => {
      const handler = createPaginatedComponent();
      await triggerDropdown();
      await waitForPromises();

      findListbox().vm.$emit('bottom-reached');
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        search: '',
        first: NAMESPACES_PAGE_SIZE,
        after: 'cursor-1',
      });
    });

    it('appends the next page to the existing items', async () => {
      createPaginatedComponent();
      await triggerDropdown();
      await waitForPromises();

      findListbox().vm.$emit('bottom-reached');
      await waitForPromises();

      expect(findListbox().props('items')).toEqual([
        { value: mockGroup1.id, text: mockGroup1.name, fullPath: mockGroup1.fullPath },
        { value: mockGroup2.id, text: mockGroup2.name, fullPath: mockGroup2.fullPath },
      ]);
    });

    it('disables infinite scroll once the last page is reached', async () => {
      createPaginatedComponent();
      await triggerDropdown();
      await waitForPromises();

      findListbox().vm.$emit('bottom-reached');
      await waitForPromises();

      expect(findListbox().props('infiniteScroll')).toBe(false);
    });

    describe('when there is no next page', () => {
      it('does not fetch again after bottom-reached fires', async () => {
        const handler = createPaginatedComponent();
        await triggerDropdown();
        await waitForPromises();

        findListbox().vm.$emit('bottom-reached');
        await waitForPromises();

        const callCountAfterLastPage = handler.mock.calls.length;

        findListbox().vm.$emit('bottom-reached');
        await waitForPromises();

        expect(handler.mock.calls).toHaveLength(callCountAfterLastPage);
      });
    });
  });

  describe('error handling', () => {
    it('displays error message when groups query fails', async () => {
      const errorHandler = jest.fn().mockRejectedValue(new Error('Failed to fetch groups'));

      createComponent({ groupsHandler: errorHandler });

      await triggerDropdown();
      await waitForPromises();

      expect(findListbox().props('noResultsText')).toBe('Failed to load groups');
    });

    it('clears the error once a later search succeeds with no results', async () => {
      const emptyResponse = {
        data: { adminDuoAvailabilityNamespaces: { nodes: [], pageInfo: pageInfo() } },
      };
      const handler = jest
        .fn()
        .mockRejectedValueOnce(new Error('Failed to fetch groups'))
        .mockResolvedValueOnce(emptyResponse);

      createComponent({ groupsHandler: handler });
      await triggerDropdown();
      await waitForPromises();

      expect(findListbox().props('noResultsText')).toBe('Failed to load groups');

      findListbox().vm.$emit('search', 'no-matches');
      await waitForPromises();

      expect(findListbox().props('noResultsText')).toBe('No groups found');
    });
  });
});
