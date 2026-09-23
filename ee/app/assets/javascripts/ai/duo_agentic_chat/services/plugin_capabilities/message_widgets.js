/* eslint-disable @gitlab/require-i18n-strings */
import isPlainObject from 'lodash-es/isPlainObject';

/**
 * @typedef {Object} MessageWidget
 * @property {(message: Object) => boolean} matchMessage - Claims a message for this
 *   widget. Must be pure and cheap: duo-ui calls it for every renderer against every
 *   message.
 * @property {Object} component - Vue SFC rendering the message.
 * @property {((message: Object, workingDirectory: string, dependencies: Object) => Object)|Object} [defaultProps] -
 *   Replaces (not merges with) the default `{ message, workingDirectory }` props.
 *   duo-ui supplies the first two arguments; `resolve` supplies the third, so a
 *   widget can read `{ apollo, duoChatContext, ... }` without a provide/inject pair.
 * @property {'inline'|'pinned'} [layout] - `pinned` renders at the conversation tail.
 * @property {boolean} [groupable] - `false` keeps a tool message out of tool-groups.
 */

const LAYOUTS = ['inline', 'pinned'];

// duo-ui owns the `defaultProps` call and only ever passes `(message, workingDirectory)`,
// so the resolver is the sole place the chat's context can reach a widget. Bound here
// rather than read from an injector: a plugin descriptor is module-level and has no
// component instance to inject into.
const bindDependencies = (widget, dependencies) =>
  typeof widget.defaultProps === 'function'
    ? {
        ...widget,
        defaultProps: (message, workingDirectory) =>
          widget.defaultProps(message, workingDirectory, dependencies),
      }
    : widget;

export const messageWidgets = {
  key: 'messageWidgets',

  /**
   * Validates if a message widget is valid.
   *
   * @param {unknown} widget
   * @returns {string[]} One message per contract violation; empty when valid.
   */
  validate(widget) {
    if (!isPlainObject(widget)) {
      return ['must be an object'];
    }

    const { matchMessage, component, defaultProps, layout, groupable } = widget;
    const errors = [];

    if (typeof matchMessage !== 'function') {
      errors.push('`matchMessage` must be a function');
    }

    if (!isPlainObject(component)) {
      errors.push('`component` must be a Vue component');
    }

    if (
      defaultProps !== undefined &&
      typeof defaultProps !== 'function' &&
      !isPlainObject(defaultProps)
    ) {
      errors.push('`defaultProps` must be a function or an object');
    }

    if (layout !== undefined && !LAYOUTS.includes(layout)) {
      errors.push(`\`layout\` must be one of: ${LAYOUTS.join(', ')}`);
    }

    if (groupable !== undefined && typeof groupable !== 'boolean') {
      errors.push('`groupable` must be a boolean');
    }

    return errors;
  },

  /**
   * Flattens every plugin's widgets into the descriptor array duo-ui's MessageMap
   * consumes. Registration order is precedence order: duo-ui merges these ahead of
   * its built-ins and takes the first match.
   *
   * @param {import('../plugin_registry').DuoChatPlugin[]} plugins
   * @param {Object} [dependencies] - Handed to each `defaultProps` unread. `apollo` is
   *   the caller's vue-apollo wrapper; `duoChatContext` carries the ids the chat is
   *   pointed at; `duoChatState` carries chat state a widget cannot reach on its own.
   * @returns {MessageWidget[]}
   */
  resolve(plugins, dependencies = {}) {
    return plugins.flatMap(({ messageWidgets: widgets = [] }) =>
      widgets.map((widget) => bindDependencies(widget, dependencies)),
    );
  },
};
