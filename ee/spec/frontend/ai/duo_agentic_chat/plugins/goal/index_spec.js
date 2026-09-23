import { goalPlugin } from 'ee/ai/duo_agentic_chat/plugins/goal';
import { PROMPT_COMPOSER_ACTIONS } from 'ee/ai/duo_agentic_chat/constants';
import { slashCommands } from 'ee/ai/duo_agentic_chat/services/plugin_capabilities/slash_commands';

describe('goalPlugin', () => {
  const PROJECT_ID = 'gid://gitlab/Project/1';

  beforeEach(() => {
    window.gon = { features: { duoChatGoalCommand: true } };
  });

  const apolloReturning = (...consumers) => ({
    query: jest.fn().mockResolvedValue({
      data: { aiCatalogConfiguredItems: { nodes: consumers } },
    }),
  });

  const configuredFlow = apolloReturning({ id: 'gid://gitlab/Ai::Catalog::ItemConsumer/7' });

  const commandsOf = (apollo, duoChatContext = { projectId: PROJECT_ID }) =>
    slashCommands.resolve([goalPlugin], { apollo, duoChatContext });

  it('is filed under a name that identifies it in plugin reports', () => {
    expect(goalPlugin.name).toBe('goal');
  });

  it('offers one command, which the capability accepts', async () => {
    await expect(commandsOf(configuredFlow)).resolves.toEqual([
      {
        label: 'Goal',
        value: '/goal',
        description: 'Work towards a goal until it is achieved',
        startOnly: true,
        action: PROMPT_COMPOSER_ACTIONS.START_GOAL,
      },
    ]);
  });

  // The only thing tying the command to the mode it starts.
  it('names the action the composer starts goal mode for', async () => {
    const [command] = await commandsOf(configuredFlow);

    expect(command.action).toBe('startGoal');
  });

  describe('when goal mode cannot run', () => {
    // Offering a command that could only fail is worse than offering none.
    it('offers nothing when no Developer flow is configured', async () => {
      await expect(commandsOf(apolloReturning())).resolves.toEqual([]);
    });

    it('offers nothing, and asks nothing, without a project', async () => {
      const apollo = apolloReturning();

      await expect(commandsOf(apollo, {})).resolves.toEqual([]);
      expect(apollo.query).not.toHaveBeenCalled();
    });

    // A mount with no state manager above it passes no context at all.
    it('offers nothing without a chat context', async () => {
      await expect(slashCommands.resolve([goalPlugin], {})).resolves.toEqual([]);
    });

    // The registry already gates on this flag; checked again so the two cannot disagree.
    it('offers nothing with the feature off', async () => {
      window.gon = { features: {} };

      await expect(commandsOf(configuredFlow)).resolves.toEqual([]);
    });
  });
});
