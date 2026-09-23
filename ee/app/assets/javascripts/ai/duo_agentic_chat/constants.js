// WebSocket close codes
export const WS_CLOSE_NORMAL = 1000;
export const WS_CLOSE_GOING_AWAY = 1001; // server restart — retryable
export const WS_CLOSE_POLICY_VIOLATION = 1008;
export const WS_CLOSE_TRY_AGAIN_LATER = 1013;
export const WS_CLOSE_INVALID_REQUEST = 4400; // backend SendInvalidRequest() — non-retryable

export const MAX_WS_RETRIES = 3;
export const WS_RETRY_DELAY_MS = 1000;

// error codes
export const WORKFLOW_NOT_FOUND_CODE = 'WORKFLOW_NOT_FOUND';
export const NO_RESOURCE_PERMISSIONS = 'NO_RESOURCE_PERMISSIONS';
export const NO_DEFAULT_NAMESPACE_CODE = 'NO_DEFAULT_NAMESPACE';

export const FEEDBACK_TRACKING_EVENT = 'ai_duo_agentic_chat_feedback_submitted';
export const CHAT_TRACKING_EVENT = 'trigger_ai_catalog_item';

export const TRACKING_EVENT_VIEW_EMPTY_STATE = 'view_dap_trial_or_paid_empty_state';
export const TRACKING_EVENT_CLICK_AGENT = 'click_dap_trial_or_paid_empty_state_agent';
export const TRACKING_EVENT_CLICK_PROMPT = 'click_dap_trial_or_paid_empty_state_prompt';
export const TRACKING_EVENT_SELECT_PREDEFINED_PROMPT = 'select_duo_agentic_chat_predefined_prompt';
export const TRACKING_EVENT_CLICK_EXPLORE_AGENTS =
  'click_dap_trial_or_paid_empty_state_explore_agents_link';
export const TRACKING_EVENT_SUBMIT_MESSAGE = 'submit_dap_trial_or_paid_empty_state_message';

export const SUGGESTED_AGENTS_LIMIT = 3;

// The default foundational chat agent used when no specific agent is selected.
export const DEFAULT_AGENT_ID = 'gid://gitlab/Ai::FoundationalChatAgent/chat';

export const TRACKING_EVENT_RECOMMEND_TOOL = 'recommend_tool_duo_chat';
export const TRACKING_EVENT_TOOL_SUCCEEDED = 'tool_succeeded_duo_chat';
export const TRACKING_EVENT_TOOL_FAILED = 'tool_failed_duo_chat';
export const TRACKING_EVENT_APPROVE_TOOL = 'approve_tool_duo_chat';
export const TRACKING_EVENT_DENY_TOOL = 'deny_tool_duo_chat';
export const TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET = 'click_through_flow_widget';
export const TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL = 'click_through_session_pill';
export const TRACKING_EVENT_USER_CLICKED_RETRY = 'retry_message_duo_agentic_chat';
export const TRACKING_EVENT_RETRY_SUCCEEDED = 'retry_succeeded_duo_agentic_chat';
export const TRACKING_EVENT_RETRY_FAILED = 'retry_failed_duo_agentic_chat';
export const TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE =
  'navigate_retry_alternative_duo_agentic_chat';

export const TRACKING_EVENT_RESIZE_PANEL = 'resize_duo_chat_panel';
export const TRACKING_EVENT_MAXIMIZE_PANEL = 'maximize_duo_chat_panel';
export const TRACKING_EVENT_MINIMIZE_PANEL = 'minimize_duo_chat_panel';

export const TRIGGER_SOURCE_WEB_CHAT = 'web_chat';
export const TRIGGER_SOURCE_WEB_UI = 'web_ui';

export const TOOL_NAME_CLARIFICATION_QUESTION = 'clarification_question';
export const MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER = 'clarification_answer';
export const MESSAGE_SUB_TYPE_TIER_ACCESS_DENIED = 'tier_access_denied';

// Total attempts (including the initial one) made to load a saved thread's
// messages before showing the user a manual retry / new chat error state.
export const THREAD_LOAD_MAX_ATTEMPTS = 3;
export const THREAD_LOAD_RETRY_DELAY_MS = 10000;

// Kept in sync with the thread-load error handlers in the state manager: these
// codes end the load with a dedicated UI state, so they are never retried.
export const THREAD_LOAD_TERMINAL_ERROR_CODES = [
  WORKFLOW_NOT_FOUND_CODE,
  NO_RESOURCE_PERMISSIONS,
  NO_DEFAULT_NAMESPACE_CODE,
];

// Mirrors @gitlab/duo-ui's RETRY_STATE. Defined locally until the dependency
// is bumped past the release that exports it, then this should be replaced
// with a direct import from '@gitlab/duo-ui'.
export const RETRY_STATE = {
  PENDING: 'pending',
  FAILED: 'failed',
};

// What a live turn is reporting while the user waits. One value rather than a flag per
// indicator: they all answer "something is happening", so at most one can be on screen,
// and a set of booleans could contradict that.
export const TURN_PROGRESS = {
  NONE: 'none',
  RESPONSE: 'response',
  COMPACTING: 'compacting',
};

// Model selection dropdown (new_model_selection feature flag).
// A model can appear in both the Recent group and the main list, but listbox
// values must be globally unique, so Recent entries are prefixed.
export const RECENT_MODEL_VALUE_PREFIX = 'recent:';
// Caps both what localStorage keeps and what the Recent group renders; nothing
// reads the list beyond that group.
export const MAX_RECENT_MODELS = 3;

export const CHAT_THREADS_PER_PAGE = 20;

/**
 * Every action `prompt_composer.vue` can perform on the draft it owns. Lives here rather
 * than beside the `SlashCommand` typedef so the plugins that name an action, the
 * capability that validates it, and the composer that dispatches on it all read the same
 * list without importing each other. A slash command's `action` merely names one of
 * these by reference. Adding an action means implementing it in `prompt_composer.vue`.
 */
export const PROMPT_COMPOSER_ACTIONS = {
  INSERT: 'insert',
  START_GOAL: 'startGoal',
};

// Sticky across sessions, like the agentic mode preference (duo_agentic_mode_on):
// a new thread has no workflow record to read the toggle back from, so the last
// choice is remembered here instead of resetting to off.
export const WEB_SEARCH_PREFERENCE_STORAGE_KEY = 'duo_chat_web_search_on';
