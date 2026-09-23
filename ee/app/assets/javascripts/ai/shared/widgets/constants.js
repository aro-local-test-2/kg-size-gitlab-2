import { s__ } from '~/locale';

export const SESSION_AWAITING_INPUT_GROUP = {
  statuses: ['INPUT_REQUIRED', 'PLAN_APPROVAL_REQUIRED', 'TOOL_CALL_APPROVAL_REQUIRED'],
  title: s__('DuoAgentPlatform|Awaiting your input'),
};

export const SESSION_OTHER_GROUPS = [
  { statuses: ['RUNNING'], title: s__('DuoAgentPlatform|Running') },
  { statuses: ['PAUSED'], title: s__('DuoAgentPlatform|Paused') },
  { statuses: ['FAILED'], title: s__('DuoAgentPlatform|Failed') },
  { statuses: ['CREATED'], title: s__('DuoAgentPlatform|Created') },
  { statuses: ['FINISHED'], title: s__('DuoAgentPlatform|Completed') },
  { statuses: ['STOPPED'], title: s__('DuoAgentPlatform|Cancelled') },
];

export const AGENT_SESSIONS_POLL_INTERVAL = 30000;
// Passed explicitly by both the sessions query and its subscription: the pushed frame
// only updates the list if it writes the same cache field key the query reads.
export const AGENT_SESSIONS_PAGE_SIZE = 20;

export const AWAITING_INPUT_HEADER_BG_CLASS = 'gl-bg-feedback-warning';
export const OTHER_GROUP_HEADER_BG_CLASS = 'gl-bg-subtle';
