/**
 * Namespacing keeps a flow from colliding with a built-in command, and makes it
 * obvious in the composer that what follows starts a flow.
 */
/* eslint-disable-next-line @gitlab/no-hardcoded-urls -- a slash command, not a URL */
export const FLOW_COMMAND_PREFIX = '/flow:';
