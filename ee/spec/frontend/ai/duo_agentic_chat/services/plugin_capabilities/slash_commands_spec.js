import {
  slashCommands,
  isSlashCommandGroup,
} from 'ee/ai/duo_agentic_chat/services/plugin_capabilities/slash_commands';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

describe('slashCommands capability', () => {
  const newCommand = { value: '/new', description: 'Start a new conversation' };
  const compactCommand = { value: '/compact', description: 'Compact this conversation' };

  const CONTEXT = { projectId: 'gid://gitlab/Project/1' };

  const pluginWith = (...commands) => ({
    name: 'a_plugin',
    slashCommands: [{ getCommands: jest.fn().mockResolvedValue(commands) }],
  });

  const providing = (commands) => ({ getCommands: () => Promise.resolve(commands) });

  const reportedErrors = () =>
    captureExceptionForDuoChat.mock.calls.map(([error]) => error.message);

  it('is filed under the `slashCommands` plugin key', () => {
    expect(slashCommands.key).toBe('slashCommands');
  });

  describe('isSlashCommandGroup', () => {
    it('tells a group from a bare command by its `items`', () => {
      expect(isSlashCommandGroup({ label: 'Pipelines', items: [] })).toBe(true);
      expect(isSlashCommandGroup(newCommand)).toBe(false);
    });

    it.each([null, undefined, { items: 'not a list' }])('reads %p as not a group', (entry) => {
      expect(isSlashCommandGroup(entry)).toBe(false);
    });
  });

  describe('validate', () => {
    it('accepts a provider that can be asked for commands', () => {
      expect(slashCommands.validate({ getCommands: () => [] })).toEqual([]);
    });

    it.each([null, undefined, 'provider', 7])('rejects %p as a provider', (provider) => {
      expect(slashCommands.validate(provider)).toEqual(['must be an object']);
    });

    it.each([undefined, 'getCommands', {}])('rejects `getCommands` of %p', (getCommands) => {
      expect(slashCommands.validate({ getCommands })).toEqual(['`getCommands` must be a function']);
    });
  });

  describe('resolve', () => {
    it('returns nothing when no plugin contributes commands', async () => {
      await expect(slashCommands.resolve([{ name: 'widgets_only' }], {})).resolves.toEqual([]);
    });

    it('flattens the commands of every plugin, in registration order', async () => {
      const plugins = [
        { name: 'first', slashCommands: [providing([newCommand])] },
        { name: 'second', slashCommands: [providing([compactCommand])] },
      ];

      await expect(slashCommands.resolve(plugins, { duoChatContext: CONTEXT })).resolves.toEqual([
        newCommand,
        compactCommand,
      ]);
    });

    it('passes the dependencies through to the provider', async () => {
      const plugin = pluginWith(newCommand);
      const dependencies = { apollo: { query: jest.fn() }, duoChatContext: CONTEXT };

      await slashCommands.resolve([plugin], dependencies);

      expect(plugin.slashCommands[0].getCommands).toHaveBeenCalledWith(dependencies);
    });

    describe('groups', () => {
      const pipelines = (...items) => ({ label: 'Pipelines', order: 20, items });

      it('hands groups on untouched, for the menu to lay out', async () => {
        const group = pipelines(compactCommand);

        await expect(
          slashCommands.resolve([pluginWith(newCommand, group)], { duoChatContext: CONTEXT }),
        ).resolves.toEqual([newCommand, group]);
      });

      it('leaves two groups sharing a label separate, since merging them is layout', async () => {
        const plugins = [pluginWith(pipelines(newCommand)), pluginWith(pipelines(compactCommand))];

        await expect(slashCommands.resolve(plugins, { duoChatContext: CONTEXT })).resolves.toEqual([
          pipelines(newCommand),
          pipelines(compactCommand),
        ]);
      });

      it('drops a group whose items are all taken, rather than leaving a bare heading', async () => {
        const plugins = [pluginWith(newCommand), pluginWith(pipelines(newCommand))];

        await expect(slashCommands.resolve(plugins, { duoChatContext: CONTEXT })).resolves.toEqual([
          newCommand,
        ]);
      });

      it('drops an empty group', async () => {
        await expect(
          slashCommands.resolve([pluginWith(pipelines())], { duoChatContext: CONTEXT }),
        ).resolves.toEqual([]);
        expect(reportedErrors()).toEqual([]);
      });

      it('leaves `order` to the menu by defaulting nothing', async () => {
        const group = { label: 'Pipelines', items: [newCommand] };

        await expect(
          slashCommands.resolve([pluginWith(group)], { duoChatContext: CONTEXT }),
        ).resolves.toEqual([group]);
      });
    });

    describe('when a provider misbehaves', () => {
      it('drops and reports a provider that throws', async () => {
        const error = new Error('the backend said no');
        const broken = {
          name: 'broken',
          slashCommands: [{ getCommands: () => Promise.reject(error) }],
        };

        await expect(
          slashCommands.resolve([broken, pluginWith(newCommand)], { duoChatContext: CONTEXT }),
        ).resolves.toEqual([newCommand]);
        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(error);
      });

      it('drops and reports a provider that returns no array', async () => {
        const plugin = { name: 'not_a_list', slashCommands: [providing(null)] };

        await expect(slashCommands.resolve([plugin], { duoChatContext: CONTEXT })).resolves.toEqual(
          [],
        );
        expect(reportedErrors()).toEqual([
          'Duo Chat plugin "not_a_list" did not return an array of slash commands',
        ]);
      });

      // The menu lowercases the value while filtering, so this would throw rather than
      // simply render nothing.
      it('drops and reports a command with no value', async () => {
        const plugin = {
          name: 'valueless',
          slashCommands: [providing([{ description: 'no value' }, newCommand])],
        };

        await expect(slashCommands.resolve([plugin], { duoChatContext: CONTEXT })).resolves.toEqual(
          [newCommand],
        );
        expect(reportedErrors()).toEqual([
          'Duo Chat plugin "valueless" contributed a slash command without a value',
        ]);
      });

      it.each(['insert', 'startGoal'])(
        'keeps a command that names the %p action the composer implements',
        async (action) => {
          const plugin = pluginWith({ value: '/goal', description: 'Set a goal', action });

          await expect(
            slashCommands.resolve([plugin], { duoChatContext: CONTEXT }),
          ).resolves.toEqual([{ value: '/goal', description: 'Set a goal', action }]);
          expect(reportedErrors()).toEqual([]);
        },
      );

      // Kept rather than dropped: a command with no action is the norm, and only a
      // present-but-unusable one is a mistake.
      it('keeps a command with no action', async () => {
        const plugin = pluginWith(newCommand);

        await expect(slashCommands.resolve([plugin], { duoChatContext: CONTEXT })).resolves.toEqual(
          [newCommand],
        );
        expect(reportedErrors()).toEqual([]);
      });

      // The composer dispatches on the action by name, so anything it does not implement
      // would leave the command looking like it does more than insert its value. Any name
      // outside `PROMPT_COMPOSER_ACTIONS` is a mistake -- including the prototype keys a
      // lookup by name would otherwise find.
      it.each(['summonBadger', 'constructor', '__proto__', {}, 42, null])(
        'drops and reports a command whose action is %p',
        async (action) => {
          const plugin = {
            name: 'a_plugin',
            slashCommands: [providing([{ value: '/goal', description: 'Set a goal', action }])],
          };

          await expect(
            slashCommands.resolve([plugin], { duoChatContext: CONTEXT }),
          ).resolves.toEqual([]);
          expect(reportedErrors()).toEqual([
            `Duo Chat plugin "a_plugin" contributed slash command \`/goal\` with an unknown action \`${action}\``,
          ]);
        },
      );

      // A label is only ever rendered, so it cannot break the menu the way a missing
      // value does.
      it('keeps a command that has no label', async () => {
        const plugin = pluginWith({ value: '/labelless', description: 'no label' });

        await expect(slashCommands.resolve([plugin], { duoChatContext: CONTEXT })).resolves.toEqual(
          [{ value: '/labelless', description: 'no label' }],
        );
        expect(reportedErrors()).toEqual([]);
      });

      // A group is the unit the plugin declared, so it goes whole rather than
      // having its commands quietly rehomed among the ungrouped ones.
      it.each(['', '   ', undefined, null, 7])(
        'drops and reports a group labelled %p, items included',
        async (label) => {
          const plugin = pluginWith({ label, items: [compactCommand] }, newCommand);

          await expect(
            slashCommands.resolve([plugin], { duoChatContext: CONTEXT }),
          ).resolves.toEqual([newCommand]);
          expect(reportedErrors()).toEqual([
            'Duo Chat plugin "a_plugin" contributed a slash command group without a label',
          ]);
        },
      );

      // One report naming the real problem, rather than a pile of item errors
      // for a group that was never going to render.
      it('does not also report the items of a group it drops', async () => {
        const plugin = pluginWith({ label: '', items: [{ description: 'no value' }] });

        await expect(slashCommands.resolve([plugin], { duoChatContext: CONTEXT })).resolves.toEqual(
          [],
        );
        expect(reportedErrors()).toEqual([
          'Duo Chat plugin "a_plugin" contributed a slash command group without a label',
        ]);
      });

      it('drops and reports a valueless command from inside a group', async () => {
        const plugin = pluginWith({
          label: 'Pipelines',
          items: [{ description: 'no value' }, newCommand],
        });

        await expect(slashCommands.resolve([plugin], { duoChatContext: CONTEXT })).resolves.toEqual(
          [{ label: 'Pipelines', items: [newCommand] }],
        );
        expect(reportedErrors()).toEqual([
          'Duo Chat plugin "a_plugin" contributed a slash command without a value',
        ]);
      });

      it('keeps the first of two commands sharing a value, and reports the other', async () => {
        const plugins = [
          pluginWith(newCommand),
          pluginWith({ ...newCommand, description: 'dupe' }),
        ];

        await expect(slashCommands.resolve(plugins, { duoChatContext: CONTEXT })).resolves.toEqual([
          newCommand,
        ]);
        expect(reportedErrors()).toEqual(['Duplicate Duo Chat slash command `/new` dropped']);
      });
    });
  });
});
