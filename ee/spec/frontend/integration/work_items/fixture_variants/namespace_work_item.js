import { cloneDeep } from 'lodash-es';
import namespaceWorkItemBase from 'test_fixtures/graphql/work_items/integration/namespace_work_item.query.graphql.json';
import namespaceWorkItemStatusUnlicensed from 'test_fixtures/graphql/work_items/integration/namespace_work_item_status_unlicensed.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

// The agent plan widget in the main query is a presence + aiPlanningEnabled marker;
// the plan content is fetched by the standalone workItemAgentPlan query (see its handler).
// Add the marker to the base work item so the selected work item and the standalone
// query target the same id. WITH_AGENT_PLAN and WITH_EMPTY_AGENT_PLAN differ only in the
// standalone query's content, driven via the workItemAgentPlan variant.
const withAgentPlanWidget = (fixture, { aiPlanningEnabled = true } = {}) => {
  const clone = cloneDeep(fixture);
  clone.data.namespace.workItem.widgets.push({
    __typename: 'WorkItemWidgetAgentPlan',
    type: 'AGENT_PLAN',
    aiPlanningEnabled,
  });
  return clone;
};

const namespaceWorkItemAgentPlan = withAgentPlanWidget(namespaceWorkItemBase);
const namespaceWorkItemAgentPlanAiDisabled = withAgentPlanWidget(namespaceWorkItemBase, {
  aiPlanningEnabled: false,
});

export default defineFixtureVariants({
  query: 'namespaceWorkItem',
  variants: {
    // BASE carries no agent plan widget, so it doubles as the "no widget" case.
    BASE: namespaceWorkItemBase,
    WITH_AGENT_PLAN: namespaceWorkItemAgentPlan,
    WITH_EMPTY_AGENT_PLAN: namespaceWorkItemAgentPlan,
    WITH_EMPTY_AGENT_PLAN_NO_UPDATE: setFixtureData(
      namespaceWorkItemAgentPlan,
      'updateWorkItem',
      false,
    ),
    WITH_AGENT_PLAN_AI_DISABLED: namespaceWorkItemAgentPlanAiDisabled,
    WITH_AGENT_PLAN_AI_DISABLED_NO_UPDATE: setFixtureData(
      namespaceWorkItemAgentPlanAiDisabled,
      'updateWorkItem',
      false,
    ),
    ARCHIVED: setFixtureData(namespaceWorkItemBase, 'archived', true),
    LOCKED: setFixtureData(namespaceWorkItemBase, 'discussionLocked', true),
    // Captured from a namespace without the status licence, so the payload is missing the
    // STATUS widget the same way a real unlicensed instance's would be.
    STATUS_UNLICENSED: namespaceWorkItemStatusUnlicensed,
  },
});
