import { s__ } from '~/locale';

export const AGENT_SESSION_INBOX_STATUS_LABELS = {
  INPUT_REQUIRED: s__('DuoAgentsPlatform|Waiting for input'),
  PLAN_APPROVAL_REQUIRED: s__('DuoAgentsPlatform|Approval gate'),
  TOOL_CALL_APPROVAL_REQUIRED: s__('DuoAgentsPlatform|Confirm action'),
  STOPPED: s__('DuoAgentsPlatform|Canceled'),
};

export const STATUS_TEXT_CLASS = {
  neutral: 'gl-text-status-neutral',
  info: 'gl-text-status-info',
  success: 'gl-text-status-success',
  warning: 'gl-text-status-warning',
  danger: 'gl-text-status-danger',
};
