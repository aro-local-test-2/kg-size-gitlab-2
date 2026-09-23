import Vue, { nextTick } from 'vue';
// eslint-disable-next-line no-restricted-imports
import Vuex from 'vuex';
import VueApollo from 'vue-apollo';
import { DuoChatThreads } from '@gitlab/duo-ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { duoChatGlobalState } from 'ee/ai/state';
import {
  getSessionStorageValue,
  removeSessionStorageValue,
  saveSessionStorageValue,
} from '~/lib/utils/local_storage';
import { getPreferredLocales } from '~/locale';
import { DUO_CURRENT_WORKFLOW_STORAGE_KEY } from 'ee/ai/constants';
import {
  AGENTIC_CHAT_NEW_ROUTE,
  AGENTIC_CHAT_SHOW_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import getUserWorkflows from 'ee/ai/graphql/get_user_workflow.query.graphql';
import deleteAgenticWorkflowMutation from 'ee/ai/graphql/delete_agentic_workflow.mutation.graphql';
import DuoAgenticChatHistoryView from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_history_view.vue';
import DuoChatDeleteThreadModal from 'ee/ai/components/duo_chat_delete_thread_modal.vue';
import { workflowStreamFactory } from 'ee/ai/duo_agentic_chat/websocket/workflow_stream_factory';
import { clearThreadSnapshot } from 'ee/ai/duo_agentic_chat/utils/chat_thread_snapshot';
import { useLocalStorageSpy } from 'helpers/local_storage_helper';

Vue.use(Vuex);
Vue.use(VueApollo);

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

jest.mock('ee/ai/duo_agentic_chat/websocket/workflow_stream_factory', () => ({
  workflowStreamFactory: {
    getWorkflowStream: jest.fn().mockReturnValue({
      disconnect: jest.fn(),
    }),
  },
}));

jest.mock('ee/ai/duo_agentic_chat/utils/chat_thread_snapshot', () => ({
  clearThreadSnapshot: jest.fn(),
}));

jest.mock('~/lib/utils/local_storage', () => ({
  ...jest.requireActual('~/lib/utils/local_storage'),
  getSessionStorageValue: jest.fn(),
  removeSessionStorageValue: jest.fn(),
  saveSessionStorageValue: jest.fn(),
}));

const MOCK_USER_ID = 'gid://gitlab/User/1';
const MOCK_WORKFLOW_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/456';
const MOCK_OTHER_WORKFLOW_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/789';
const MOCK_THIRD_WORKFLOW_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/101';
const MOCK_END_CURSOR = 'MjA';

const mockWorkflowNode = (id, title, lastUpdatedAt) => ({
  id,
  title,
  lastUpdatedAt,
  aiCatalogItemVersionId: null,
  agentName: 'GitLab Duo',
  archived: false,
});

const mockWorkflowsResponse = (nodes, pageInfo = { endCursor: null, hasNextPage: false }) => ({
  data: {
    duoWorkflowWorkflows: {
      pageInfo,
      edges: nodes.map((node) => ({ node })),
    },
  },
});

const MOCK_FIRST_NODE = mockWorkflowNode(
  MOCK_WORKFLOW_ID,
  'Test workflow goal',
  '2024-01-01T00:00:00Z',
);
const MOCK_SECOND_NODE = mockWorkflowNode(
  MOCK_OTHER_WORKFLOW_ID,
  'Another workflow goal',
  '2024-01-02T00:00:00Z',
);
const MOCK_THIRD_NODE = mockWorkflowNode(
  MOCK_THIRD_WORKFLOW_ID,
  'Third workflow goal',
  '2024-01-03T00:00:00Z',
);

const MOCK_USER_WORKFLOWS_RESPONSE = mockWorkflowsResponse([MOCK_FIRST_NODE, MOCK_SECOND_NODE]);
const MOCK_FIRST_PAGE_RESPONSE = mockWorkflowsResponse([MOCK_FIRST_NODE, MOCK_SECOND_NODE], {
  endCursor: MOCK_END_CURSOR,
  hasNextPage: true,
});
// Offset cursors shift when a thread is created between page loads, so the
// second page repeats the last node of the first one.
const MOCK_SECOND_PAGE_RESPONSE = mockWorkflowsResponse([MOCK_SECOND_NODE, MOCK_THIRD_NODE], {
  endCursor: 'NDA',
  hasNextPage: false,
});

const MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE = {
  data: {
    deleteDuoWorkflowsWorkflow: { success: true, clientMutationId: null, errors: [] },
  },
};

describe('DuoAgenticChatHistoryView', () => {
  useLocalStorageSpy();

  let wrapper;
  let mockRouter;
  let setMessagesSpy;

  const userWorkflowsQueryHandlerMock = jest.fn();
  const deleteWorkflowMutationMock = jest.fn();

  const createComponent = () => {
    setMessagesSpy = jest.fn();

    const store = new Vuex.Store({
      state: { messages: [] },
      actions: { setMessages: setMessagesSpy },
    });

    const apolloProvider = createMockApollo([
      [getUserWorkflows, userWorkflowsQueryHandlerMock],
      [deleteAgenticWorkflowMutation, deleteWorkflowMutationMock],
    ]);

    mockRouter = { push: jest.fn().mockResolvedValue() };

    wrapper = shallowMountExtended(DuoAgenticChatHistoryView, {
      store,
      apolloProvider,
      propsData: { userId: MOCK_USER_ID },
      mocks: {
        $router: mockRouter,
      },
    });
  };

  const findError = () => wrapper.findByTestId('chat-error');
  const findThreads = () => wrapper.findComponent(DuoChatThreads);
  const findDeleteModal = () => wrapper.findComponent(DuoChatDeleteThreadModal);
  const listedThreadIds = () =>
    findThreads()
      .props('threads')
      .map((thread) => thread.id);

  beforeEach(() => {
    userWorkflowsQueryHandlerMock.mockResolvedValue(MOCK_USER_WORKFLOWS_RESPONSE);
    deleteWorkflowMutationMock.mockResolvedValue(MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE);
    duoChatGlobalState.focusChatInput = false;
  });

  describe('thread list', () => {
    it('does not render an error initially', () => {
      createComponent();

      expect(findError().exists()).toBe(false);
    });

    it('passes the loading state while the query is in flight', () => {
      createComponent();

      expect(findThreads().props('loading')).toBe(true);
    });

    it('passes the fetched workflows to DuoChatThreads', async () => {
      createComponent();
      await waitForPromises();

      expect(userWorkflowsQueryHandlerMock).toHaveBeenCalledWith({
        type: 'foundational_chat_agents',
        first: 20,
        environment: 'WEB',
      });
      expect(findThreads().props('loading')).toBe(false);
      expect(findThreads().props('threads')).toEqual([
        expect.objectContaining({ id: MOCK_WORKFLOW_ID }),
        expect.objectContaining({ id: MOCK_OTHER_WORKFLOW_ID }),
      ]);
    });

    it('passes the preferred locales to DuoChatThreads', () => {
      createComponent();

      expect(findThreads().props('preferredLocale')).toEqual(getPreferredLocales());
    });

    it('shows an error when the query fails', async () => {
      userWorkflowsQueryHandlerMock.mockRejectedValue(new Error('boom'));
      createComponent();
      await waitForPromises();

      expect(findError().exists()).toBe(true);
    });
  });

  describe('pagination', () => {
    describe('when there are no more pages', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('tells DuoChatThreads there is nothing more to load', () => {
        expect(findThreads().props('hasNextPage')).toBe(false);
      });
    });

    describe('when more pages exist', () => {
      beforeEach(async () => {
        userWorkflowsQueryHandlerMock.mockResolvedValueOnce(MOCK_FIRST_PAGE_RESPONSE);
        createComponent();
        await waitForPromises();
      });

      it('tells DuoChatThreads more pages exist', () => {
        expect(findThreads().props('hasNextPage')).toBe(true);
        expect(findThreads().props('loadingMore')).toBe(false);
        expect(listedThreadIds()).toEqual([MOCK_WORKFLOW_ID, MOCK_OTHER_WORKFLOW_ID]);
      });

      describe('when DuoChatThreads asks for more', () => {
        let resolveNextPage;

        beforeEach(() => {
          // Hold the response so the in-flight state is observable.
          userWorkflowsQueryHandlerMock.mockImplementationOnce(
            () =>
              new Promise((resolve) => {
                resolveNextPage = resolve;
              }),
          );
          findThreads().vm.$emit('load-more');
        });

        it('requests the next page from the end cursor', () => {
          expect(userWorkflowsQueryHandlerMock).toHaveBeenLastCalledWith({
            type: 'foundational_chat_agents',
            first: 20,
            after: MOCK_END_CURSOR,
            environment: 'WEB',
          });
        });

        it('keeps the loaded threads on screen and flags the page as loading', async () => {
          await nextTick();

          expect(findThreads().props('loading')).toBe(false);
          expect(findThreads().props('loadingMore')).toBe(true);
          expect(listedThreadIds()).toEqual([MOCK_WORKFLOW_ID, MOCK_OTHER_WORKFLOW_ID]);
        });

        it('ignores a second request while the page is in flight', async () => {
          findThreads().vm.$emit('load-more');
          await waitForPromises();

          expect(userWorkflowsQueryHandlerMock).toHaveBeenCalledTimes(2);
        });

        describe('when the next page arrives', () => {
          beforeEach(async () => {
            resolveNextPage(MOCK_SECOND_PAGE_RESPONSE);
            await waitForPromises();
          });

          it('appends the new threads and drops the node repeated across pages', () => {
            expect(listedThreadIds()).toEqual([
              MOCK_WORKFLOW_ID,
              MOCK_OTHER_WORKFLOW_ID,
              MOCK_THIRD_WORKFLOW_ID,
            ]);
          });

          it('does not refetch the first page', () => {
            expect(userWorkflowsQueryHandlerMock).toHaveBeenCalledTimes(2);
          });

          it('tells DuoChatThreads the last page is loaded', () => {
            expect(findThreads().props('hasNextPage')).toBe(false);
            expect(findThreads().props('loadingMore')).toBe(false);
          });
        });
      });

      describe('when loading the next page fails', () => {
        beforeEach(async () => {
          userWorkflowsQueryHandlerMock.mockRejectedValueOnce(new Error('boom'));
          findThreads().vm.$emit('load-more');
          await waitForPromises();
        });

        it('shows the error and keeps the loaded threads', () => {
          expect(findError().exists()).toBe(true);
          expect(listedThreadIds()).toEqual([MOCK_WORKFLOW_ID, MOCK_OTHER_WORKFLOW_ID]);
        });

        describe('when a later page load succeeds', () => {
          beforeEach(async () => {
            userWorkflowsQueryHandlerMock.mockResolvedValueOnce(MOCK_SECOND_PAGE_RESPONSE);
            findThreads().vm.$emit('load-more');
            await waitForPromises();
          });

          it('clears the error and appends the new threads', () => {
            expect(findError().exists()).toBe(false);
            expect(listedThreadIds()).toEqual([
              MOCK_WORKFLOW_ID,
              MOCK_OTHER_WORKFLOW_ID,
              MOCK_THIRD_WORKFLOW_ID,
            ]);
          });
        });
      });

      describe('when a thread is deleted before the next page loads', () => {
        beforeEach(async () => {
          findThreads().vm.$emit('delete-thread', MOCK_WORKFLOW_ID);
          findDeleteModal().vm.$emit('confirm');
          await waitForPromises();

          userWorkflowsQueryHandlerMock.mockResolvedValueOnce(MOCK_SECOND_PAGE_RESPONSE);
          findThreads().vm.$emit('load-more');
          await waitForPromises();
        });

        it('does not bring the deleted thread back', () => {
          expect(listedThreadIds()).toEqual([MOCK_OTHER_WORKFLOW_ID, MOCK_THIRD_WORKFLOW_ID]);
        });
      });
    });
  });

  describe('when a new chat is requested', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      findThreads().vm.$emit('new-chat');
    });

    it('disconnects any running stream', () => {
      expect(workflowStreamFactory.getWorkflowStream().disconnect).toHaveBeenCalled();
    });

    it('clears the shared message store', () => {
      expect(setMessagesSpy).toHaveBeenCalledWith(expect.anything(), []);
    });

    it('navigates to the new chat route', () => {
      expect(mockRouter.push).toHaveBeenCalledWith({ name: AGENTIC_CHAT_NEW_ROUTE });
    });

    it('signals the chat input to focus once the chat view mounts', async () => {
      await waitForPromises();

      expect(duoChatGlobalState.focusChatInput).toBe(true);
    });
  });

  describe('when navigating to a new chat fails', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      mockRouter.push.mockRejectedValueOnce(new Error('nav failed'));
      findThreads().vm.$emit('new-chat');
      await waitForPromises();
    });

    it('does not signal the chat input to focus', () => {
      expect(duoChatGlobalState.focusChatInput).toBe(false);
    });
  });

  describe('when a thread is selected', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      findThreads().vm.$emit('select-thread', { id: MOCK_WORKFLOW_ID });
    });

    it('disconnects any running stream', () => {
      expect(workflowStreamFactory.getWorkflowStream().disconnect).toHaveBeenCalled();
    });

    it('clears the shared message store', () => {
      expect(setMessagesSpy).toHaveBeenCalledWith(expect.anything(), []);
    });

    it('stores the selected workflow for the chat state manager to hydrate', () => {
      expect(saveSessionStorageValue).toHaveBeenCalledWith(DUO_CURRENT_WORKFLOW_STORAGE_KEY, {
        workflowId: MOCK_WORKFLOW_ID,
      });
    });

    it('navigates to the chat route', () => {
      expect(mockRouter.push).toHaveBeenCalledWith({ name: AGENTIC_CHAT_SHOW_ROUTE });
    });
  });

  describe('thread deletion', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('does not show the delete modal initially', () => {
      expect(findDeleteModal().props('visible')).toBe(false);
    });

    it('opens the confirmation modal instead of deleting immediately', async () => {
      findThreads().vm.$emit('delete-thread', MOCK_WORKFLOW_ID);
      await waitForPromises();

      expect(findDeleteModal().props('visible')).toBe(true);
      expect(deleteWorkflowMutationMock).not.toHaveBeenCalled();
    });

    describe('when the deletion is confirmed', () => {
      beforeEach(async () => {
        findThreads().vm.$emit('delete-thread', MOCK_WORKFLOW_ID);
        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();
        // Apollo delivers cache writes to the list query on a zero-delay timer.
        jest.runOnlyPendingTimers();
        await nextTick();
      });

      it('deletes the workflow', () => {
        expect(deleteWorkflowMutationMock).toHaveBeenCalledWith({
          input: { workflowId: MOCK_WORKFLOW_ID },
        });
      });

      it('removes the deleted thread from the list without refetching', () => {
        expect(userWorkflowsQueryHandlerMock).toHaveBeenCalledTimes(1);
        expect(findThreads().props('threads')).toEqual([
          expect.objectContaining({ id: MOCK_OTHER_WORKFLOW_ID }),
        ]);
      });

      it('clears the thread snapshot and closes the modal', () => {
        expect(clearThreadSnapshot).toHaveBeenCalledWith(MOCK_WORKFLOW_ID);
        expect(findDeleteModal().props('visible')).toBe(false);
      });

      // An unsent draft outlives the conversation it was written for otherwise.
      it("drops the deleted thread's draft", () => {
        expect(localStorage.removeItem).toHaveBeenCalledWith('autosave/duo_chat_draft_1_456');
      });
    });

    describe('stored active workflow', () => {
      it('clears the stored workflow when the deleted thread is the active one', async () => {
        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        findThreads().vm.$emit('delete-thread', MOCK_WORKFLOW_ID);
        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();

        expect(removeSessionStorageValue).toHaveBeenCalledWith(DUO_CURRENT_WORKFLOW_STORAGE_KEY);
      });

      it('keeps the stored workflow when a different thread is deleted', async () => {
        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_OTHER_WORKFLOW_ID },
        });
        findThreads().vm.$emit('delete-thread', MOCK_WORKFLOW_ID);
        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();

        expect(removeSessionStorageValue).not.toHaveBeenCalled();
      });

      it('keeps the stored workflow when there is nothing in session storage', async () => {
        getSessionStorageValue.mockReturnValue({ exists: false });
        findThreads().vm.$emit('delete-thread', MOCK_WORKFLOW_ID);
        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();

        expect(removeSessionStorageValue).not.toHaveBeenCalled();
      });
    });

    describe('when the deletion fails', () => {
      beforeEach(async () => {
        deleteWorkflowMutationMock.mockRejectedValue(new Error('deletion failed'));
        findThreads().vm.$emit('delete-thread', MOCK_WORKFLOW_ID);
        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('keeps the thread in the list and shows the error', () => {
        expect(findThreads().props('threads')).toHaveLength(2);
        expect(findError().exists()).toBe(true);
      });

      it('closes the modal', () => {
        expect(findDeleteModal().props('visible')).toBe(false);
      });

      it('clears the error on a subsequent successful deletion', async () => {
        deleteWorkflowMutationMock.mockResolvedValue(MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE);
        findThreads().vm.$emit('delete-thread', MOCK_OTHER_WORKFLOW_ID);
        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();

        expect(findError().exists()).toBe(false);
      });
    });
  });
});
