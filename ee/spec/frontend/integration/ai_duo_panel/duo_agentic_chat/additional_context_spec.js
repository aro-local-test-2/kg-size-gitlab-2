import { waitFor } from '@testing-library/vue';
import setWindowLocation from 'helpers/set_window_location_helper';
import { saveSessionStorageValue } from '~/lib/utils/local_storage';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import {
  AI_CONTEXT_ID_AGENT_MD,
  AI_CONTEXT_ID_CHAT_RULE,
  AI_CONTEXT_ID_PAGE_CONTEXT,
  DUO_CURRENT_WORKFLOW_STORAGE_KEY,
  DUO_WORKFLOW_ADDITIONAL_CONTEXT_REPOSITORY,
  DUO_WORKFLOW_ADDITIONAL_CONTEXT_USER_RULE,
} from 'ee/ai/constants';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import {
  expectGraphQLCalls,
  lastRequestVariables,
  snapshotRequests,
} from 'ee_jest/integration/core/operation_helpers';
import {
  getRuleContent,
  getWorkflowLatestCheckpointWithContext,
  workflowLatestCheckpointVariants,
  installDuoAIPanelHandlers,
} from '../test_support/api_handlers';
import {
  PROJECT_PATH,
  findChatMessages,
  findContextSelectionTitles,
  findContextTokenLabels,
  findSubmitButton,
  mountDuoAgenticChatStateManager,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  getSockets,
  lastAdditionalContext,
  pushCheckpoint,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

const EXPECTED_CONTEXT_IDS = [
  AI_CONTEXT_ID_PAGE_CONTEXT,
  AI_CONTEXT_ID_AGENT_MD,
  AI_CONTEXT_ID_CHAT_RULE,
];

const ruleContent = () => getRuleContent.project();

const ruleBlob = (name) => ruleContent().repository.blobs.nodes.find((blob) => blob.name === name);

const agentsMdBlob = () => ruleBlob('AGENTS.md');

const chatRulesBlob = () => ruleBlob('chat-rules.md');

const rulesProjectId = () => ruleContent().id;

// What RuleContextProvider asks the resolver for.
const RULE_PATHS = ['AGENTS.md', '.gitlab/duo/chat-rules.md'];

const hydratedMessages = () => getWorkflowLatestCheckpointWithContext.messages();

const SEEDED_WORKFLOW_ID = getIdFromGraphQLId(getWorkflowLatestCheckpointWithContext.workflow().id);
const EARLIER_ANSWER = hydratedMessages().find(({ role }) => role === 'assistant').content;

/**
 * The page the recorded conversation carries context for. The de-duplication
 * assertions only hold when the live page matches what the prior turn recorded, so
 * the test moves to the fixture's page rather than the fixture guessing the test's.
 */
const HYDRATED_PAGE_PATH = hydratedMessages()
  .find(({ role }) => role === 'user')
  .additionalContext.find(({ id }) => id === AI_CONTEXT_ID_PAGE_CONTEXT).metadata.pagePath;

const OTHER_PAGE_PATH = '/group/project-with-rules/-/merge_requests/1';

describe('Duo Agentic Chat | injecting page and repository rule context', () => {
  /**
   * The system-context items on the wire, keyed by id and with `metadata` parsed
   * back out of its JSON string. Items from the external context store carry no
   * `id` and belong to `external_context_store_spec.js`, so they are dropped here.
   */
  const sentContext = () =>
    Object.fromEntries(
      lastAdditionalContext()
        .filter(({ id }) => id)
        .map(({ id, category, content, metadata }) => [
          id,
          { category, content, metadata: JSON.parse(metadata) },
        ]),
    );

  const mountAndWaitForComposer = async () => {
    mountDuoAgenticChatStateManager({
      propsData: { projectId: rulesProjectId(), projectPath: PROJECT_PATH },
    });

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });
  };

  /**
   * Puts a finished turn that already carries context into the conversation the
   * way a reload would: the workflow service serves it over GraphQL and the chat
   * hydrates from the workflow id in session storage.
   */
  const mountWithHydratedConversation = async () => {
    // Stand on the page the recorded turn carries context for, so "same page" is
    // true and the providers have something to de-duplicate against.
    setWindowLocation(HYDRATED_PAGE_PATH);

    setQueryVariant(workflowLatestCheckpointVariants).withContext();
    saveSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY, {
      workflowId: SEEDED_WORKFLOW_ID,
    });

    await mountAndWaitForComposer();

    // The providers read the conversation, so nothing may be sent until it is in.
    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(EARLIER_ANSWER);
    });
  };

  /**
   * Sends a prompt and waits for the socket the worker opens for it. The context
   * providers have run by then, and their output is on the wire once the worker
   * flushes the startRequest from its onopen handler.
   */
  const sendPromptAndWaitForConnect = async (prompt) => {
    const socketsBefore = getSockets().length;

    sendPrompt(prompt);

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

  it('sends page context and both repository rule files with the first message', async () => {
    await mountAndWaitForComposer();
    const baselineRequests = snapshotRequests();

    await sendPromptAndWaitForConnect('first question');

    expectGraphQLCalls(baselineRequests, { expect: ['getRuleContent'], forbid: [] });
    expect(lastRequestVariables('getRuleContent')).toEqual({
      projectPath: PROJECT_PATH,
      paths: RULE_PATHS,
    });

    const context = sentContext();

    expect(Object.keys(context).sort()).toEqual([...EXPECTED_CONTEXT_IDS].sort());

    // PageContextProvider reads the live document, so this is the real page.
    expect(context[AI_CONTEXT_ID_PAGE_CONTEXT].category).toBe(
      DUO_WORKFLOW_ADDITIONAL_CONTEXT_REPOSITORY,
    );
    expect(context[AI_CONTEXT_ID_PAGE_CONTEXT].content).toContain(window.location.href);
    expect(context[AI_CONTEXT_ID_PAGE_CONTEXT].metadata).toMatchObject({
      pagePath: window.location.pathname,
      projectPath: PROJECT_PATH,
    });

    // The rule bodies came back from `getRuleContent` through real Apollo, and the
    // oids are what a later turn is de-duplicated against.
    expect(context[AI_CONTEXT_ID_AGENT_MD].category).toBe(
      DUO_WORKFLOW_ADDITIONAL_CONTEXT_USER_RULE,
    );
    expect(context[AI_CONTEXT_ID_AGENT_MD].content).toContain(agentsMdBlob().rawBlob);
    expect(context[AI_CONTEXT_ID_AGENT_MD].metadata.oid).toBe(agentsMdBlob().oid);

    expect(context[AI_CONTEXT_ID_CHAT_RULE].content).toContain(chatRulesBlob().rawBlob);
    expect(context[AI_CONTEXT_ID_CHAT_RULE].metadata.oid).toBe(chatRulesBlob().oid);
  });

  it('sends no context when the conversation already carries it', async () => {
    await mountWithHydratedConversation();
    const baselineRequests = snapshotRequests();

    await sendPromptAndWaitForConnect('follow-up question');

    // Same page, same project, same rule oids -- both providers stay quiet.
    expect(sentContext()).toEqual({});

    // Quiet at the request level too: the rules are read off the conversation,
    // so the resolver is not asked again.
    expectGraphQLCalls(baselineRequests, { expect: [], forbid: ['getRuleContent'] });
  });

  it('sends the page context again after the user navigates, but not the rules', async () => {
    await mountWithHydratedConversation();
    const baselineRequests = snapshotRequests();

    setWindowLocation(OTHER_PAGE_PATH);

    await sendPromptAndWaitForConnect('question from another page');

    const context = sentContext();

    // The project did not change, so the rules are still in the conversation and
    // are neither re-sent nor re-fetched.
    expect(Object.keys(context)).toEqual([AI_CONTEXT_ID_PAGE_CONTEXT]);
    expect(context[AI_CONTEXT_ID_PAGE_CONTEXT].metadata.pagePath).toBe(OTHER_PAGE_PATH);
    expectGraphQLCalls(baselineRequests, { expect: [], forbid: ['getRuleContent'] });
  });

  it('sends the context again in a new chat', async () => {
    await mountWithHydratedConversation();

    // `/new` routes through onNewChat, which drops the conversation and calls
    // resetContextInjectionState, so nothing is left to de-duplicate against.
    sendPrompt('/new');

    await waitFor(() => {
      expect(getText(findChatMessages())).not.toContain(EARLIER_ANSWER);
    });

    const baselineRequests = snapshotRequests();

    await sendPromptAndWaitForConnect('question in the new chat');

    expect(Object.keys(sentContext()).sort()).toEqual([...EXPECTED_CONTEXT_IDS].sort());

    // Re-fetched rather than replayed from what the previous conversation held,
    // which is the difference between resetting the state and merely resending.
    expectGraphQLCalls(baselineRequests, { expect: ['getRuleContent'], forbid: [] });
  });

  it('renders the injected context as expandable tokens on the user message', async () => {
    await mountAndWaitForComposer();
    await sendPromptAndWaitForConnect('first question');

    // The only test that needs the checkpoint: context tokens are rendered from
    // the message the workflow service returns, never from the outgoing send.
    // Echoing the client's own items back is the point here -- the assertion is
    // that whatever the providers produced reaches the transcript. `metadata` is
    // a JSON string on the wire out and an object in the checkpoint, so it has to
    // be parsed on the way back in.
    await pushCheckpoint([
      userLogEntry({
        id: 'user-1',
        content: 'first question',
        additionalContext: Object.entries(sentContext()).map(([id, item]) => ({ id, ...item })),
      }),
      agentLogEntry({ id: 'agent-1', content: 'first answer' }),
    ]);

    await waitFor(() => {
      expect(findContextSelectionTitles()).toHaveLength(1);
    });

    // The tokens are collapsed behind the "included reference" summary; expand
    // it the way a user would.
    findContextSelectionTitles()[0].click();

    // One token per injected item and nothing else, labelled with the titles the
    // providers set.
    await waitFor(() => {
      expect(findContextTokenLabels().sort()).toEqual(
        ['Current page', 'AGENTS.md', 'chat-rules.md'].sort(),
      );
    });
  });
});
