import { slashCommandContextFor } from 'ee/ai/duo_agentic_chat/context/slash_commands_context';

describe('slashCommandContextFor', () => {
  describe('a flow command', () => {
    const SCAN = {
      value: '/flow:security-scan',
      label: 'Security Scan',
      startOnly: true,
      consumerId: 42,
    };

    const contextFor = (text, slashCommands = [SCAN]) =>
      slashCommandContextFor({ text, slashCommands });

    const payloadFor = (text) => {
      const [item] = contextFor(text);

      return { ...item, content: JSON.parse(item.content) };
    };

    it('addresses the flow by consumer id, so the model never picks it', () => {
      const item = payloadFor('/flow:security-scan check the auth module');

      expect(item.category).toBe('duo_chat_command');
      expect(item.content).toEqual({
        command: 'flow',
        ai_catalog_item_consumer_id: 42,
        goal: 'check the auth module',
      });
    });

    // Rails rejects a mode the flow does not declare, and a flow command names none.
    it('sends no mode, so the flow runs the config it declares by default', () => {
      expect(payloadFor('/flow:security-scan go').content).not.toHaveProperty('mode');
    });

    // Rails falls back to the flow's own description only when the goal is absent.
    it.each(['/flow:security-scan', '/flow:security-scan   '])(
      'sends a null goal for %p, which carries none',
      (text) => {
        expect(payloadFor(text).content.goal).toBeNull();
      },
    );

    it('sends parsable metadata, which the service requires', () => {
      expect(JSON.parse(payloadFor('/flow:security-scan go').metadata)).toEqual({});
    });

    it('is case insensitive about the command it matches', () => {
      expect(payloadFor('/FLOW:Security-Scan go').content.goal).toBe('go');
    });

    // The builder records a command whose token appears anywhere in the text, and
    // `startOnly` is only honoured when offering one. A flow takes over the whole turn,
    // so a prompt that merely mentions one must not start it.
    it.each(['tell me what /flow:security-scan does', 'what does /flow:security-scan do?'])(
      'contributes nothing for %p, which only mentions the flow',
      (text) => {
        expect(contextFor(text)).toEqual([]);
      },
    );

    it('contributes nothing when no command was recorded', () => {
      expect(contextFor('what does this project do?', [])).toEqual([]);
    });

    // Commands that contribute nothing to the turn land in the same list.
    it('ignores a command that carries no consumer id', () => {
      expect(contextFor('/compact', [{ value: '/compact' }])).toEqual([]);
    });

    it('picks the flow out from among other commands', () => {
      const context = contextFor('/flow:security-scan go', [{ value: '/compact' }, SCAN]);

      expect(JSON.parse(context[0].content).ai_catalog_item_consumer_id).toBe(42);
    });

    it.each([undefined, {}, { text: '/flow:security-scan' }])(
      'tolerates a prompt of %p',
      (userPrompt) => {
        expect(slashCommandContextFor(userPrompt)).toEqual([]);
      },
    );
  });

  describe('a goal prompt', () => {
    const contextFor = (text, goalFlow = { consumerId: 7 }) =>
      slashCommandContextFor({ text, goalFlow });

    const payloadFor = (...args) => {
      const [item] = contextFor(...args);

      return { ...item, content: JSON.parse(item.content) };
    };

    // The action took the token out, so there is no prefix left to strip off the goal.
    it('starts the goal flow with the whole prompt as the goal', () => {
      const item = payloadFor('keep the pipeline green');

      expect(item.category).toBe('duo_chat_command');
      expect(item.content).toEqual({
        command: 'flow',
        ai_catalog_item_consumer_id: 7,
        goal: 'keep the pipeline green',
        mode: 'goal',
      });
    });

    // Without it the same flow runs its ordinary config.
    it('names the mode that configures the flow for a goal', () => {
      expect(payloadFor('keep it green').content.mode).toBe('goal');
    });

    it('sends parsable metadata, which the service requires', () => {
      expect(JSON.parse(payloadFor('keep it green').metadata)).toEqual({});
    });

    it.each(['', '   '])('sends a null goal for %p, which carries none', (text) => {
      expect(payloadFor(text).content.goal).toBeNull();
    });

    // A command recorded beside a goal must not start a second flow.
    it('starts the goal flow rather than a command recorded beside it', () => {
      const context = slashCommandContextFor({
        text: 'keep it green',
        slashCommands: [{ value: '/flow:other', consumerId: 42 }],
        goalFlow: { consumerId: 7 },
      });

      expect(context).toHaveLength(1);
      expect(JSON.parse(context[0].content).ai_catalog_item_consumer_id).toBe(7);
    });

    it('contributes nothing for a prompt that is not in goal mode', () => {
      expect(slashCommandContextFor({ text: 'keep it green', goalFlow: null })).toEqual([]);
    });
  });
});
