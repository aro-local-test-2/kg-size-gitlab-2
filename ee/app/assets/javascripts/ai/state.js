import { observable } from '~/lib/utils/observable';

export const CHAT_MODES = {
  CLASSIC: 'classic',
  AGENTIC: 'agentic',
};

// Kept out of `~/super_sidebar/state`: that module is on INFECTION_BLOCKLIST, so it
// is never duplicated and `observable` would build a mirror for one Vue version only.
export const duoChatGlobalState = observable('duo_chat_global_state', {
  commands: [],
  chatMode: CHAT_MODES.CLASSIC, // CHAT_MODES.CLASSIC or CHAT_MODES.AGENTIC - single source of truth for chat mode
  focusChatInput: false, // Set to true to force the chat input to focus when the chat is expanded
  lastRoutePerTab: {}, // Tracks the last visited route for each tab (e.g., { sessions: '/agent-sessions/123' })
  aiPanelDragWidth: null, // number (px) when user has dragged; null = use CSS clamp default. Session-only.
});
