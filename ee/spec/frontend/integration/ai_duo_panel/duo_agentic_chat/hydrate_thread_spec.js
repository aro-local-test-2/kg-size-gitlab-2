import { waitFor } from '@testing-library/vue';
import { saveSessionStorageValue } from '~/lib/utils/local_storage';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { DUO_CURRENT_WORKFLOW_STORAGE_KEY } from 'ee/ai/constants';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import {
  getWorkflowLatestCheckpoint,
  installDuoAIPanelHandlers,
} from '../test_support/api_handlers';
import {
  mountDuoAgenticChatStateManager,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';

// The real workflow stream runs here, but this spec never sends a prompt, so
// `connect()` is never reached and no socket is opened -- the hydration path is
// pure GraphQL. The websocket fake `setupDuoChatTest` installs is still in place
// so that if hydration ever did start a workflow, it would not reach for a real
// socket.

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

// NOTE: we intentionally do NOT mock `workflow_utils`, `apollo_utils`,
// or `chat_thread_snapshot`. These are the modules whose real behaviour
// the spec is exercising.

describe('Duo Agentic Chat | hydrating a thread through real Apollo', () => {
  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();

    // The state manager picks up workflowId from sessionStorage on mount and
    // hydrates that thread; seed it so hydrateActiveWorkflow runs against
    // our MSW fixture.
    saveSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY, {
      workflowId: getIdFromGraphQLId(getWorkflowLatestCheckpoint.workflow().id),
    });
  });

  afterEach(() => teardownDuoChatTest());

  it('renders the hydrated conversation with parsed tool_info and per-message context items', async () => {
    mountDuoAgenticChatStateManager();

    // Wait for hydrateActiveWorkflow to render the six fixture messages
    // (user-A, agent-A, tool-C, tool-D, user-B, agent-B). Both markers
    // below come from the conversation content — once they appear, the
    // tool message and both users' context tokens have all rendered.
    await waitFor(() => {
      // Regression #1 — `5dcff523`: `toolInfo` arrives from GraphQL as a
      // JSON string and `WorkflowUtils.normalizeDuoMessages` must parse it
      // into an object. The tool-message template (`message_tool.vue`)
      // reads `tool_info.name` and translates it through
      // `tool_message_registry` into a user-visible label — `gitlab_api_get`
      // becomes "Queried GitLab". Without the JSON.parse, `tool_info` is a
      // raw string, `tool_info.name` is `undefined`, and the readable
      // label never reaches the DOM.
      expect(getText(document.body)).toContain('Queried GitLab');

      // Regression #2 — `0c04847116`: Apollo's default `__typename:id`
      // normalisation would collapse the two messages'
      // `chat-rules-user-instructions` entries (same id) into a single
      // shared cache slot. User-A's chat-rules item has
      // `metadata.title: "chat-rules.md"`; user-B's has
      // `metadata.title: "Ignore previous chat-rules.md"` (the "ignore
      // previous" marker that fires when a previously injected file is
      // missing from the next project's repository). Without the
      // `AiAdditionalContext: { keyFields: false }` typePolicy in
      // `ee/app/assets/javascripts/ai/graphql/index.js`, user-B's metadata
      // is overwritten by user-A's and the "Ignore previous" title never
      // reaches the DOM.
      expect(getText(document.body)).toContain('Ignore previous chat-rules.md');
    });
  });
});
