import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

describe('DuoChatPluginRegistry', () => {
  let registry;

  const widget = { matchMessage: () => true, component: { name: 'SomeWidget' } };
  const plugin = { name: 'a_plugin', messageWidgets: [widget] };

  const reportedError = () => captureExceptionForDuoChat.mock.calls[0][0].message;

  beforeEach(() => {
    registry = new DuoChatPluginRegistry();
  });

  it('starts empty', () => {
    expect(registry.plugins).toEqual([]);
  });

  it('registers a valid plugin', () => {
    registry.registerPlugin(plugin);

    expect(registry.plugins).toEqual([plugin]);
    expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
  });

  it('registers a plugin contributing more than one capability', () => {
    const contributor = {
      name: 'a_contributor',
      messageWidgets: [widget],
      slashCommands: [{ getCommands: () => [] }],
    };

    registry.registerPlugin(contributor);

    expect(registry.plugins).toEqual([contributor]);
    expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
  });

  it('preserves registration order', () => {
    const other = { name: 'another_plugin', messageWidgets: [] };

    registry.registerPlugin(plugin);
    registry.registerPlugin(other);

    expect(registry.plugins).toEqual([plugin, other]);
  });

  it('returns a copy, so a caller cannot mutate the registry', () => {
    registry.registerPlugin(plugin);
    registry.plugins.push({ name: 'sneaky', messageWidgets: [] });

    expect(registry.plugins).toEqual([plugin]);
  });

  describe('invalid plugins', () => {
    it.each([null, 'plugin', 42])('rejects %p', (invalid) => {
      registry.registerPlugin(invalid);

      expect(registry.plugins).toEqual([]);
      expect(reportedError()).toBe('Invalid Duo Chat plugin: plugin must be an object');
    });

    it.each([
      ['a missing name', { messageWidgets: [widget] }],
      ['an empty name', { name: '', messageWidgets: [widget] }],
      ['a blank name', { name: '   ', messageWidgets: [widget] }],
      ['a non-string name', { name: 42, messageWidgets: [widget] }],
    ])('rejects %s', (_, invalid) => {
      registry.registerPlugin(invalid);

      expect(registry.plugins).toEqual([]);
      expect(reportedError()).toBe('Invalid Duo Chat plugin: `name` must be a non-empty string');
    });

    it('does not treat `name` as a capability', () => {
      registry.registerPlugin({ name: 'named_plugin' });

      expect(registry.plugins).toEqual([{ name: 'named_plugin' }]);
      expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
    });

    it('rejects an unrecognised capability, so a typo is not silently ignored', () => {
      registry.registerPlugin({ name: 'typo_plugin', messageWidget: [widget] });

      expect(registry.plugins).toEqual([]);
      expect(reportedError()).toBe(
        'Invalid Duo Chat plugin "typo_plugin": unknown capability `messageWidget`',
      );
    });

    it('rejects a capability that is not an array', () => {
      registry.registerPlugin({ name: 'not_an_array', messageWidgets: widget });

      expect(registry.plugins).toEqual([]);
      expect(reportedError()).toBe(
        'Invalid Duo Chat plugin "not_an_array": `messageWidgets` must be an array',
      );
    });

    it('reports which entry failed and why', () => {
      registry.registerPlugin({ name: 'bad_entry', messageWidgets: [widget, { component: {} }] });

      expect(registry.plugins).toEqual([]);
      expect(reportedError()).toBe(
        'Invalid Duo Chat plugin "bad_entry": messageWidgets[1] `matchMessage` must be a function',
      );
    });

    it('reports every violation across the plugin', () => {
      registry.registerPlugin({ name: 'many_problems', messageWidgets: [{}], slashCommand: [] });

      expect(reportedError()).toBe(
        'Invalid Duo Chat plugin "many_problems": ' +
          'messageWidgets[0] `matchMessage` must be a function; ' +
          'messageWidgets[0] `component` must be a Vue component; ' +
          'unknown capability `slashCommand`',
      );
    });
  });
});
