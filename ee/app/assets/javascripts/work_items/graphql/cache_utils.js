import { WIDGET_TYPE_AGENT_PLAN } from 'ee/work_items/constants';
import workItemAgentPlanQuery from './work_item_agent_plan.query.graphql';

export const buildAgentPlanWidget = ({
  content,
  contentHtml,
  aiPlanningEnabled = true,
  readinessScore = null,
  generationStatus = null,
}) => ({
  type: WIDGET_TYPE_AGENT_PLAN,
  content,
  contentHtml,
  aiPlanningEnabled,
  readinessScore,
  generationStatus,
  __typename: 'WorkItemWidgetAgentPlan',
});

export const writeAgentPlanToCache = ({
  cache,
  workItemId,
  workItemIid,
  content,
  contentHtml,
  aiPlanningEnabled,
  readinessScore,
  generationStatus,
  useWorkItemFeatures,
  includeReadinessScore = false,
}) => {
  const agentPlan = buildAgentPlanWidget({
    content,
    contentHtml,
    aiPlanningEnabled,
    readinessScore,
    generationStatus,
  });

  cache.writeQuery({
    query: workItemAgentPlanQuery,
    variables: { id: workItemId, useWorkItemFeatures, includeReadinessScore },
    data: {
      workItem: {
        __typename: 'WorkItem',
        id: workItemId,
        iid: workItemIid,
        ...(useWorkItemFeatures
          ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
          : { widgets: [agentPlan] }),
      },
    },
  });
};
