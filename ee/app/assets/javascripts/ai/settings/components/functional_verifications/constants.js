export const FUNCTIONAL_VERIFICATION_STATUS = {
  NOT_RUN: 'NOT_RUN',
  RUNNING: 'RUNNING',
  PASSED: 'PASSED',
  FAILED: 'FAILED',
};

export const MODEL_PROVIDERS = {
  SELF_HOSTED: 'self_hosted',
  GITLAB_MANAGED: 'vendored',
  DISABLED: 'disabled',
};

export const AGENTIC_CHAT_FEATURE = 'duo_agent_platform_agentic_chat';

export const NAMESPACES_PAGE_SIZE = 20;

export const CHECK_TYPES = {
  AGENTIC_CHAT: 'AGENTIC_CHAT',
};

export const NOT_RUN_STATE = {
  state: FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN,
  checkedAt: null,
};
