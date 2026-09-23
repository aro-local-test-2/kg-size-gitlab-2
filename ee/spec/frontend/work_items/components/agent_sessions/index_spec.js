import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import Visibility from 'visibilityjs';
import { createMockSubscription } from 'mock-apollo-client';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { createAlert } from '~/alert';
import WorkItemAgentSessions from 'ee/work_items/components/agent_sessions/index.vue';
import AgentSessionsList from 'ee/ai/shared/widgets/agent_sessions_list.vue';
import getDuoAgentSessionsOnWorkItemQuery from 'ee/ai/shared/widgets/graphql/get_duo_agent_sessions_on_work_item.query.graphql';
import duoAgentSessionsOnWorkItemUpdatedSubscription from 'ee/ai/shared/widgets/graphql/duo_agent_sessions_on_work_item.subscription.graphql';
import { buildSession, buildWorkItemSessionsQueryResponse } from 'ee_jest/ai/mocks';
import { WORKFLOW_TERMINAL_STATUSES } from 'ee/ai/duo_agents_platform/constants';
import {
  eventHub,
  REFETCH_SESSIONS,
  SCROLL_TO_SESSIONS,
  requestScrollToSessions,
} from 'ee/ai/events/panel';

Vue.use(VueApollo);

jest.mock('~/alert');
jest.mock('visibilityjs');

const WORK_ITEM_ID = 'gid://gitlab/WorkItem/1';
const POLL_INTERVAL = 30000;

const buildQueryResponse = (nodes = []) =>
  buildWorkItemSessionsQueryResponse({ workItemId: WORK_ITEM_ID, nodes });

describe('WorkItemAgentSessions', () => {
  let wrapper;
  let queryHandler;
  let subscription;

  const createComponent = ({ workItemId = WORK_ITEM_ID, handler = queryHandler } = {}) => {
    // A fresh mock per call: changing workItemId resubscribes with new variables, and
    // mock-apollo-client warns if one subscription object is reused across two queries.
    const subscriptionHandler = () => {
      subscription = createMockSubscription();
      return subscription;
    };

    wrapper = shallowMountExtended(WorkItemAgentSessions, {
      apolloProvider: createMockApollo([
        [getDuoAgentSessionsOnWorkItemQuery, handler],
        [duoAgentSessionsOnWorkItemUpdatedSubscription, subscriptionHandler],
      ]),
      propsData: { workItemId },
    });
  };

  // The server pushes the same shape the query returns, under workItemUpdated.
  const pushSessionsUpdate = (nodes) => {
    const { data } = buildQueryResponse(nodes);
    subscription.next({ data: { workItemUpdated: data.workItem } });
  };

  const findSessionsList = () => wrapper.findComponent(AgentSessionsList);

  const advanceIntervals = async (count) => {
    for (let i = 0; i < count; i += 1) {
      jest.advanceTimersByTime(POLL_INTERVAL);
      // eslint-disable-next-line no-await-in-loop
      await waitForPromises();
    }
  };

  const triggerVisibilityChange = () => {
    const [onVisibilityChange] = Visibility.change.mock.calls.at(-1);
    onVisibilityChange();
  };

  beforeEach(() => {
    Visibility.hidden.mockReturnValue(false);
    queryHandler = jest.fn().mockResolvedValue(buildQueryResponse());
  });

  describe('Apollo query', () => {
    it('queries with the workItemId', () => {
      createComponent();

      expect(queryHandler).toHaveBeenCalledWith(expect.objectContaining({ id: WORK_ITEM_ID }));
    });

    it('skips the query when workItemId is not set', () => {
      createComponent({ workItemId: null });

      expect(queryHandler).not.toHaveBeenCalled();
    });

    it('calls createAlert on query error', async () => {
      const error = new Error('GraphQL error');
      createComponent({ handler: jest.fn().mockRejectedValue(error) });
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ captureError: true, error }),
      );
    });
  });

  afterEach(() => {
    eventHub.$off(SCROLL_TO_SESSIONS);
    eventHub.$off(REFETCH_SESSIONS);
  });

  describe('AgentSessionsList', () => {
    it('is rendered while the query is in flight', () => {
      createComponent({ handler: jest.fn().mockReturnValue(new Promise(() => {})) });

      expect(findSessionsList().exists()).toBe(true);
      expect(findSessionsList().props('isLoading')).toBe(true);
    });

    it('passes all fetched sessions to the list', async () => {
      const sessions = [
        buildSession({ id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1', status: 'RUNNING' }),
        buildSession({ id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/2', status: 'FINISHED' }),
      ];
      createComponent({ handler: jest.fn().mockResolvedValue(buildQueryResponse(sessions)) });
      await waitForPromises();

      expect(findSessionsList().props('sessions')).toEqual(sessions);
    });

    it('passes isLoading=false once the query resolves', async () => {
      const sessions = [buildSession()];
      createComponent({ handler: jest.fn().mockResolvedValue(buildQueryResponse(sessions)) });
      await waitForPromises();

      expect(findSessionsList().props('isLoading')).toBe(false);
    });
  });

  describe('auto-scroll on SCROLL_TO_SESSIONS event', () => {
    let scrollIntoViewMock;

    beforeEach(() => {
      scrollIntoViewMock = jest.fn();
      Element.prototype.scrollIntoView = scrollIntoViewMock;
    });

    afterEach(() => {
      delete Element.prototype.scrollIntoView;
    });

    it('scrolls via sticky flag when component mounts after requestScrollToSessions', async () => {
      requestScrollToSessions();
      createComponent({
        handler: jest.fn().mockResolvedValue(buildQueryResponse([buildSession()])),
      });
      await waitForPromises();
      await nextTick();

      expect(scrollIntoViewMock).toHaveBeenCalledWith({
        behavior: 'smooth',
        block: 'start',
      });
    });

    it('scrolls via eventHub when component is already mounted', async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(buildQueryResponse([buildSession()])),
      });
      await waitForPromises();

      eventHub.$emit(SCROLL_TO_SESSIONS);
      await nextTick();

      expect(scrollIntoViewMock).toHaveBeenCalledWith({
        behavior: 'smooth',
        block: 'start',
      });
    });

    it('does not scroll when neither event nor sticky flag', async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(buildQueryResponse([buildSession()])),
      });
      await waitForPromises();
      await nextTick();

      expect(scrollIntoViewMock).not.toHaveBeenCalled();
    });

    it('does not scroll when sessions are empty', async () => {
      requestScrollToSessions();
      createComponent();
      await waitForPromises();
      await nextTick();

      expect(scrollIntoViewMock).not.toHaveBeenCalled();
    });
  });

  describe('when REFETCH_SESSIONS is emitted', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      eventHub.$emit(REFETCH_SESSIONS);
      await waitForPromises();
    });

    it('refetches the sessions query', () => {
      expect(queryHandler).toHaveBeenCalledTimes(2);
    });
  });

  describe('polling', () => {
    const SESSION_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/9';
    const activeSession = () => buildSession({ id: SESSION_ID, status: 'RUNNING' });

    describe('when there are no sessions', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('fetches once and never polls again', async () => {
        jest.advanceTimersByTime(POLL_INTERVAL * 100);
        await waitForPromises();

        expect(queryHandler).toHaveBeenCalledTimes(1);
      });
    });

    describe.each(WORKFLOW_TERMINAL_STATUSES)('when every session is %s', (status) => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([buildSession({ status })]));
        createComponent();
        await waitForPromises();
      });

      it('does not poll', async () => {
        jest.advanceTimersByTime(POLL_INTERVAL * 100);
        await waitForPromises();

        expect(queryHandler).toHaveBeenCalledTimes(1);
      });
    });

    describe('when a session is active', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([activeSession()]));
        createComponent();
        await waitForPromises();
      });

      it('does not fetch before the interval elapses', async () => {
        jest.advanceTimersByTime(POLL_INTERVAL - 1);
        await waitForPromises();

        expect(queryHandler).toHaveBeenCalledTimes(1);
      });

      it('fetches once per interval', async () => {
        await advanceIntervals(5);

        expect(queryHandler).toHaveBeenCalledTimes(6);
      });
    });

    describe('when the active session reaches a terminal status', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([activeSession()]));
        createComponent();
        await waitForPromises();

        queryHandler.mockResolvedValue(
          buildQueryResponse([buildSession({ id: SESSION_ID, status: 'FINISHED' })]),
        );
        await advanceIntervals(1);
      });

      it('stops polling', async () => {
        await advanceIntervals(5);

        expect(queryHandler).toHaveBeenCalledTimes(2);
      });
    });

    describe('when an active session arrives after a terminal list', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([buildSession()]));
        createComponent();
        await waitForPromises();

        queryHandler.mockResolvedValue(buildQueryResponse([buildSession(), activeSession()]));
        eventHub.$emit(REFETCH_SESSIONS);
        await waitForPromises();
      });

      it('resumes polling with a single poller', async () => {
        await advanceIntervals(5);

        expect(queryHandler).toHaveBeenCalledTimes(7);
      });
    });

    describe('when the work item changes while a session is active', () => {
      const OTHER_WORK_ITEM_ID = 'gid://gitlab/WorkItem/2';
      let callsAfterSwitch;

      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([activeSession()]));
        createComponent();
        await waitForPromises();

        queryHandler.mockResolvedValue(
          buildWorkItemSessionsQueryResponse({
            workItemId: OTHER_WORK_ITEM_ID,
            nodes: [activeSession()],
          }),
        );
        await wrapper.setProps({ workItemId: OTHER_WORK_ITEM_ID });
        await waitForPromises();

        callsAfterSwitch = queryHandler.mock.calls.length;
      });

      it('does not fetch before the interval elapses', async () => {
        jest.advanceTimersByTime(POLL_INTERVAL - 1);
        await waitForPromises();

        expect(queryHandler).toHaveBeenCalledTimes(callsAfterSwitch);
      });

      it('fetches once per interval', async () => {
        await advanceIntervals(3);

        expect(queryHandler).toHaveBeenCalledTimes(callsAfterSwitch + 3);
      });
    });

    describe('when the browser tab is hidden', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([activeSession()]));
        createComponent();
        await waitForPromises();

        Visibility.hidden.mockReturnValue(true);
        triggerVisibilityChange();
      });

      it('stops polling', async () => {
        await advanceIntervals(5);

        expect(queryHandler).toHaveBeenCalledTimes(1);
      });

      describe('and becomes visible again', () => {
        beforeEach(() => {
          Visibility.hidden.mockReturnValue(false);
          triggerVisibilityChange();
        });

        it('resumes polling', async () => {
          await advanceIntervals(5);

          expect(queryHandler).toHaveBeenCalledTimes(6);
        });
      });
    });

    describe('when a poll fails', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([activeSession()]));
        createComponent();
        await waitForPromises();

        queryHandler.mockRejectedValue(new Error('GraphQL error'));
        await advanceIntervals(1);
      });

      it('stops polling', async () => {
        await advanceIntervals(5);

        expect(queryHandler).toHaveBeenCalledTimes(2);
      });

      it('alerts once instead of once per interval', async () => {
        await advanceIntervals(5);

        expect(createAlert).toHaveBeenCalledTimes(1);
      });

      describe('and a refetch succeeds', () => {
        beforeEach(async () => {
          queryHandler.mockResolvedValue(buildQueryResponse([activeSession()]));
          eventHub.$emit(REFETCH_SESSIONS);
          await waitForPromises();
        });

        it('resumes polling', async () => {
          await advanceIntervals(3);

          expect(queryHandler).toHaveBeenCalledTimes(6);
        });
      });
    });
  });

  describe('when a workItemUpdated frame arrives', () => {
    const SESSION_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/9';

    beforeEach(async () => {
      queryHandler = jest
        .fn()
        .mockResolvedValue(
          buildQueryResponse([buildSession({ id: SESSION_ID, status: 'FAILED' })]),
        );
      createComponent();
      await waitForPromises();

      pushSessionsUpdate([buildSession({ id: SESSION_ID, status: 'RUNNING' })]);
      await waitForPromises();
    });

    it('renders the pushed status without refetching', () => {
      expect(findSessionsList().props('sessions')).toEqual([
        expect.objectContaining({ id: SESSION_ID, status: 'RUNNING' }),
      ]);
      expect(queryHandler).toHaveBeenCalledTimes(1);
    });

    it('starts polling, because the restarted session is active again', async () => {
      await advanceIntervals(3);

      expect(queryHandler).toHaveBeenCalledTimes(4);
    });
  });
});
