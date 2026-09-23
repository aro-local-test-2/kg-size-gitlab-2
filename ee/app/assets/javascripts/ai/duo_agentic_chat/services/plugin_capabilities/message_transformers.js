import isObject from 'lodash-es/isObject';
import { captureExceptionForDuoChat } from '../../observability/sentry_utils';

/**
 * @typedef {Object} MessageTransformer
 * @property {(messages: Object[]) => Object[]} transformMessages - Receives the whole
 *   message log and returns the log the chat renders, so a plugin can rewrite or drop
 *   messages that its widgets cannot express on their own. Called from a computed on
 *   every change to the log, so it must be pure, cheap, and must not mutate its input.
 */

const LOG_PREFIX = '[duo-chat][transformer]';

const report = (message) => captureExceptionForDuoChat(new Error(message));

/**
 * Logs both sides of a transform, in development only.
 *
 * A transformer rewriting the log leaves no trace in the UI -- a dropped message simply
 * is not there -- so the only way to tell a working transformer from a too-eager one is
 * to see what went in and what came out.
 *
 * Development only because this runs off a computed that recomputes on every streamed
 * update: unguarded, it would fill every user's console with repeated copies of their
 * whole conversation.
 *
 * Kept at `info` rather than `error`: a transform is not a fault, and ConsoleWatcher turns
 * `console.error` into a thrown error in jest.
 */
const logTransform = (plugin, before, after) => {
  if (process.env.NODE_ENV !== 'development') return;

  // eslint-disable-next-line no-console
  console.info(`${LOG_PREFIX} ${plugin}`, {
    before: { count: before?.length, messages: before },
    after: { count: after.length, messages: after },
  });
};

/**
 * Wraps a contributed transformer so a broken one cannot take the transcript with it:
 * a throw, or anything but an array back, leaves the log exactly as it arrived.
 */
const isolate =
  (plugin, { transformMessages }) =>
  (messages) => {
    try {
      const transformed = transformMessages(messages);

      if (!Array.isArray(transformed)) {
        report(`Duo Chat plugin "${plugin}" did not return an array of messages`);
        return messages;
      }

      logTransform(plugin, messages, transformed);

      return transformed;
    } catch (error) {
      // Reported and skipped: one bad transformer must not blank the conversation.
      captureExceptionForDuoChat(error);
      return messages;
    }
  };

export const messageTransformers = {
  key: 'messageTransformers',

  /**
   * Validates if a message transformer is valid.
   *
   * @param {unknown} transformer
   * @returns {string[]} One message per contract violation; empty when valid.
   */
  validate(transformer) {
    if (!isObject(transformer)) {
      // eslint-disable-next-line @gitlab/require-i18n-strings -- reported to Sentry for the plugin author, never rendered
      return ['must be an object'];
    }

    return typeof transformer.transformMessages === 'function'
      ? []
      : ['`transformMessages` must be a function'];
  },

  /**
   * Flattens every plugin's transformers into the pipeline `runMessageTransformers`
   * consumes. Registration order is application order, and the host runs these after
   * its own built-ins, so a plugin always sees an already-normalised log.
   *
   * Resolvers are also handed the capability dependency bag; this one has no use for
   * it, so it is left off the signature rather than declared and ignored.
   *
   * @param {import('../plugin_registry').DuoChatPlugin[]} plugins
   * @returns {((messages: Object[]) => Object[])[]}
   */
  resolve(plugins) {
    return plugins.flatMap(({ name, messageTransformers: transformers = [] }) =>
      transformers.map((transformer) => isolate(name, transformer)),
    );
  },
};
