import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlButton, GlEmptyState, GlTab, GlTabs } from '@gitlab/ui';
import AgentSessionInbox from 'ee/ai/duo_agents_platform/panel/agent_session_inbox.vue';
import getUserAgentFlowInboxQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_user_agent_flow_inbox.query.graphql';
import AgentFlowFilteredSearch from 'ee/ai/duo_agents_platform/components/common/agent_flow_filtered_search.vue';
import AgentSessionInboxTab from 'ee/ai/duo_agents_platform/panel/agent_session_inbox_tab.vue';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import {
  DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES,
  INBOX_TAB_ALL,
} from 'ee/ai/duo_agents_platform/constants';
import { buildInboxResponse, mockInboxEdges, mockInboxPageInfo } from '../../mocks';

Vue.use(VueApollo);
jest.mock('~/alert');

describe('AgentSessionInbox', () => {
  let wrapper;
  const getInboxHandler = jest.fn();

  const createWrapper = () => {
    wrapper = shallowMountExtended(AgentSessionInbox, {
      apolloProvider: createMockApollo([[getUserAgentFlowInboxQuery, getInboxHandler]]),
      // Real GlTab so #title slots render; GlEmptyState stubbed with all slots to reach #actions.
      stubs: {
        GlTab,
        GlEmptyState: stubComponent(GlEmptyState, { template: RENDER_ALL_SLOTS_TEMPLATE }),
        // Rendered for real so the tab's slots resolve; its own spec covers its branches.
        AgentSessionInboxTab: stubComponent(AgentSessionInboxTab, {
          template: RENDER_ALL_SLOTS_TEMPLATE,
        }),
      },
    });
    return waitForPromises();
  };

  const findTabs = () => wrapper.findComponent(GlTabs);
  const findFilteredSearch = () => wrapper.findComponent(AgentFlowFilteredSearch);
  const findAllTab = () => wrapper.findComponentByTestId('all-tab');
  const findDecisionTab = () => wrapper.findComponentByTestId('needs-decision-tab');
  const findDecisionEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findSeeWhatsRunningButton = () => wrapper.findComponent(GlButton);
  const findDecisionTabBadge = () => wrapper.findByTestId('needs-decision-tab-badge');

  beforeEach(() => {
    getInboxHandler.mockResolvedValue(buildInboxResponse());
  });

  it('renders Needs a decision and All tabs', async () => {
    await createWrapper();

    expect(findTabs().exists()).toBe(true);
    expect(wrapper.text()).toContain('Needs a decision');
    expect(wrapper.text()).toContain('All');
  });

  it('opens on the All tab', async () => {
    await createWrapper();

    expect(findTabs().props('value')).toBe(INBOX_TAB_ALL);
  });

  it('sets pollInterval: 10000 on the inbox smart query', () => {
    expect(AgentSessionInbox.apollo.inbox.pollInterval).toBe(10000);
  });

  it('passes type: non_foundational_chat_agents, which keeps chat threads out of both tabs', async () => {
    await createWrapper();

    expect(getInboxHandler).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'non_foundational_chat_agents' }),
    );
  });

  describe('while the query is in flight', () => {
    beforeEach(() => {
      // Never resolves, so the loading state does not depend on test timing.
      getInboxHandler.mockReturnValue(new Promise(() => {}));
      createWrapper();
    });

    it('marks both tabs as loading', () => {
      expect(findDecisionTab().props('loading')).toBe(true);
      expect(findAllTab().props('loading')).toBe(true);
    });

    it('renders no decision badge', () => {
      expect(findDecisionTabBadge().exists()).toBe(false);
    });
  });

  describe('tab count badges', () => {
    const overflow = `${DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES.first}+`;

    describe('when neither connection has a further page', () => {
      beforeEach(() => createWrapper());

      it('shows the loaded edge count on the decision tab', () => {
        expect(findDecisionTabBadge().text()).toBe(String(mockInboxEdges.length));
      });
    });

    describe('when both connections report a further page', () => {
      beforeEach(() => {
        getInboxHandler.mockResolvedValue(
          buildInboxResponse({
            needsDecisionPageInfo: { ...mockInboxPageInfo, hasNextPage: true },
            allPageInfo: { ...mockInboxPageInfo, hasNextPage: true },
          }),
        );
        return createWrapper();
      });

      it('shows an overflow count on the decision badge', () => {
        expect(findDecisionTabBadge().text()).toBe(overflow);
      });
    });

    describe('when both connections are on their last page', () => {
      beforeEach(() => {
        getInboxHandler.mockResolvedValue(
          buildInboxResponse({
            needsDecisionPageInfo: { ...mockInboxPageInfo, hasPreviousPage: true },
            allPageInfo: { ...mockInboxPageInfo, hasPreviousPage: true },
          }),
        );
        return createWrapper();
      });

      it("keeps the overflow count, rather than shrinking to the last page's row count", () => {
        expect(findDecisionTabBadge().text()).toBe(overflow);
      });
    });
  });

  describe('when a filter is active and nothing needs a decision', () => {
    beforeEach(async () => {
      getInboxHandler.mockResolvedValue(buildInboxResponse({ needsDecisionEdges: [] }));
      await createWrapper();
      await findFilteredSearch().vm.$emit('search-variables-updated', {
        sort: 'UPDATED_DESC',
        filters: { search: 'nothing matches this' },
        updatedAfter: null,
      });
      await waitForPromises();
    });

    it('defers to the list so the copy is about the search, not an empty inbox', () => {
      expect(findDecisionTab().props('showEmptyState')).toBe(false);
      expect(findDecisionTab().props('workflows')).toEqual([]);
    });
  });

  describe('pagination on the decision tab', () => {
    beforeEach(() => {
      getInboxHandler.mockResolvedValue(
        buildInboxResponse({
          needsDecisionPageInfo: {
            ...mockInboxPageInfo,
            hasNextPage: true,
            endCursor: 'decision-cursor',
          },
        }),
      );
      return createWrapper();
    });

    it('passes the alias page info through to the list', () => {
      expect(findDecisionTab().props('pageInfo')).toMatchObject({
        hasNextPage: true,
        endCursor: 'decision-cursor',
      });
    });

    it('pages the decision alias on its own cursors, leaving the All tab alone', async () => {
      await findDecisionTab().vm.$emit('next-page');
      await waitForPromises();

      expect(getInboxHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({
          needsDecisionAfter: 'decision-cursor',
          needsDecisionFirst: 20,
          needsDecisionBefore: null,
          needsDecisionLast: null,
          allAfter: null,
          allFirst: 20,
        }),
      );
    });

    it('pages backwards on its own cursors', async () => {
      await findDecisionTab().vm.$emit('prev-page');
      await waitForPromises();

      expect(getInboxHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({
          needsDecisionBefore: mockInboxPageInfo.startCursor,
          needsDecisionLast: 20,
          needsDecisionAfter: null,
          needsDecisionFirst: null,
        }),
      );
    });
  });

  describe('when no session needs a decision', () => {
    beforeEach(() => {
      getInboxHandler.mockResolvedValue(buildInboxResponse({ needsDecisionEdges: [] }));
      return createWrapper();
    });

    it('renders the dedicated empty state rather than a no-results message', () => {
      expect(findDecisionTab().props('showEmptyState')).toBe(true);
      expect(findDecisionEmptyState().props('title')).toBe('Nothing needs you right now');
    });

    it('switches to the All tab from the empty state', async () => {
      await findSeeWhatsRunningButton().vm.$emit('click');

      expect(findTabs().props('value')).toBe(1);
    });
  });

  describe('when the search bar emits new search variables', () => {
    beforeEach(async () => {
      await createWrapper();
      await findFilteredSearch().vm.$emit('search-variables-updated', {
        sort: 'CREATED_ASC',
        filters: { statusGroup: 'PAUSED' },
        updatedAfter: null,
      });
      await waitForPromises();
    });

    it('requeries with the new sort and filters', () => {
      expect(getInboxHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ sort: 'CREATED_ASC', statusGroup: 'PAUSED' }),
      );
    });
  });

  describe('pagination on the All tab', () => {
    describe('when next-page is emitted', () => {
      beforeEach(async () => {
        getInboxHandler.mockResolvedValue(
          buildInboxResponse({
            needsDecisionEdges: [],
            allPageInfo: { ...mockInboxPageInfo, hasNextPage: true, endCursor: 'cursor123' },
          }),
        );
        await createWrapper();
        await findAllTab().vm.$emit('next-page');
        await waitForPromises();
      });

      it('requeries with the forward cursor', () => {
        expect(getInboxHandler).toHaveBeenLastCalledWith(
          expect.objectContaining({
            allAfter: 'cursor123',
            allFirst: 20,
            allBefore: null,
            allLast: null,
          }),
        );
      });
    });

    describe('when prev-page is emitted', () => {
      beforeEach(async () => {
        getInboxHandler.mockResolvedValue(
          buildInboxResponse({
            needsDecisionEdges: [],
            allPageInfo: { ...mockInboxPageInfo, hasPreviousPage: true, startCursor: 'cursor456' },
          }),
        );
        await createWrapper();
        await findAllTab().vm.$emit('prev-page');
        await waitForPromises();
      });

      it('requeries with the backward cursor', () => {
        expect(getInboxHandler).toHaveBeenLastCalledWith(
          expect.objectContaining({
            allBefore: 'cursor456',
            allLast: 20,
            allAfter: null,
            allFirst: null,
          }),
        );
      });
    });
  });

  describe('when the tab changes after paginating', () => {
    beforeEach(async () => {
      getInboxHandler.mockResolvedValue(
        buildInboxResponse({
          needsDecisionEdges: [],
          allPageInfo: { ...mockInboxPageInfo, hasNextPage: true, endCursor: 'cursor123' },
        }),
      );
      await createWrapper();
      await findAllTab().vm.$emit('next-page');
      await waitForPromises();
      await findTabs().vm.$emit('input', 0);
      // A search update forces a cache miss so the reset cursor is observable in the variables.
      await findFilteredSearch().vm.$emit('search-variables-updated', {
        sort: 'CREATED_ASC',
        filters: {},
        updatedAfter: null,
      });
      await waitForPromises();
    });

    it('resets pagination on both tabs to the first page', () => {
      expect(getInboxHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({
          sort: 'CREATED_ASC',
          allAfter: null,
          allBefore: null,
          allFirst: 20,
          allLast: null,
          needsDecisionAfter: null,
          needsDecisionBefore: null,
          needsDecisionFirst: 20,
          needsDecisionLast: null,
        }),
      );
    });
  });

  describe('when a filter is applied and then the next page is requested', () => {
    beforeEach(async () => {
      getInboxHandler.mockResolvedValue(
        buildInboxResponse({
          needsDecisionEdges: [],
          allPageInfo: { ...mockInboxPageInfo, hasNextPage: true, endCursor: 'cursor789' },
        }),
      );
      await createWrapper();
      await findFilteredSearch().vm.$emit('search-variables-updated', {
        sort: 'CREATED_ASC',
        filters: { statusGroup: 'PAUSED' },
        updatedAfter: null,
      });
      await waitForPromises();
      await findAllTab().vm.$emit('next-page');
      await waitForPromises();
    });

    it('keeps the sort, the filters and the chat exclusion on the paged request', () => {
      expect(getInboxHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({
          sort: 'CREATED_ASC',
          statusGroup: 'PAUSED',
          type: 'non_foundational_chat_agents',
          allAfter: 'cursor789',
          allFirst: 20,
        }),
      );
    });
  });

  describe('when the query returns sessions', () => {
    beforeEach(() => createWrapper());

    it('lists the needsDecision edges on the decision tab', () => {
      expect(findDecisionTab().props('workflows')).toEqual(mockInboxEdges.map((edge) => edge.node));
    });

    it('lists the all edges on the All tab', () => {
      expect(findAllTab().props('workflows')).toEqual(mockInboxEdges.map((edge) => edge.node));
    });
  });
});
