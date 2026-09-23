import { humanize } from '~/lib/utils/text_utility';
import { CLIENT_TYPES, DEFAULT_CLIENT_TYPE } from './constants';

/**
 * Converts a snake_case audit event name into a human-readable title.
 *
 * Examples:
 *   'ai_agent_session_ended'   => 'Agent session ended'
 *   'ai_llm_input_sent'        => 'Llm input sent'
 *   'ai_tool_invoked'          => 'Tool invoked'
 *
 * @param {string} name - The raw event name from the API.
 * @returns {string}
 */
export function formatEventName(name) {
  if (!name) return '';
  return name
    .replace(/^ai_/, '')
    .replace(/_/g, ' ')
    .replace(/^./, (c) => c.toUpperCase());
}

/**
 * Returns the client type object for a session artifact item.
 *
 * `agentType` is null for sessions run on the GitLab Duo Agent Platform and a
 * raw value like `claude-code` for external agents. Unknown values are
 * humanised so the report never misattributes a session to GitLab Duo.
 *
 * @param {Object} item - A session artifact item.
 * @returns {{ name: string, icon?: string }}
 */
export function getClientType(item) {
  if (!item.agentType) {
    return DEFAULT_CLIENT_TYPE;
  }

  return CLIENT_TYPES[item.agentType] || { name: humanize(item.agentType, '-') };
}
