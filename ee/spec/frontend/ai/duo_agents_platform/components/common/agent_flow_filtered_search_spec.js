import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentFlowFilteredSearch from 'ee/ai/duo_agents_platform/components/common/agent_flow_filtered_search.vue';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import getFlowTypesQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_flow_types.query.graphql';

Vue.use(VueApollo);

const mockFlowTypesNodes = [
  { id: '1', name: 'Code review', foundationalFlowReference: 'code_review/v1' },
  { id: '2', name: 'Convert to gitlab ci', foundationalFlowReference: 'convert_to_gitlab_ci' },
  { id: '3', name: 'Developer', foundationalFlowReference: 'developer/v1' },
  { id: '4', name: 'Fix pipeline', foundationalFlowReference: 'fix_pipeline/v1' },
  { id: '5', name: 'Issue to merge request', foundationalFlowReference: 'issue_to_merge_request' },
  { id: '6', name: 'Software development', foundationalFlowReference: 'software_development' },
];

const mockFlowTypesResponse = {
  data: {
    aiCatalogItems: {
      nodes: mockFlowTypesNodes,
    },
  },
};

const mockFlowTypesQueryHandler = jest.fn().mockResolvedValue(mockFlowTypesResponse);

const mockEmptyFlowTypesHandler = jest.fn().mockResolvedValue({
  data: { aiCatalogItems: { nodes: [] } },
});

const mockFlowTypesErrorHandler = jest
  .fn()
  .mockRejectedValue(new Error('Failed to fetch flow types'));

describe('AgentFlowFilteredSearch', () => {
  let wrapper;

  const defaultProps = {
    hasInitialWorkflows: true,
    initialSort: 'UPDATED_DESC',
  };

  const findFilteredSearchBar = () => wrapper.findComponent(FilteredSearchBar);
  const findTimeRangeDropdown = () => wrapper.findComponentByTestId('time-range-filter');

  const expectSearchVariablesUpdatedEvent = (expectedPayload) => {
    const emittedEvents = wrapper.emitted('search-variables-updated');
    expect(emittedEvents).toHaveLength(1);
    expect(emittedEvents[0]).toEqual([expectedPayload]);
  };

  const createWrapper = ({
    props = {},
    apolloHandlers = [[getFlowTypesQuery, mockFlowTypesQueryHandler]],
  } = {}) => {
    const apolloProvider = createMockApollo([...apolloHandlers]);

    wrapper = shallowMountExtended(AgentFlowFilteredSearch, {
      apolloProvider,
      propsData: { ...defaultProps, ...props },
    });

    return waitForPromises();
  };

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('when component is mounted', () => {
    beforeEach(async () => {
      await createWrapper();
    });

    it('renders the filtered search bar with correct props', () => {
      expect(findFilteredSearchBar().exists()).toBe(true);
      expect(findFilteredSearchBar().props()).toMatchObject({
        namespace: 'duo-agents-platform',
        searchInputPlaceholder: 'Search for a session',
        syncFilterAndSort: true,
        termsAsTokens: true,
        initialSortBy: 'UPDATED_DESC',
        initialFilterValue: [],
      });
    });

    it('selects the default time range', () => {
      expect(findTimeRangeDropdown().props('selected')).toBe('all');
    });

    it('renders the filtered search bar with sort options', () => {
      expect(findFilteredSearchBar().props('sortOptions')).toEqual([
        {
          id: 1,
          title: 'Created date',
          sortDirection: {
            descending: 'CREATED_DESC',
            ascending: 'CREATED_ASC',
          },
        },
        {
          id: 2,
          title: 'Updated date',
          sortDirection: {
            descending: 'UPDATED_DESC',
            ascending: 'UPDATED_ASC',
          },
        },
      ]);
    });
  });

  describe('when flow types are available', () => {
    beforeEach(async () => {
      await createWrapper();
    });

    it('renders the filtered search bar with filter tokens', () => {
      const tokens = findFilteredSearchBar().props('tokens');

      expect(tokens).toHaveLength(2);

      expect(tokens[0]).toMatchObject({
        type: 'flow-name',
        title: 'Flow',
        icon: 'flow-ai',
        unique: true,
      });
      expect(tokens[0].options).toEqual(
        mockFlowTypesNodes.map((node) => ({
          value: node.foundationalFlowReference,
          title: node.name,
        })),
      );

      expect(tokens[1]).toMatchObject({
        type: 'flow-status-group',
        title: 'Status',
        icon: 'status',
        unique: true,
      });
      expect(tokens[1].options).toEqual([
        { value: 'ACTIVE', title: 'Active' },
        { value: 'PAUSED', title: 'Paused' },
        { value: 'AWAITING_INPUT', title: 'Awaiting input' },
        { value: 'COMPLETED', title: 'Completed' },
        { value: 'FAILED', title: 'Failed' },
        { value: 'CANCELED', title: 'Canceled' },
      ]);
    });
  });

  describe.each`
    description                  | apolloHandlers
    ${'no flow types available'} | ${[[getFlowTypesQuery, mockEmptyFlowTypesHandler]]}
    ${'flow types query fails'}  | ${[[getFlowTypesQuery, mockFlowTypesErrorHandler]]}
  `('when there are $description', ({ apolloHandlers }) => {
    beforeEach(async () => {
      await createWrapper({ apolloHandlers });
    });

    it('does not render the flow token', () => {
      const tokens = findFilteredSearchBar().props('tokens');

      expect(tokens).toHaveLength(1);
      expect(tokens[0]).toMatchObject({
        type: 'flow-status-group',
        title: 'Status',
        icon: 'status',
        unique: true,
      });
    });
  });

  describe('when hasInitialWorkflows is false', () => {
    beforeEach(async () => {
      await createWrapper({ props: { hasInitialWorkflows: false } });
    });

    it('does not render the filtered search bar', () => {
      expect(findFilteredSearchBar().exists()).toBe(false);
    });
  });

  describe('when on-sort is triggered', () => {
    beforeEach(async () => {
      await createWrapper();
      findFilteredSearchBar().vm.$emit('on-sort', 'UPDATED_DESC');
    });

    it('emits search-variables-updated event', () => {
      expectSearchVariablesUpdatedEvent({
        sort: 'UPDATED_DESC',
        filters: {},
        updatedAfter: null,
      });
    });
  });

  describe('when filtering', () => {
    beforeEach(async () => {
      await createWrapper();
    });

    describe('with valid flow-name token', () => {
      beforeEach(() => {
        findFilteredSearchBar().vm.$emit('on-filter', [
          { type: 'flow-name', value: { data: 'convert_to_gitlab_ci' } },
        ]);
      });

      it('emits search-variables-updated event with processed filter parameters', () => {
        expectSearchVariablesUpdatedEvent({
          sort: 'UPDATED_DESC',
          filters: { type: 'convert_to_gitlab_ci' },
          updatedAfter: null,
        });
      });
    });

    describe('with valid flow-status-group token', () => {
      beforeEach(() => {
        findFilteredSearchBar().vm.$emit('on-filter', [
          { type: 'flow-status-group', value: { data: 'PAUSED' } },
        ]);
      });

      it('emits search-variables-updated event with processed filter parameters', () => {
        expectSearchVariablesUpdatedEvent({
          sort: 'UPDATED_DESC',
          filters: { statusGroup: 'PAUSED' },
          updatedAfter: null,
        });
      });
    });

    describe('with free text search term', () => {
      beforeEach(() => {
        findFilteredSearchBar().vm.$emit('on-filter', [
          { type: 'filtered-search-term', value: { data: 'software dev' } },
        ]);
      });

      it('emits search-variables-updated event with processed filter parameters', () => {
        expectSearchVariablesUpdatedEvent({
          sort: 'UPDATED_DESC',
          filters: { search: 'software dev' },
          updatedAfter: null,
        });
      });
    });

    describe('when filters are cleared', () => {
      beforeEach(() => {
        findFilteredSearchBar().vm.$emit('on-filter', []);
      });

      it('emits search-variables-updated event with empty filters', () => {
        expectSearchVariablesUpdatedEvent({
          sort: 'UPDATED_DESC',
          filters: {},
          updatedAfter: null,
        });
      });
    });
  });

  describe('when filters are restored from a previous visit', () => {
    const savedFilters = {
      type: 'convert_to_gitlab_ci',
      statusGroup: 'PAUSED',
      search: 'software dev',
    };

    beforeEach(async () => {
      await createWrapper({
        props: {
          initialFilters: { ...savedFilters, updatedAfter: '2020-01-01T00:00:00.000Z' },
        },
      });
    });

    it('seeds the search bar with a token for each saved filter', () => {
      expect(findFilteredSearchBar().props('initialFilterValue')).toEqual([
        { type: 'flow-name', value: { data: 'convert_to_gitlab_ci', operator: '=' } },
        { type: 'flow-status-group', value: { data: 'PAUSED', operator: '=' } },
        { type: 'filtered-search-term', value: { data: 'software dev' } },
      ]);
    });

    it('selects the time range implied by the saved filters', () => {
      expect(findTimeRangeDropdown().props('selected')).toBe('available');
    });

    describe('and then only the sort is changed', () => {
      beforeEach(() => {
        findFilteredSearchBar().vm.$emit('on-sort', 'CREATED_ASC');
      });

      it('keeps the restored filters and recomputes updatedAfter', () => {
        expectSearchVariablesUpdatedEvent({
          sort: 'CREATED_ASC',
          filters: savedFilters,
          updatedAfter: '2020-06-06T00:00:00.000Z',
        });
      });
    });
  });

  describe('time range filter', () => {
    beforeEach(async () => {
      await createWrapper();
    });

    describe('when time range is set to "all"', () => {
      beforeEach(() => {
        findTimeRangeDropdown().vm.$emit('select', 'all');
      });

      it('emits search-variables-updated event with updatedAfter as null', () => {
        expectSearchVariablesUpdatedEvent({
          sort: 'UPDATED_DESC',
          filters: {},
          updatedAfter: null,
        });
      });
    });

    describe('when time range is set to "available"', () => {
      beforeEach(() => {
        findTimeRangeDropdown().vm.$emit('select', 'available');
      });

      it('emits search-variables-updated event with updatedAfter set to 30 days ago', () => {
        expectSearchVariablesUpdatedEvent({
          sort: 'UPDATED_DESC',
          filters: {},
          updatedAfter: '2020-06-06T00:00:00.000Z',
        });
      });
    });
  });
});
