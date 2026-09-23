import { waitFor } from '@testing-library/vue';
import { waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { saveSessionStorageValue } from '~/lib/utils/local_storage';
import { DUO_CURRENT_WORKFLOW_STORAGE_KEY } from 'ee/ai/constants';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  getUserWorkflowsWithArchived,
  userWorkflowsVariants,
  workflowLatestCheckpointVariants,
  installDuoAIPanelHandlers,
} from './test_support/api_handlers';
import {
  buildChatConfiguration,
  findBackToThreadsButton,
  findChatComponent,
  findChatError,
  findChatInput,
  findEmptyState,
  findThreadBoxWithText,
  findThreadInactiveEmptyState,
  mountAISidebar,
  openHistoryTab,
  setupDuoChatTest,
  teardownDuoChatTest,
} from './test_support/test_setup';

describe('Duo Agentic Chat — archived thread integration', () => {
  const installThreadList = () => {
    installDuoAIPanelHandlers();

    // The thread list itself; the flags the UI acts on come from the per-workflow
    // checkpoint query, which the two recorded conversations below answer. Their
    // workflow ids are the list's own, so the pair lines up by construction.
    setQueryVariant(userWorkflowsVariants).withArchived();

    setQueryVariant(workflowLatestCheckpointVariants).archived();
  };

  const mountPanel = ({ workflowId } = {}) => {
    if (workflowId) {
      saveSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY, { workflowId });
    }

    return mountAISidebar({ chatConfiguration: buildChatConfiguration({ autoExpand: true }) });
  };

  beforeEach(setupDuoChatTest);

  afterEach(() => teardownDuoChatTest());

  it('disables the chat input when deep-linking to an archived workflow', async () => {
    installThreadList();

    mountPanel({ workflowId: getUserWorkflowsWithArchived.archivedThread().id });

    await waitForElement(findChatComponent);
    await waitForElement(findThreadInactiveEmptyState);

    expect(findChatInput().disabled).toBe(true);
  });

  it('disables the chat input after clicking an archived thread in the list', async () => {
    installThreadList();

    mountPanel();

    await waitForElement(findChatComponent);

    openHistoryTab();

    await waitForElement(() =>
      findThreadBoxWithText(getUserWorkflowsWithArchived.archivedThread().title),
    );
    findThreadBoxWithText(getUserWorkflowsWithArchived.archivedThread().title).click();

    await waitForElement(findThreadInactiveEmptyState);
    expect(findChatInput().disabled).toBe(true);
  });

  it('re-enables the chat input when switching from an archived thread to a non-archived one', async () => {
    installThreadList();

    mountPanel({ workflowId: getUserWorkflowsWithArchived.archivedThread().id });

    await waitForElement(findChatComponent);
    await waitForElement(findThreadInactiveEmptyState);

    findBackToThreadsButton().click();

    setQueryVariant(workflowLatestCheckpointVariants).active();

    await waitForElement(() =>
      findThreadBoxWithText(getUserWorkflowsWithArchived.activeThread().title),
    );
    findThreadBoxWithText(getUserWorkflowsWithArchived.activeThread().title).click();

    await waitFor(() => {
      expect(findThreadInactiveEmptyState()).toBe(null);
      expect(findChatInput().disabled).toBe(false);
    });

    // The active variant answers whatever id it is asked for, so the proof that the
    // second thread really was opened is the id the chat asked for.
    expect(lastRequestVariables('getWorkflowLatestCheckpoint')).toEqual({
      workflowId: getUserWorkflowsWithArchived.activeThread().id,
    });
  });

  it('opens a new chat when the deep-linked workflow no longer exists', async () => {
    installDuoAIPanelHandlers();

    // A stale workflow id in session storage, from a thread deleted since. The
    // chat asks for it, the API answers with no workflow, and the chat has to
    // land the user somewhere usable rather than on an error.
    setQueryVariant(workflowLatestCheckpointVariants).notFound();

    mountPanel({ workflowId: getUserWorkflowsWithArchived.activeThread().id });

    await waitForElement(findChatComponent);
    await waitForElement(findEmptyState);

    // The empty state only renders with no messages, so reaching it is also the
    // proof that the stale thread hydrated nothing. What it must not be is the
    // archived-thread state or an error banner.
    expect(findThreadInactiveEmptyState()).toBe(null);
    expect(findChatError()).toBe(null);
  });
});
