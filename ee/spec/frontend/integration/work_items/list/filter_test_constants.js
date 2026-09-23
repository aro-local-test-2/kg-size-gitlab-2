export const WORK_ITEMS = {
  DEPENDENT: 'Dependent test issue',
  SECOND: 'Second test issue',
  CHILD_TASK: 'Child task',
  BLOCKING: 'Blocking issue',
  LINKABLE: 'Linkable test issue',
  AGENT_PLAN: 'Agent plan test issue',
};

/**
 * Filter values the seed creates. Specs build URLs from these so a seed change is a
 * one-line edit. Assertions still use literals, so a drift fails a test rather than
 * quietly agreeing with itself.
 */
export const FILTER_VALUES = {
  LABEL: 'To Do',
  OTHER_LABEL: 'Doing',
  REACTION: 'thumbsup',
  ASSIGNABLE_USER: 'assignable_user',
  SECOND_ASSIGNABLE_USER: 'second_assignable_user',
  MILESTONE: 'v1.0',
  RELEASE: 'v1.0.0',
};

export const PROJECT_PATH = 'gitlab-org/gitlab';
export const GROUP_PATH = 'gitlab-org';
