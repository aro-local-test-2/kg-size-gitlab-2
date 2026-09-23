import { messageTransformers } from 'ee/ai/duo_agentic_chat/services/plugin_capabilities/message_transformers';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

describe('messageTransformers capability', () => {
  const messages = [{ id: 'a' }, { id: 'b' }];

  const pluginWith = (transformMessages, name = 'a_plugin') => ({
    name,
    messageTransformers: [{ transformMessages }],
  });

  const runAll = (plugins, log = messages) =>
    messageTransformers.resolve(plugins).reduce((current, transform) => transform(current), log);

  const reportedErrors = () =>
    captureExceptionForDuoChat.mock.calls.map(([error]) => error.message);

  let logSpy;

  beforeEach(() => {
    logSpy = jest.spyOn(console, 'info').mockImplementation();
  });

  it('is filed under the `messageTransformers` plugin key', () => {
    expect(messageTransformers.key).toBe('messageTransformers');
  });

  describe('validate', () => {
    it('accepts a transformer that can rewrite the log', () => {
      expect(messageTransformers.validate({ transformMessages: (msgs) => msgs })).toEqual([]);
    });

    it.each([null, undefined, 'transformer', 7])('rejects %p as a transformer', (transformer) => {
      expect(messageTransformers.validate(transformer)).toEqual(['must be an object']);
    });

    it.each`
      description                           | transformer                      | error
      ${'a missing transformMessages'}      | ${{}}                            | ${'`transformMessages` must be a function'}
      ${'a non-function transformMessages'} | ${{ transformMessages: 'nope' }} | ${'`transformMessages` must be a function'}
    `('reports $description', ({ transformer, error }) => {
      expect(messageTransformers.validate(transformer)).toEqual([error]);
    });
  });

  describe('resolve', () => {
    it('returns an empty array when there are no plugins', () => {
      expect(messageTransformers.resolve([])).toEqual([]);
    });

    it('skips plugins that contribute no transformers', () => {
      expect(messageTransformers.resolve([{}, pluginWith((msgs) => msgs)])).toHaveLength(1);
    });

    it('hands the whole log to the transformer', () => {
      const transformMessages = jest.fn().mockReturnValue([]);

      runAll([pluginWith(transformMessages)]);

      expect(transformMessages).toHaveBeenCalledWith(messages);
    });

    it('lets a transformer drop messages', () => {
      const dropB = (msgs) => msgs.filter(({ id }) => id !== 'b');

      expect(runAll([pluginWith(dropB)])).toEqual([{ id: 'a' }]);
    });

    // Application order is registration order, so a plugin can rely on seeing the
    // output of everything contributed before it.
    it('applies transformers across plugins in registration order', () => {
      const appendFirst = (msgs) => [...msgs, { id: 'first' }];
      const appendSecond = (msgs) => [...msgs, { id: 'second' }];

      expect(runAll([pluginWith(appendFirst, 'one'), pluginWith(appendSecond, 'two')], [])).toEqual(
        [{ id: 'first' }, { id: 'second' }],
      );
    });

    describe('logging', () => {
      const dropB = (msgs) => msgs.filter(({ id }) => id !== 'b');

      // The pipeline reruns on every streamed update, so an ungated log would repeatedly
      // copy a user's whole conversation into their console.
      it('stays quiet outside development', () => {
        runAll([pluginWith(dropB)]);

        expect(logSpy).not.toHaveBeenCalled();
      });

      describe('in development', () => {
        const { NODE_ENV } = process.env;

        beforeEach(() => {
          process.env.NODE_ENV = 'development';
        });

        afterEach(() => {
          process.env.NODE_ENV = NODE_ENV;
        });

        it('logs both sides of the transform, so a dropped message is still traceable', () => {
          runAll([pluginWith(dropB)]);

          expect(logSpy).toHaveBeenCalledWith('[duo-chat][transformer] a_plugin', {
            before: { count: 2, messages },
            after: { count: 1, messages: [{ id: 'a' }] },
          });
        });

        it('does not log a transformer that handed back no array', () => {
          runAll([pluginWith(() => undefined, 'not_a_list')]);

          expect(logSpy).not.toHaveBeenCalled();
        });
      });
    });

    describe('when a transformer misbehaves', () => {
      it('reports a transformer that throws and leaves the log alone', () => {
        const error = new Error('cannot read tool_info of undefined');
        const broken = () => {
          throw error;
        };

        expect(runAll([pluginWith(broken)])).toEqual(messages);
        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(error);
      });

      it('reports a transformer that returns no array and leaves the log alone', () => {
        expect(runAll([pluginWith(() => undefined, 'not_a_list')])).toEqual(messages);
        expect(reportedErrors()).toEqual([
          'Duo Chat plugin "not_a_list" did not return an array of messages',
        ]);
      });

      it('keeps running the remaining transformers', () => {
        const broken = () => {
          throw new Error('boom');
        };
        const dropB = (msgs) => msgs.filter(({ id }) => id !== 'b');

        expect(runAll([pluginWith(broken, 'broken'), pluginWith(dropB, 'healthy')])).toEqual([
          { id: 'a' },
        ]);
      });
    });
  });
});
