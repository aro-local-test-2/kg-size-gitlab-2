// MSW handlers for every Duo chat GraphQL operation: the agentic panel, the
// classic panel, and the workflow queries both of them share.
//
// Every response is a Rails-generated fixture, served as recorded, so a schema
// change breaks these specs instead of silently diverging from the API. The handlers
// keep no state: a spec picks the shape it needs with `setQueryVariant`.

import { join } from 'node:path';
import { graphql, HttpResponse } from 'msw';
import { cloneDeep } from 'lodash-es';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import { captureRequest } from 'ee_jest/integration/core/operation_helpers';
import { server } from '../../server';
import aiChatAvailableModelsVariants from './fixture_variants/get_ai_chat_available_models';
import aiMessagesWithThreadVariants from './fixture_variants/get_ai_messages_with_thread';
import duoDefaultNamespaceCandidatesVariants from './fixture_variants/get_duo_default_namespace_candidates';
import userWorkflowsVariants from './fixture_variants/get_user_workflows';
import workflowLatestCheckpointVariants from './fixture_variants/get_workflow_latest_checkpoint';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/ai_duo_panel/integration/');

const REGENERATE_HINT =
  'Regenerate with: bundle exec rspec ee/spec/frontend/fixtures/ai_duo_panel_integration.rb';

const fixtures = loadFixturesMap(FIXTURES_PATH);

/**
 * Reads a generated fixture, resolved on use rather than at import so a spec that
 * never exercises an operation is not broken by an unrelated missing fixture. A
 * stale `tmp/` is common, so say what to do about it instead of failing with
 * `Cannot read properties of undefined`.
 */
const fixtureFor = (operationName) => {
  const fixture = fixtures[operationName];

  if (!fixture) {
    throw new Error(`Missing MSW fixture for "${operationName}". ${REGENERATE_HINT}`);
  }

  return fixture;
};

// -----------------------------------------------------------------------------
// Fixture accessors: the mock data specs assert against.
//
// One export per recorded fixture, named for the fixture file, which is itself
// named for the GraphQL operation it records -- `getUserWorkflowsWithArchived` is
// `get_user_workflows_with_archived.query.graphql.json`, the `WITH_ARCHIVED`
// variant of `getUserWorkflows`. A spec imports these rather than the JSON, so a
// call site names the fixture its expected value came from, and the drilling into
// a response shape lives here instead of in every spec that needs it.
//
// Functions rather than constants, so a stale fixture fails the example that reads
// it, with the name of the fixture, rather than the whole spec file at import time.
// -----------------------------------------------------------------------------

/**
 * The counterpart to `fixtureFor` for a fixture that loaded but holds nothing
 * useful, so an empty response reads as the same actionable message rather than
 * as `Cannot read properties of undefined` further down the call stack.
 */
const orFail = (value, description) => {
  if (!value?.length) {
    throw new Error(`MSW fixture has no ${description}. ${REGENERATE_HINT}`);
  }

  return value;
};

const nodesOf = (operationName, field) =>
  orFail(fixtureFor(operationName).data[field]?.nodes, `${field} nodes in ${operationName}`);

const edgeNodesOf = (operationName, field) =>
  orFail(fixtureFor(operationName).data[field]?.edges, `${field} edges in ${operationName}`).map(
    ({ node }) => node,
  );

/**
 * The shared shape of the `getWorkflowLatestCheckpoint` captures: one workflow
 * carrying the conversation recorded for it.
 */
const conversationIn = (operationName) => {
  const workflow = () => nodesOf(operationName, 'duoWorkflowWorkflows')[0];

  return {
    workflow,
    messages: () =>
      orFail(workflow().latestCheckpoint?.duoMessages, `messages in ${operationName}`),
  };
};

export const getUserWorkflows = {
  threads: () => edgeNodesOf('getUserWorkflows', 'duoWorkflowWorkflows'),
};

// Named for the two threads it adds. The recorded list also carries the default
// workflow every fixture example shares, so it holds three.
export const getUserWorkflowsTwoThreads = {
  threads: () => edgeNodesOf('getUserWorkflowsTwoThreads', 'duoWorkflowWorkflows'),
};

// `archived` is derived from the workflow's age rather than stored, so the fixture
// spec ages one workflow past the retention window to produce this pair.
const archivedListThreadWhere = (predicate, description) =>
  orFail(
    edgeNodesOf('getUserWorkflowsWithArchived', 'duoWorkflowWorkflows').filter(predicate),
    `${description} thread in getUserWorkflowsWithArchived`,
  )[0];

export const getUserWorkflowsWithArchived = {
  archivedThread: () => archivedListThreadWhere(({ archived }) => archived, 'archived'),
  activeThread: () => archivedListThreadWhere(({ archived }) => !archived, 'active'),
};

export const getWorkflowLatestCheckpoint = conversationIn('getWorkflowLatestCheckpoint');
export const getWorkflowLatestCheckpointFirstThread = conversationIn(
  'getWorkflowLatestCheckpointFirstThread',
);
export const getWorkflowLatestCheckpointSecondThread = conversationIn(
  'getWorkflowLatestCheckpointSecondThread',
);
export const getWorkflowLatestCheckpointWithContext = conversationIn(
  'getWorkflowLatestCheckpointWithContext',
);

export const getAiConversationThreads = {
  threads: () => nodesOf('getAiConversationThreads', 'aiConversationThreads'),
};

export const getAiMessagesWithThread = {
  messages: () => nodesOf('getAiMessagesWithThread', 'aiMessages'),
};

export const getConfiguredAgents = {
  agents: () => nodesOf('getConfiguredAgents', 'aiCatalogConfiguredItems'),
};

export const getFoundationalChatAgents = {
  agents: () => nodesOf('getFoundationalChatAgents', 'aiFoundationalChatAgents'),
};

export const getDuoDefaultNamespaceCandidates = {
  namespaces: () => nodesOf('getDuoDefaultNamespaceCandidates', 'duoDefaultNamespaceCandidates'),
};

export const getAiChatAvailableModelsUnpinned = {
  models: () => fixtureFor('getAiChatAvailableModelsUnpinned').data.aiChatAvailableModels,
};

export const getRuleContent = {
  project: () => fixtureFor('getRuleContent').data.project,
};

// Two aliases of `duoWorkflowWorkflows` in one document, so the field name is the
// alias rather than the query field.
export const getUserAgentFlowInbox = {
  needsDecisionThreads: () => edgeNodesOf('getUserAgentFlowInbox', 'needsDecision'),
  allThreads: () => edgeNodesOf('getUserAgentFlowInbox', 'all'),
};

// Query constants for `setQueryVariant`. The accessor objects above share the
// operation names, so the variant constants are re-exported under `*Variants`.
export {
  aiChatAvailableModelsVariants,
  aiMessagesWithThreadVariants,
  duoDefaultNamespaceCandidatesVariants,
  userWorkflowsVariants,
  workflowLatestCheckpointVariants,
};

// -----------------------------------------------------------------------------
// What the panel is served: the generated fixture for the operation, or the
// active variant of it. `getActiveVariant` returns null while BASE is active, so
// the default path is the recorded response, cloned so that a caller reading the
// fixture map cannot be handed the same object the handler served.
// -----------------------------------------------------------------------------
const responseFor = (operationName) =>
  getActiveVariant(operationName) ?? cloneDeep(fixtures[operationName]);

/**
 * Installs the Duo AI panel GraphQL handlers for the current test.
 *
 * Opt-in rather than part of the global chain in `integration/handlers.js`,
 * so a spec that does not touch the panel neither pays for these fixtures nor
 * fails when one of them is stale. It also keeps this module off the chain, and
 * so out of an import cycle with `server.js`.
 *
 * Every generated fixture is served as-is. To serve a different recorded shape,
 * declare it in `fixture_variants/` and pick it per test with `setQueryVariant`.
 *
 * Nothing here models the backend writing and reading state back. A workflow the
 * client creates does not appear in the thread list, because whether it does is the
 * backend's business: assert the create mutation's variables, and assert the list
 * renders what the server returned.
 *
 * Operations this does not own return `undefined`, which MSW treats as "not
 * handled", so work-item and AI catalog requests still fall through to the
 * global chain. The suite-wide `server.resetHandlers()` in
 * `integration/test_setup.js` removes these again after each test.
 */
export const installDuoAIPanelHandlers = () => {
  server.use(
    graphql.operation(({ operationName, variables, request }) => {
      if (!Object.hasOwn(fixtures, operationName)) {
        return undefined;
      }

      // Runtime handlers are prepended, so they answer before the global chain
      // records the call. Capture here too, or these operations stay invisible
      // to `expectGraphQLCalls` and `lastRequestVariables`.
      captureRequest(operationName, request, variables);

      return HttpResponse.json(responseFor(operationName));
    }),
  );
};
