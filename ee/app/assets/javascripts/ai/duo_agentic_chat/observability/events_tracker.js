import { InternalEvents } from '~/tracking';
import {
  TRIGGER_SOURCE_WEB_CHAT,
  TRACKING_EVENT_RECOMMEND_TOOL,
  TRACKING_EVENT_TOOL_SUCCEEDED,
  TRACKING_EVENT_TOOL_FAILED,
  TRACKING_EVENT_APPROVE_TOOL,
  TRACKING_EVENT_DENY_TOOL,
  TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET,
  TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL,
  TRACKING_EVENT_RESIZE_PANEL,
  TRACKING_EVENT_MAXIMIZE_PANEL,
  TRACKING_EVENT_MINIMIZE_PANEL,
  TRACKING_EVENT_USER_CLICKED_RETRY,
  TRACKING_EVENT_RETRY_SUCCEEDED,
  TRACKING_EVENT_RETRY_FAILED,
  TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE,
} from '../constants';

const trackedEventKeys = new Set();

let context = {
  sessionId: undefined,
  flowType: undefined,
  triggerSource: TRIGGER_SOURCE_WEB_CHAT,
  model: undefined,
};

const buildProperties = (toolName) => ({
  tool_name: toolName,
  session_id: context.sessionId,
  flow_type: context.flowType,
  trigger_source: context.triggerSource,
  model: context.model,
});

// Session context shared across the Duo chat panel control events so panel
// interactions can be correlated back to the session they occurred in.
const buildContext = () => ({
  session_id: context.sessionId,
  flow_type: context.flowType,
  trigger_source: context.triggerSource,
  model: context.model,
});

// A tool approval request and the tool message that resolves it arrive under
// one message_id, so the key needs the event and tool to tell them apart.
const trackDedupedEvent = (eventName, { messageId, toolName } = {}) => {
  if (!messageId) return;

  const key = `${eventName}:${messageId}:${toolName}`;
  if (trackedEventKeys.has(key)) return;

  trackedEventKeys.add(key);
  InternalEvents.trackEvent(eventName, buildProperties(toolName));
};

export const EventsTracker = {
  reset() {
    trackedEventKeys.clear();
    context = {
      sessionId: undefined,
      flowType: undefined,
      triggerSource: TRIGGER_SOURCE_WEB_CHAT,
      model: undefined,
    };
  },

  updateContext({ sessionId, flowType, triggerSource, model } = {}) {
    if (sessionId !== undefined) context.sessionId = sessionId;
    if (flowType !== undefined) context.flowType = flowType;
    if (triggerSource !== undefined) context.triggerSource = triggerSource;
    if (model !== undefined) context.model = model;
  },

  trackToolRecommended({ messageId, toolName } = {}) {
    trackDedupedEvent(TRACKING_EVENT_RECOMMEND_TOOL, { messageId, toolName });
  },

  trackToolSucceeded({ messageId, toolName } = {}) {
    trackDedupedEvent(TRACKING_EVENT_TOOL_SUCCEEDED, { messageId, toolName });
  },

  trackToolFailed({ messageId, toolName } = {}) {
    trackDedupedEvent(TRACKING_EVENT_TOOL_FAILED, { messageId, toolName });
  },

  trackApproveTool({ toolName } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_APPROVE_TOOL, buildProperties(toolName));
  },

  trackDenyTool({ toolName } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_DENY_TOOL, buildProperties(toolName));
  },

  trackClickThroughFlowWidget({ toolName } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET, buildProperties(toolName));
  },

  trackClickThroughSessionPill({ workflowId } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL, {
      workflow_id: workflowId,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackPanelResized({ value } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_RESIZE_PANEL, { value, ...buildContext() });
  },

  trackPanelMaximized({ value } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_MAXIMIZE_PANEL, { value, ...buildContext() });
  },

  trackPanelMinimized({ value } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_MINIMIZE_PANEL, { value, ...buildContext() });
  },

  // attemptNumber and index below map to the built-in numeric `value` property,
  // which lands in a dedicated Snowflake column and is queryable without Data team work.
  trackRetryMessage({ attemptNumber } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_USER_CLICKED_RETRY, {
      value: attemptNumber,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackRetrySucceeded({ attemptNumber } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_RETRY_SUCCEEDED, {
      value: attemptNumber,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackRetryFailed({ attemptNumber } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_RETRY_FAILED, {
      value: attemptNumber,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackNavigateRetryAlternative({ index } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE, {
      value: index,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },
};
