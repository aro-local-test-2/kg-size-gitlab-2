import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { cloneDeep, escape } from 'lodash-es';
import { buildAgentPlanWidgetMock } from 'ee_else_ce_jest/work_items/mock_data';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant, getVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import { buildUpdateResponse } from './fixtures_helper';
import './fixture_variants/get_work_items_full';
import './fixture_variants/get_work_items_slim';
import './fixture_variants/get_work_items_count_only_ee';
import './fixture_variants/has_work_items';
import './fixture_variants/work_item_metadata';
import './fixture_variants/namespace_work_item';
import './fixture_variants/namespace_work_item_features';
import './fixture_variants/work_item_agent_plan';
import './fixture_variants/work_item_notes_by_iid';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/work_items/integration/');

// The AI session widget is a Duo feature, so its fixture is generated alongside
// the other Duo ones, but the drawer is what queries it -- hence the handler
// lives here, where every work item spec already gets it.
const AI_PANEL_FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/ai_duo_panel/integration/',
);

const fixtures = loadFixturesMap(FIXTURES_PATH);
const aiPanelFixtures = loadFixturesMap(AI_PANEL_FIXTURES_PATH);

export const labelsResponse = fixtures.projectLabels;
export const autocompleteUsersResponse = fixtures.workspaceAutocompleteUsersSearch;
export const milestonesResponse = fixtures.projectMilestones;
export const baseUpdateResponse = fixtures.updateWorkItem;
export const canCreateBranchResponse = fixtures.canCreateBranch;
export const workItemsSlimResponse = fixtures.getWorkItemsSlim;

const { id, name } = fixtures.getWorkItemsRest.data.namespace;

const GET_WORK_ITEMS_REST_GQL_MOCK = {
  data: {
    namespace: { id, fullPath: 'gitlab-org/gitlab', name, __typename: 'Namespace' },
  },
};

const currentUserTodosUpdateResponse = ({ useWorkItemFeatures, workItemId, action }) => {
  const emptyTodos = { nodes: [], __typename: 'TodoConnection' };
  const todos =
    action === 'ADD'
      ? {
          nodes: [{ id: 'gid://gitlab/Todo/99', state: 'pending', __typename: 'Todo' }],
          __typename: 'TodoConnection',
        }
      : emptyTodos;

  return {
    data: {
      workItemUpdate: {
        __typename: 'WorkItemUpdatePayload',
        errors: [],
        workItem: {
          __typename: 'WorkItem',
          id: workItemId,
          ...(useWorkItemFeatures
            ? {
                features: {
                  __typename: 'WorkItemFeatures',
                  currentUserTodos: {
                    __typename: 'WorkItemWidgetCurrentUserTodos',
                    // The WorkItemCurrentUserTodos fragment selects `type`; without it the
                    // write is incomplete and the widget reads a cache miss.
                    type: 'CURRENT_USER_TODOS',
                    currentUserTodos: todos,
                  },
                },
              }
            : {
                widgets: [
                  {
                    __typename: 'WorkItemWidgetCurrentUserTodos',
                    type: 'CURRENT_USER_TODOS',
                    currentUserTodos: todos,
                  },
                ],
              }),
        },
      },
    },
  };
};

// A namespace has one licence, so the detail-query variant a spec activates decides the list
// payload as well. It has to: the list rows and the detail query write their widgets onto the
// same cached work item and the cache policies merge them, so a STATUS widget coming from the
// list alone is enough to render the sidebar widget.
function restListResponse() {
  const statusUnlicensed =
    getActiveVariant('namespaceWorkItem') === getVariant('namespaceWorkItem', 'STATUS_UNLICENSED');

  return statusUnlicensed ? fixtures.restWorkItemsListStatusUnlicensed : fixtures.restWorkItemsList;
}

export const GET_WORK_ITEMS_REST_ENDPOINT = {
  name: 'getWorkItemsRest',
  method: 'get',
  path: /\/api\/v4\/namespaces\/.*\/-\/work_items/,
  // A getter, not a value: buildHandlers reads `response` per request, so the variant a test
  // activates is honoured the same way the GraphQL handlers honour it.
  get response() {
    return restListResponse();
  },
  headers: { 'x-next-cursor': '', 'x-prev-cursor': '' },
};

const OPERATION_NAME_OVERRIDES = {
  workItemMetadataEE: fixtures.workItemMetadata,
  EEgetWorkItemStateCounts: fixtures.getWorkItemStateCounts,
  getWorkItemsFullEE: fixtures.getWorkItemsFull,
  getWorkItemsSlimEE: fixtures.getWorkItemsSlim,
  getWorkItemsCountOnlyEE: fixtures.getWorkItemsCountOnly,
  getWorkItemsRestEE: GET_WORK_ITEMS_REST_GQL_MOCK,
};

// The token dropdowns these specs never open, so an empty project branch is enough.
function emptyProjectResponse(field) {
  const { id: projectId } = fixtures.projectLabels.data.namespace;

  return { data: { project: { id: projectId, __typename: 'Project', ...field } } };
}

// No __typename, or Apollo caches this as a real Group or Project and overwrites it.
function emptyCrmResponse(field) {
  const group = { id: 'gid://gitlab/Group/1', [field]: { nodes: [] } };

  return { data: { group, project: { id: 'gid://gitlab/Project/1', group } } };
}

// Creating a work item redirects to it, which re-fetches it by iid. Both sides are
// recorded captures of the same item, so the iid comes off the create fixture rather
// than being hard-coded here.
const CREATED_WORK_ITEM_IID = fixtures.createWorkItem.data.workItemCreate.workItem.iid;

// Each work item type carries its own allowed statuses, but a status update names only an id,
// so one flat list is enough to echo back the status the dropdown offered.
const ALLOWED_STATUSES = fixtures.namespaceWorkItemTypes.data.namespace.workItemTypes.nodes.flatMap(
  ({ widgetDefinitions = [] }) =>
    widgetDefinitions.find(({ type }) => type === 'STATUS')?.allowedStatuses ?? [],
);

function listResponse(kind) {
  // The spec names the fixture it wants with `useListFixture`, so there is nothing to
  // infer from the request variables here.
  const query = kind === 'slim' ? 'getWorkItemsSlimEE' : 'getWorkItemsFullEE';
  const unfiltered = kind === 'slim' ? fixtures.getWorkItemsSlim : fixtures.getWorkItemsFull;

  return { data: (getActiveVariant(query) ?? unfiltered).data };
}

const FIXTURE_RESPONSES = {
  ...fixtures,
  ...OPERATION_NAME_OVERRIDES,
};

const STATIC_OPERATION_HANDLERS = Object.fromEntries(
  Object.entries(FIXTURE_RESPONSES).map(([operationName, fixture]) => [
    operationName,
    () => ({ data: (getActiveVariant(operationName) ?? fixture).data }),
  ]),
);

// The award-emoji body toggle resolves the cache from the server-returned
// `toggledOn`, so the handler tracks current-user reactions and flips per call.
// Reset between tests via resetAwardState().
let currentUserReactions = new Set();

export const resetAwardState = () => {
  currentUserReactions = new Set();
};

const awardEmojiMutationHandlers = {
  updateWorkItemAwardEmojiWidget: ({ variables }) => {
    const { awardableId, name: emojiName } = variables.input;
    const key = `${awardableId}:${emojiName}`;
    const toggledOn = !currentUserReactions.has(key);

    if (toggledOn) {
      currentUserReactions.add(key);
    } else {
      currentUserReactions.delete(key);
    }

    return {
      data: {
        awardEmojiToggle: { __typename: 'AwardEmojiTogglePayload', errors: [], toggledOn },
      },
    };
  },
  // Note reactions decide add-vs-remove and update the cache optimistically on the
  // client, so the acknowledgements are static.
  workItemNoteAddAwardEmoji: () => ({
    data: { awardEmojiAdd: { __typename: 'AwardEmojiAddPayload', errors: [] } },
  }),
  workItemNoteRemoveAwardEmoji: () => ({
    data: { awardEmojiRemove: { __typename: 'AwardEmojiRemovePayload', errors: [] } },
  }),
};

const DYNAMIC_OPERATION_HANDLERS = {
  ...awardEmojiMutationHandlers,
  createWorkItemNote: () => fixtures.createWorkItemNote,

  // Echoes the requested work item. Serving the fixture's own id verbatim would
  // write this response's `features` onto whichever work item happens to share
  // that id, and these suites read `features` back out of the Apollo cache.
  getDuoAgentSessionsOnWorkItem: ({ variables }) => {
    const fixture = cloneDeep(aiPanelFixtures.getDuoAgentSessionsOnWorkItem);
    fixture.data.workItem.id = variables?.id ?? fixture.data.workItem.id;

    return fixture;
  },

  // The agent-plan drawer mounts ViewSessionButton, which probes duoChatAvailable.
  // These suites never assert the button, so a false keeps it hidden (v-if).
  duoChatAvailable: () => ({
    data: {
      currentUser: {
        __typename: 'CurrentUser',
        id: 'gid://gitlab/User/1',
        duoChatAvailable: false,
      },
    },
  }),

  // The iteration dropdown re-runs this query with the typed term. Only one search is
  // exercised ('plan'), so any non-empty term serves the filtered fixture; the empty
  // term is what the dropdown sends when it first opens.
  issueIterationsAliasedProject: ({ variables }) => ({
    data: variables.title ? fixtures.projectIterationsSearch.data : fixtures.projectIterations.data,
  }),

  usersAutocomplete: () => emptyProjectResponse({ autocompleteUsers: [] }),
  searchMilestones: () =>
    emptyProjectResponse({ milestones: { nodes: [], __typename: 'MilestoneConnection' } }),
  searchCrmOrganizations: () => emptyCrmResponse('organizations'),
  searchCrmContacts: () => emptyCrmResponse('contacts'),
  issueSuggestion: () =>
    emptyProjectResponse({ issues: { edges: [], __typename: 'IssueConnection' } }),

  getWorkItemsSlim: () => listResponse('slim'),
  getWorkItemsSlimEE: () => listResponse('slim'),
  getWorkItemsFull: () => listResponse('full'),
  getWorkItemsFullEE: () => listResponse('full'),

  namespaceWorkItem: ({ variables }) => {
    if (variables.useWorkItemFeatures) {
      const featuresVariant = getActiveVariant('namespaceWorkItemFeatures');
      return { data: (featuresVariant ?? fixtures.namespaceWorkItemFeatures).data };
    }

    if (variables.iid === CREATED_WORK_ITEM_IID) {
      return { data: fixtures.namespaceWorkItemCreated.data };
    }

    const activeVariant = getActiveVariant('namespaceWorkItem');
    return { data: (activeVariant ?? fixtures.namespaceWorkItem).data };
  },

  workItemCrmContacts: ({ variables }) =>
    variables.useWorkItemFeatures
      ? { data: fixtures.workItemCrmContactsFeatures.data }
      : { data: fixtures.workItemCrmContacts.data },

  workItemCurrentUserTodos: ({ variables }) =>
    variables.useWorkItemFeatures
      ? { data: fixtures.workItemCurrentUserTodosFeatures.data }
      : { data: fixtures.workItemCurrentUserTodos.data },

  workItemLinkedResources: ({ variables }) =>
    variables.useWorkItemFeatures
      ? { data: fixtures.workItemLinkedResourcesFeatures.data }
      : { data: fixtures.workItemLinkedResources.data },

  workItemLinkedItems: ({ variables }) =>
    variables.useWorkItemFeatures
      ? { data: fixtures.workItemLinkedItemsFeatures.data }
      : { data: fixtures.workItemLinkedItems.data },

  addLinkedItems: ({ variables }) =>
    variables.useWorkItemFeatures
      ? { data: fixtures.addLinkedItemsFeatures.data }
      : { data: fixtures.addLinkedItems.data },

  removeLinkedItems: () => ({ data: fixtures.removeLinkedItems.data }),

  // Kept as a minimal, deliberately un-normalized stub (no __typename) rather than
  // a generated fixture: a fully-typed empty response writes a `Namespace` entry
  // into the Apollo cache that clobbers the list's own cache updates and breaks
  // the drawer title-update propagation.
  savedViews: () => ({
    data: {
      namespace: {
        id: 'gid://gitlab/Group/1',
        savedViews: { nodes: [] },
      },
    },
  }),

  workItemUpdateCurrentUserTodos: ({ variables }) =>
    currentUserTodosUpdateResponse({
      useWorkItemFeatures: variables.useWorkItemFeatures,
      workItemId: variables.input.id,
      action: variables.input.currentUserTodosWidget?.action,
    }),

  workItemSubscribe: ({ variables }) => ({
    data: {
      workItemSubscribe: {
        errors: [],
        workItem: {
          __typename: 'WorkItem',
          id: variables.input.id,
          widgets: [
            {
              type: 'NOTIFICATIONS',
              subscribed: variables.input.subscribed,
              __typename: 'WorkItemWidgetNotifications',
            },
          ],
        },
      },
    },
  }),

  updateWorkItemListUserPreference: ({ variables }) => ({
    data: {
      workItemUserPreferenceUpdate: {
        errors: [],
        userPreferences: {
          displaySettings: variables.displaySettings,
          sort: variables.sort || null,
        },
      },
    },
  }),

  updateWorkItemsDisplaySettings: ({ variables }) => ({
    data: {
      userPreferencesUpdate: {
        userPreferences: {
          workItemsDisplaySettings: variables.input?.workItemsDisplaySettings || {},
        },
      },
    },
  }),

  workItemUpdate: ({ variables }) =>
    buildUpdateResponse({
      baseResponse: fixtures.updateWorkItem,
      labelsFixture: fixtures.updateWorkItemLabels,
      assigneesFixture: fixtures.updateWorkItemAssignees,
      milestoneFixture: fixtures.updateWorkItemMilestone,
      iterationNodes: fixtures.projectIterations.data.namespace.attributes.nodes,
      statusNodes: ALLOWED_STATUSES,
      input: variables.input,
      featuresFixture: fixtures.namespaceWorkItemFeatures,
      useWorkItemFeatures: variables.useWorkItemFeatures,
    }),

  workItemAgentPlan: ({ variables }) => {
    const activeVariant = getActiveVariant('workItemAgentPlan');
    const content = activeVariant?.data?.content ?? '';
    const contentHtml = activeVariant?.data?.contentHtml ?? '';
    const aiPlanningEnabled = activeVariant?.data?.aiPlanningEnabled ?? true;
    const readinessScore = activeVariant?.data?.readinessScore ?? null;
    const agentPlan = buildAgentPlanWidgetMock({
      content,
      contentHtml,
      aiPlanningEnabled,
      readinessScore,
    });

    return {
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: variables.id,
          iid: '1',
          ...(variables.useWorkItemFeatures
            ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
            : { widgets: [agentPlan] }),
        },
      },
    };
  },

  updateWorkItemAgentPlan: ({ variables }) => {
    const { content } = variables.input.agentPlanWidget;
    const agentPlan = buildAgentPlanWidgetMock({
      ...getActiveVariant('workItemAgentPlan')?.data,
      content,
      contentHtml: content ? `<p>${escape(content)}</p>` : '',
    });

    return {
      data: {
        workItemUpdate: {
          __typename: 'WorkItemUpdatePayload',
          errors: [],
          workItem: {
            __typename: 'WorkItem',
            id: variables.input.id,
            iid: '1',
            ...(variables.useWorkItemFeatures
              ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
              : { widgets: [agentPlan] }),
          },
        },
      },
    };
  },

  workItemEnableAiPlanning: ({ variables }) => {
    const content = getActiveVariant('workItemAgentPlan')?.data?.content ?? '';
    const agentPlan = buildAgentPlanWidgetMock({ content, aiPlanningEnabled: true });

    return {
      data: {
        workItemEnableAiPlanning: {
          __typename: 'WorkItemEnableAiPlanningPayload',
          workItem: {
            __typename: 'WorkItem',
            id: variables.input.id,
            ...(variables.useWorkItemFeatures
              ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
              : { widgets: [agentPlan] }),
          },
          errors: [],
        },
      },
    };
  },
};

const OPERATION_HANDLERS = {
  ...STATIC_OPERATION_HANDLERS,
  ...DYNAMIC_OPERATION_HANDLERS,
};

export function handleWorkItemOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  const payload = handler({ operationName, variables });

  return HttpResponse.json(payload);
}

export const workItemRestEndpoints = [
  { method: 'get', path: /issues\/\d+\/can_create_branch/, response: fixtures.canCreateBranch },
  { method: 'get', path: /\/-\/autocomplete\/award_emojis/, response: [] },
  { method: 'get', path: /\/-\/releases\.json/, response: [] },
  GET_WORK_ITEMS_REST_ENDPOINT,
];
