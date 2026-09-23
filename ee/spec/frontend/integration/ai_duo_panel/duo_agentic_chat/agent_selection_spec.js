import { waitFor } from '@testing-library/vue';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import {
  getFoundationalChatAgents,
  getUserWorkflows,
  installDuoAIPanelHandlers,
} from '../test_support/api_handlers';
import {
  buildChatConfiguration,
  findAgentItem,
  findAgentToggle,
  findChatSubheader,
  findSubmitButton,
  findThreadBoxWithText,
  mountAISidebar,
  openAgentDropdown,
  openChatTab,
  openHistoryTab,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  getSockets,
  lastWebsocketParams,
  pushCheckpoint,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

// Replaces the "allows user to select a custom agent" example from
// ee/spec/support/shared_examples/ai/agentic_chat_shared_example.rb.
//
// That example asserted `Ai::DuoWorkflows::Workflow.last.workflow_definition`
// through the browser. The server side of that contract is already covered by
// ee/spec/requests/api/graphql/mutations/ai/duo_workflows/create_spec.rb, so what
// is left to prove is the client side: that picking an agent puts its
// `referenceWithVersion` on both the create mutation and the websocket URL.

const DATA_ANALYST = getFoundationalChatAgents
  .agents()
  .find((agent) => agent.name === 'Data Analyst');

// Without this the selection tests fail deep inside a `waitFor` on a missing `.id`,
// which says nothing about the fixture being the cause. The agent list shrinks when
// the fixture user loses its default namespace, which has happened.
if (!DATA_ANALYST) {
  throw new Error(
    'The foundational agents fixture needs a "Data Analyst" agent. ' +
      'Regenerate with: bundle exec rspec ee/spec/frontend/fixtures/ai_duo_panel_integration.rb',
  );
}
const listedThread = () => getUserWorkflows.threads()[0];

describe('Duo Agentic Chat | selecting a foundational agent', () => {
  const mountAndSelectDataAnalyst = async () => {
    mountAISidebar({ chatConfiguration: buildChatConfiguration() });

    await waitFor(() => {
      expect(findAgentToggle()).not.toBe(null);
    });

    openAgentDropdown();

    const item = await waitFor(() => {
      const option = findAgentItem(DATA_ANALYST.id);
      expect(option).not.toBe(null);
      return option;
    });

    item.click();

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });
  };

  const sendAndWaitForConnect = async (prompt) => {
    const socketsBefore = getSockets().length;

    sendPrompt(prompt);

    // Each startWorkflow opens a fresh socket; the worker flushes the startRequest
    // from its onopen handler, so wait for the handshake before asserting on it.
    await waitFor(() => {
      expect(getSockets()).toHaveLength(socketsBefore + 1);
    });
    await waitForSocket();
  };

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  it('shows the selected agent in the chat subheader and closes the dropdown', async () => {
    await mountAndSelectDataAnalyst();

    await waitFor(() => {
      expect(getText(findChatSubheader())).toContain(DATA_ANALYST.name);
    });

    // Regression guard: the listbox used to stay open after picking an agent
    // while the panel was already mounted. `new_chat_button.vue` has to close it
    // explicitly because the listbox is `multiple`. The Capybara original
    // asserted the header text was gone; in jsdom the collapsed menu markup is
    // still present, so assert the expanded state instead.
    await waitFor(() => {
      expect(findAgentToggle().querySelector('button').getAttribute('aria-expanded')).toBe('false');
    });
  });

  it('creates the workflow with the agent definition and opens the socket for it', async () => {
    await mountAndSelectDataAnalyst();

    await sendAndWaitForConnect('analyse my issues');

    expect(lastRequestVariables('createAiDuoWorkflow').workflowDefinition).toBe(
      DATA_ANALYST.referenceWithVersion,
    );
    expect(lastWebsocketParams().get('workflow_definition')).toBe(
      DATA_ANALYST.referenceWithVersion,
    );
  });

  it('keeps the agent selected after a round-trip through history', async () => {
    await mountAndSelectDataAnalyst();
    await sendAndWaitForConnect('analyse my issues');

    await pushCheckpoint(
      [
        userLogEntry({ id: 'user-1', content: 'analyse my issues' }),
        agentLogEntry({ id: 'agent-1', content: 'Based on my analysis...' }),
      ],
      { goal: 'analyse my issues' },
    );

    await waitFor(() => {
      expect(getText(document.body)).toContain('Based on my analysis...');
    });

    openHistoryTab();

    // Confirm history actually rendered, otherwise coming back proves nothing. The
    // thread is one the server returned: whether the workflow this test just created
    // shows up here is the backend's business, not the panel's.
    await waitFor(() => {
      expect(findThreadBoxWithText(listedThread().title)).not.toBe(null);
    });

    // Coming back remounts the chat, but `currentAgent` lives in the panel-level
    // store, so the subheader title still resolves to the pick instead of
    // falling back to the default "GitLab Duo".
    openChatTab();

    await waitFor(() => {
      expect(getText(findChatSubheader())).toContain(DATA_ANALYST.name);
    });
  });
});
