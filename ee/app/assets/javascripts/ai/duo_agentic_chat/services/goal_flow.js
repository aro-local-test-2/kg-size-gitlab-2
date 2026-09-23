import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import getConfiguredFlows from 'ee/ai/graphql/get_configured_flows.query.graphql';

// Goal is a configuration of the Developer flow rather than a flow of its own, so the
// identity billing and enablement key off stays `developer/v1` and the mode picks the
// config. Named rather than versioned to keep the client off Flow Registry internals.
export const GOAL_FLOW_REFERENCE = 'developer/v1';
export const GOAL_FLOW_MODE = 'goal';

/**
 * The flow goal mode would run here, or `null` where it cannot run at all -- feature off,
 * no project, flow not configured, or not readable by this user. One answer for all of
 * them, so a caller asks once rather than working through a checklist.
 *
 * No `fetchPolicy`, so it inherits `cache-first`: that is what makes the goal plugin and
 * the composer both asking cost one request.
 *
 * @param {Object} params
 * @param {Object} params.apollo - A vue-apollo wrapper or an Apollo client.
 * @param {string} [params.projectId] - Project GID.
 * @returns {Promise<{ consumerId: number }|null>}
 */
export const getGoalFlow = async ({ apollo, projectId } = {}) => {
  if (!window.gon?.features?.duoChatGoalCommand) return null;

  // Flows are enabled per project.
  if (!projectId) return null;

  const { data } = await apollo.query({
    query: getConfiguredFlows,
    variables: { projectId, foundationalFlowReference: GOAL_FLOW_REFERENCE },
    context: { featureCategory: 'duo_agent_platform' },
  });

  const [consumer] = data?.aiCatalogConfiguredItems?.nodes ?? [];
  if (!consumer) return null;

  // An id rather than a GID, which is what the turn's envelope carries.
  return { consumerId: getIdFromGraphQLId(consumer.id) };
};
