import { waitFor } from '@testing-library/vue';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';
import { installDuoAIPanelHandlers } from '../test_support/api_handlers';
import {
  PROJECT_ID,
  findChatInput,
  findSlashCommandOptions,
  findSubmitButton,
  mountDuoAgenticChatStateManager,
  pressComposerKey,
  setupDuoChatTest,
  teardownDuoChatTest,
  typeInComposer,
} from '../test_support/test_setup';
import { getSockets, lastStartRequest, waitForSocket } from '../test_support/websocket_mock';

// Covers the slash-command menu end to end: the composer, the menu wrapped
// around it, and the prompt that reaches the websocket. The unit specs drive the
// menu in isolation, which cannot show that selecting a command actually submits
// the right thing.
//
// jsdom performs no layout, so the menu's caret measurement and floating-ui
// placement both resolve to zeros here. That is fine for this test -- it asserts
// behaviour, not geometry -- but it does mean positioning stays unverified.

describe('Duo Agentic Chat | slash commands', () => {
  const mountAndWaitForComposer = async ({ provide = {} } = {}) => {
    mountDuoAgenticChatStateManager({ propsData: { projectId: PROJECT_ID }, provide });

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });
  };

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  /**
   * Types a prefix, waits for the menu to narrow to the one matching command,
   * and takes it with Enter. No command submits on its own, so this leaves the
   * command sitting in the composer.
   */
  const chooseCommandFrom = async (typed, command) => {
    typeInComposer(typed);

    // The menu opens on a loading row first; options arrive once the plugins answer.
    await waitFor(() => {
      expect(findSlashCommandOptions().map((option) => option.textContent)).toEqual([
        expect.stringContaining(command),
      ]);
    });

    await pressComposerKey('Enter');

    // The trailing space is what closes the menu instead of re-matching the
    // command that was just inserted.
    await waitFor(() => {
      expect(findChatInput().value).toBe(`${command} `);
    });
  };

  // Choosing a command fills the composer and stops there, so the user can see
  // what they are about to run. Asserting a single socket after the send is what
  // pins the regression the menu's keyup swallowing exists to prevent: without
  // it the release of the selecting keydown reaches the composer and sends early.
  it('sends the chosen command down the wire, exactly once', async () => {
    await mountAndWaitForComposer();

    await chooseCommandFrom('/co', '/compact');

    expect(getSockets()).toHaveLength(0);

    await pressComposerKey('Enter');

    // The worker opens the socket only once startWorkflow connects.
    await waitFor(() => {
      expect(getSockets()).toHaveLength(1);
    });
    await waitForSocket();

    expect(lastStartRequest().goal).toBe('/compact');
  });

  // Choosing a command used to rewrite the whole prompt, so anything already
  // typed after it was lost on the way to the wire.
  it('keeps the rest of the prompt when a command is prefixed to it', async () => {
    await mountAndWaitForComposer();

    typeInComposer('/co summarise the thread above');
    findChatInput().setSelectionRange(3, 3);
    findChatInput().dispatchEvent(new Event('input', { bubbles: true }));

    await waitFor(() => {
      expect(findSlashCommandOptions()).toHaveLength(1);
    });

    await pressComposerKey('Enter');

    await waitFor(() => {
      expect(findChatInput().value).toBe('/compact summarise the thread above');
    });

    await pressComposerKey('Enter');

    await waitFor(() => {
      expect(getSockets()).toHaveLength(1);
    });
    await waitForSocket();

    expect(lastStartRequest().goal).toBe('/compact summarise the thread above');
  });

  // Not every command is a prompt. `/new` is intercepted by the state manager
  // (`shouldStartNewChat`), which starts a fresh chat and returns before any
  // workflow begins -- a difference the component specs cannot see, because the
  // composer emits `send-chat-prompt` either way.
  it('does not start a workflow for a command the chat handles itself', async () => {
    await mountAndWaitForComposer();

    await chooseCommandFrom('/n', '/new');

    await pressComposerKey('Enter');

    // Clearing the composer is the observable end of the send, so waiting on it
    // means a socket had every chance to open.
    await waitFor(() => {
      expect(findChatInput().value).toBe('');
    });

    expect(getSockets()).toHaveLength(0);
  });

  // The other tests use `/compact`, a bundled plugin command, so none of them would
  // catch the registry being bypassed. This one registers its own plugin to prove
  // commands really come from there, scoped to the chat's context.
  it('offers commands contributed by a plugin, scoped to the current chat', async () => {
    const getCommands = jest
      .fn()
      .mockResolvedValue([{ value: '/handover', description: 'Hand over to a human' }]);
    const duoChatPluginRegistry = new DuoChatPluginRegistry();
    duoChatPluginRegistry.registerPlugin({
      name: 'a_plugin',
      slashCommands: [{ getCommands }],
    });

    await mountAndWaitForComposer({ provide: { duoChatPluginRegistry } });

    await chooseCommandFrom('/ha', '/handover');

    expect(getCommands).toHaveBeenCalledWith(
      expect.objectContaining({
        duoChatContext: expect.objectContaining({ projectId: PROJECT_ID }),
      }),
    );
  });
});
