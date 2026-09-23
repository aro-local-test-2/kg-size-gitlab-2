import { GlAlert, GlBadge, GlLoadingIcon } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { createMockSubscription } from 'mock-apollo-client';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import ApplicationFlow from 'ee/cd/components/application_details/flow/application_flow.vue';
import FlowFooter from 'ee/cd/components/application_details/flow/flow_footer.vue';
import StepSidePanel from 'ee/cd/components/application_details/flow/step_side_panel.vue';
import FlowStage from 'ee/cd/components/application_details/flow/flow_stage.vue';
import FlowStep from 'ee/cd/components/application_details/flow/flow_step.vue';
import cdApplicationDeploymentFlowQuery from 'ee/cd/graphql/applications/flow/cd_application_deployment_flow.query.graphql';
import cdRolloutApprovalGatesQuery from 'ee/cd/graphql/applications/flow/cd_rollout_approval_gates.query.graphql';
import cdRolloutFlowQuery from 'ee/cd/graphql/applications/flow/cd_rollout_flow.query.graphql';
import cdRolloutStepUpdatedSubscription from 'ee/cd/graphql/applications/flow/cd_rollout_step_updated.subscription.graphql';
import cdRolloutGateUpdatedSubscription from 'ee/cd/graphql/applications/flow/cd_rollout_gate_updated.subscription.graphql';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import {
  buildRolloutApprovalGateResponse,
  mockCdDefinitionSteps,
} from 'ee/cd/../../../../spec/frontend/cd/components/mock_data';

Vue.use(VueApollo);

const APPLICATION_ID = 'gid://gitlab/Cd::Application/7';
const ORGANIZATION_ID = 'gid://gitlab/Organizations::Organization/1';
const flowEditorRoute = { name: 'flow_editor_route', params: { id: '7' } };

const flowDef = ({ version = 1, steps = [] } = {}) => ({
  __typename: 'CdApplicationFlowDefinition',
  id: `gid://gitlab/Cd::ApplicationFlowDefinition/${version}`,
  version,
  definitionSteps: steps,
});

const rolloutNode = ({
  id = 5,
  iid = 486,
  state = 'IN_PROGRESS',
  versionSetId = 5,
  releaseName = 'v2.4.1',
  author = 'data-platform',
  flow = flowDef(),
  steps = [],
} = {}) => ({
  __typename: 'CdRollout',
  id: `gid://gitlab/Cd::Rollout/${id}`,
  iid,
  state,
  versionSet: versionSetId
    ? {
        __typename: 'CdVersionSet',
        id: `gid://gitlab/Cd::VersionSet/${versionSetId}`,
        name: releaseName,
        author: author
          ? { __typename: 'UserCore', id: 'gid://gitlab/User/3', username: author }
          : null,
      }
    : null,
  applicationFlowDefinition: flow,
  rolloutSteps: steps,
});

let stepId = 0;

const rolloutStep = ({
  type,
  name = null,
  state = 'SUCCESS',
  error = null,
  environment = null,
  params = null,
  steps = [],
}) => {
  stepId += 1;

  return {
    __typename: 'CdRolloutStep',
    id: `gid://gitlab/Cd::RolloutStep/${stepId}`,
    path: String(stepId),
    stepType: type,
    name,
    params,
    state,
    error,
    environment: environment
      ? {
          __typename: 'CdEnvironment',
          id: `gid://gitlab/Cd::Environment/${environment}`,
          name: environment,
        }
      : null,
    steps,
  };
};

const stageStep = (name, state, steps) =>
  rolloutStep({ type: 'com.gitlab.cd.steps.stage', name, state, steps });

const deployStep = (environment, state) =>
  rolloutStep({
    type: 'com.gitlab.cd.argo.canary.deploy',
    environment,
    state,
    params: { services: [{ name: 'api' }, { name: 'worker' }] },
  });

const waitStep = (state) => rolloutStep({ type: 'com.gitlab.cd.steps.wait', state });

const approvalStep = (state) => rolloutStep({ type: 'com.gitlab.cd.steps.approval', state });

const flowSteps = () => [
  stageStep('dev', 'SUCCESS', [deployStep('dev-eu', 'SUCCESS')]),
  stageStep('production', 'RUNNING', [
    approvalStep('APPROVED'),
    deployStep('prod-eu', 'SUCCESS'),
    deployStep('prod-us', 'PENDING'),
    waitStep('PENDING'),
  ]),
  waitStep('PENDING'),
];

const connection = (node) => ({ nodes: node ? [node] : [] });

const appFlowResponse = ({
  active = null,
  latestFinished = null,
  applicationFlow = null,
  canResolveGate = false,
} = {}) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: ORGANIZATION_ID,
      cdApplication: {
        __typename: 'CdApplication',
        id: APPLICATION_ID,
        name: 'payments-platform',
        userPermissions: {
          resolveCdRolloutGate: canResolveGate,
        },
        activeRollout: connection(active),
        latestFinishedRollout: connection(latestFinished),
        applicationFlowDefinitions: connection(applicationFlow),
      },
    },
  },
});

const rolloutFlowResponse = (rollout) => ({
  data: { organization: { __typename: 'Organization', id: ORGANIZATION_ID, cdRollout: rollout } },
});

describe('ApplicationFlow', () => {
  let wrapper;
  let appHandler;
  let rolloutHandler;
  let rolloutStepSubscriptionHandler;
  let gateHandler;

  const createComponent = ({
    appResponse = appFlowResponse(),
    rolloutResponse = rolloutFlowResponse(null),
    selectedDeploymentId = null,
    routedPanelOpen = false,
    appError = false,
    rolloutError = false,
    mountFn = shallowMountExtended,
    subscriptionHandler = jest.fn(() => createMockSubscription()),
  } = {}) => {
    appHandler = appError
      ? jest.fn().mockRejectedValue(new Error('boom'))
      : jest.fn().mockResolvedValue(appResponse);
    rolloutHandler = rolloutError
      ? jest.fn().mockRejectedValue(new Error('boom'))
      : jest.fn().mockResolvedValue(rolloutResponse);
    rolloutStepSubscriptionHandler = subscriptionHandler;

    gateHandler = jest.fn(({ id }) =>
      Promise.resolve(buildRolloutApprovalGateResponse({ rolloutId: getIdFromGraphQLId(id) })),
    );

    wrapper = mountFn(ApplicationFlow, {
      apolloProvider: createMockApollo([
        [cdApplicationDeploymentFlowQuery, appHandler],
        [cdRolloutFlowQuery, rolloutHandler],
        [cdRolloutStepUpdatedSubscription, rolloutStepSubscriptionHandler],
        [cdRolloutApprovalGatesQuery, gateHandler],
        [cdRolloutGateUpdatedSubscription, () => createMockSubscription()],
      ]),
      propsData: { applicationId: APPLICATION_ID, selectedDeploymentId, routedPanelOpen },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findFlowCanvas = () => wrapper.findByTestId('flow-canvas');
  const findEditButton = () => wrapper.findComponentByTestId('edit-flow-button');
  const findToggleAllButton = () => wrapper.findComponentByTestId('toggle-all-stages-button');
  const findCreateButton = () => wrapper.findComponentByTestId('create-flow-button');
  const lastRolloutSelected = () => wrapper.emitted('rollout-selected').at(-1)[0];
  const findFooter = () => wrapper.findComponent(FlowFooter);
  const findStepPanel = () => wrapper.findComponent(StepSidePanel);
  const findStages = () => wrapper.findAllComponents(FlowStage);
  const findSteps = () => wrapper.findAllComponents(FlowStep);
  const findStepBoxes = () => wrapper.findAllByTestId('flow-step-box');
  const findConnectorPaths = () => wrapper.findAllByTestId('flow-connector');
  const findStageHeaders = () => wrapper.findAllByTestId('stage-header');
  const findRolloutMeta = () => wrapper.findByTestId('rollout-meta');
  const nodeIdsInMarkup = () =>
    findFlowCanvas()
      .findAll('[data-flow-node]')
      .wrappers.map((node) => node.attributes('data-flow-node'));
  const findExpandedStage = () => findStages().wrappers.find((stage) => stage.props('expanded'));
  const expandedStepNodeIds = () =>
    findExpandedStage()
      .findAll('[data-testid="stage-body"] [data-flow-node]')
      .wrappers.map((node) => node.attributes('data-flow-node'));

  describe('while loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });
  });

  describe('errors', () => {
    describe('when the application query fails and nothing is selected', () => {
      beforeEach(async () => {
        createComponent({ appError: true });
        await waitForPromises();
      });

      it('shows the error', () => {
        expect(findAlert().props('variant')).toBe('danger');
        expect(findAlert().text()).toContain('Failed to load the application flow');
      });
    });

    describe('when a selected deployment loads while the application query fails', () => {
      beforeEach(async () => {
        createComponent({
          appError: true,
          rolloutResponse: rolloutFlowResponse(
            rolloutNode({ id: 9, flow: flowDef({ version: 9 }) }),
          ),
          selectedDeploymentId: 'gid://gitlab/Cd::Rollout/9',
        });
        await waitForPromises();
      });

      it('shows the selected flow without an error', () => {
        expect(findAlert().exists()).toBe(false);
        expect(findBadge().text()).toBe('Version 9');
      });
    });

    describe('when the selected deployment fails to load', () => {
      beforeEach(async () => {
        createComponent({ rolloutError: true, selectedDeploymentId: 'gid://gitlab/Cd::Rollout/9' });
        await waitForPromises();
      });

      it('shows the error', () => {
        expect(findAlert().props('variant')).toBe('danger');
      });
    });
  });

  describe('with no rollout and no application flow', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the empty state message', () => {
      expect(wrapper.text()).toContain('No flow is defined for this application yet.');
    });

    it('renders the create button linking to the flow editor', () => {
      expect(findCreateButton().props('to')).toEqual(flowEditorRoute);
    });

    it('does not render the canvas or the version badge', () => {
      expect(findFlowCanvas().exists()).toBe(false);
      expect(findBadge().exists()).toBe(false);
    });
  });

  describe.each([
    ['null', null],
    ['empty', []],
  ])('when the definition steps are %s', (_, steps) => {
    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({ applicationFlow: flowDef({ version: 2, steps }) }),
      });
      await waitForPromises();
    });

    it('renders a trigger and no steps', () => {
      expect(findSteps()).toHaveLength(1);
      expect(findStages()).toHaveLength(0);
    });

    it('keeps the edit button available', () => {
      expect(findEditButton().props('to')).toEqual(flowEditorRoute);
    });
  });

  describe('when there is no rollout', () => {
    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({
          applicationFlow: flowDef({ version: 2, steps: mockCdDefinitionSteps() }),
        }),
      });
      await waitForPromises();
    });

    it('renders a stage per definition stage', () => {
      expect(findStages()).toHaveLength(2);
    });

    it('renders a trigger', () => {
      expect(findSteps().at(0).props('title')).toBe('Trigger');
    });

    it('marks every step inactive', () => {
      const states = [...findSteps().wrappers, ...findStages().wrappers].map((item) =>
        item.props('state'),
      );

      expect(states).toEqual(['INACTIVE', 'INACTIVE', 'INACTIVE', 'INACTIVE']);
    });

    it('does not render the footer', () => {
      expect(findFooter().exists()).toBe(false);
    });

    describe('when a stage is toggled', () => {
      beforeEach(async () => {
        findStages().at(0).vm.$emit('toggle');
        await nextTick();
      });

      it('expands only that stage', () => {
        expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([
          true,
          false,
        ]);
      });
    });

    describe('when expand all is clicked', () => {
      beforeEach(async () => {
        findToggleAllButton().vm.$emit('click');
        await nextTick();
      });

      it('expands every stage', () => {
        expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([true, true]);
      });
    });
  });

  describe('flow source fallback', () => {
    it.each`
      scenario             | appResponse                                                                            | version
      ${'active'}          | ${appFlowResponse({ active: rolloutNode({ flow: flowDef({ version: 5 }) }) })}         | ${5}
      ${'latest finished'} | ${appFlowResponse({ latestFinished: rolloutNode({ flow: flowDef({ version: 4 }) }) })} | ${4}
    `('shows the $scenario rollout flow', async ({ appResponse, version }) => {
      createComponent({ appResponse });
      await waitForPromises();

      expect(findBadge().text()).toBe(`Version ${version}`);
    });

    it('prefers the active rollout over the latest finished rollout', async () => {
      createComponent({
        appResponse: appFlowResponse({
          active: rolloutNode({ id: 5, flow: flowDef({ version: 5 }) }),
          latestFinished: rolloutNode({
            id: 4,
            flow: flowDef({ version: 4 }),
          }),
        }),
      });
      await waitForPromises();

      expect(findBadge().text()).toBe('Version 5');
    });

    describe('when no rollout has a flow definition', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({
            applicationFlow: flowDef({ version: 2, steps: mockCdDefinitionSteps() }),
          }),
        });
        await waitForPromises();
      });

      it('falls back to the application flow', () => {
        expect(findBadge().text()).toBe('Version 2');
        expect(findFlowCanvas().exists()).toBe(true);
      });

      it('renders the edit button linking to the flow editor', () => {
        expect(findEditButton().props('to')).toEqual(flowEditorRoute);
      });
    });
  });

  describe('when a deployment is explicitly selected', () => {
    const selectedId = 'gid://gitlab/Cd::Rollout/9';

    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({
          active: rolloutNode({ id: 5, flow: flowDef({ version: 5 }) }),
        }),
        rolloutResponse: rolloutFlowResponse(
          rolloutNode({
            id: 9,
            versionSetId: 9,
            flow: flowDef({ version: 9 }),
          }),
        ),
        selectedDeploymentId: selectedId,
      });
      await waitForPromises();
    });

    it('fetches that rollout and overrides the fallback', () => {
      expect(rolloutHandler).toHaveBeenCalledWith({ id: selectedId });
      expect(findBadge().text()).toBe('Version 9');
    });
  });

  describe('when the selected deployment has no flow of its own', () => {
    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({ applicationFlow: flowDef() }),
        rolloutResponse: rolloutFlowResponse(rolloutNode({ id: 9, flow: null })),
        selectedDeploymentId: 'gid://gitlab/Cd::Rollout/9',
      });
      await waitForPromises();
    });

    it('clears the canvas', () => {
      expect(findFlowCanvas().exists()).toBe(false);
      expect(findCreateButton().exists()).toBe(true);
    });
  });

  describe('rollout-selected event', () => {
    describe('when a rollout is shown', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({ active: rolloutNode({ id: 5, versionSetId: 5 }) }),
        });
        await waitForPromises();
      });

      it('emits the shown rollout id and version set id', () => {
        expect(lastRolloutSelected()).toEqual({
          id: 'gid://gitlab/Cd::Rollout/5',
          versionSetId: 'gid://gitlab/Cd::VersionSet/5',
        });
      });
    });

    describe('when falling back to the application flow', () => {
      beforeEach(async () => {
        createComponent({ appResponse: appFlowResponse({ applicationFlow: flowDef() }) });
        await waitForPromises();
      });

      it('emits nulls', () => {
        expect(lastRolloutSelected()).toEqual({ id: null, versionSetId: null });
      });
    });
  });
  describe('when the selected rollout has steps', () => {
    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({
          active: rolloutNode({ id: 5, flow: flowDef({ version: 2 }), steps: flowSteps() }),
        }),
        mountFn: mountExtended,
      });
      await waitForPromises();
    });

    it('renders a trigger step ahead of the flow the rollout describes', () => {
      expect(findSteps().at(0).props('category')).toBe('trigger');
    });

    describe('rollout metadata in the header', () => {
      it('shows the rollout reference, the release name and the step counts', () => {
        expect(findRolloutMeta().text()).toContain('#486 · v2.4.1 (3/6)');
      });

      describe.each([
        ['IN_PROGRESS', 'In progress'],
        ['COMPLETED', 'Available'],
        ['FAILED', 'Failed'],
      ])('when the rollout is %s', (state, expected) => {
        beforeEach(async () => {
          createComponent({
            appResponse: appFlowResponse({
              active: rolloutNode({ state, flow: flowDef({ version: 2 }), steps: flowSteps() }),
            }),
            mountFn: mountExtended,
          });
          await waitForPromises();
        });

        it('names the state in the tooltip and for screen readers', () => {
          expect(findRolloutMeta().attributes('title')).toBe(expected);
          expect(findRolloutMeta().text()).toContain(expected);
        });
      });
    });

    it('renders a container per stage and a bare step per standalone step', () => {
      expect(findStages()).toHaveLength(2);
      expect(nodeIdsInMarkup()).toEqual([
        'item-0',
        'item-1',
        'item-2',
        'item-2-step-0',
        'item-2-step-1',
        'item-2-step-2',
        'item-2-step-3',
        'item-3',
      ]);
    });

    it('expands the running stage and leaves the settled one collapsed', () => {
      expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([false, true]);
    });

    it('draws a connector for every edge', () => {
      expect(findConnectorPaths()).toHaveLength(6);
    });

    it('anchors every node exactly once, so no connector can resolve two elements', () => {
      const rendered = nodeIdsInMarkup();

      expect(rendered).toEqual([...new Set(rendered)]);
    });

    it("anchors every one of the expanded stage's steps, in flow order", () => {
      expect(expandedStepNodeIds()).toEqual([
        'item-2-step-0',
        'item-2-step-1',
        'item-2-step-2',
        'item-2-step-3',
      ]);
    });

    describe('when the rollout data changes after the user has toggled a stage', () => {
      beforeEach(async () => {
        const steps = flowSteps();

        createComponent({
          appResponse: appFlowResponse({
            active: rolloutNode({ id: 5, flow: flowDef({ version: 2 }), steps }),
          }),
          rolloutResponse: rolloutFlowResponse(
            rolloutNode({ id: 5, flow: flowDef({ version: 2 }), steps }),
          ),
          mountFn: mountExtended,
        });
        await waitForPromises();

        await findStageHeaders().at(1).trigger('click');
        await waitForPromises();
      });

      it("keeps the user's choice when the same stages arrive again", async () => {
        expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([
          false,
          false,
        ]);

        await wrapper.setProps({ selectedDeploymentId: 'gid://gitlab/Cd::Rollout/5' });
        await waitForPromises();

        expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([
          false,
          false,
        ]);
      });
    });

    describe('when a stage header is clicked', () => {
      beforeEach(async () => {
        await findStageHeaders().at(0).trigger('click');
        await waitForPromises();
      });

      it('expands that stage and leaves the others as they were', () => {
        expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([true, true]);
      });

      it('exposes the newly revealed steps as connector anchors', () => {
        expect(nodeIdsInMarkup()).toContain('item-1-step-0');
      });
    });

    describe('while at least one stage is collapsed', () => {
      it('shows the expand button', () => {
        expect(findToggleAllButton().text()).toBe('Expand all');
      });

      describe('when the toggle is clicked', () => {
        beforeEach(() => findToggleAllButton().trigger('click'));

        it('expands every stage', () => {
          expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([
            true,
            true,
          ]);
        });

        it('shows the collapse button', () => {
          expect(findToggleAllButton().text()).toBe('Collapse all');
        });

        describe('when the toggle is clicked again', () => {
          beforeEach(() => findToggleAllButton().trigger('click'));

          it('collapses every stage', () => {
            expect(findStages().wrappers.map((stage) => stage.props('expanded'))).toEqual([
              false,
              false,
            ]);
          });
        });
      });
    });
  });

  describe('when there is a flow definition but no rollout to visualize', () => {
    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({ applicationFlow: flowDef({ version: 2 }) }),
        mountFn: mountExtended,
      });
      await waitForPromises();
    });

    it('still shows the flow header for the definition that was selected', () => {
      expect(findBadge().text()).toBe('Version 2');
    });

    it('omits the rollout metadata', () => {
      expect(findRolloutMeta().exists()).toBe(false);
    });
  });

  describe('when the rollout has no steps', () => {
    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({
          active: rolloutNode({ id: 5, flow: flowDef({ version: 5 }) }),
        }),
        mountFn: mountExtended,
      });
      await waitForPromises();
    });

    it('renders the trigger and no steps', () => {
      expect(findFlowCanvas().exists()).toBe(true);
      expect(findStages()).toHaveLength(0);
      expect(findSteps()).toHaveLength(1);
    });
  });

  describe('approval gate', () => {
    describe('when the user can resolve gates', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({
            active: rolloutNode({ id: 5, steps: flowSteps() }),
            canResolveGate: true,
          }),
        });
        await waitForPromises();
      });

      it('renders the gate for the shown rollout', () => {
        expect(findFooter().props('rolloutId')).toBe('gid://gitlab/Cd::Rollout/5');
      });

      it('lets the user resolve the gate', () => {
        expect(findFooter().props('canResolve')).toBe(true);
      });
    });

    describe('when a step failed inside a stage', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({
            active: rolloutNode({
              id: 5,
              steps: [
                stageStep('production', 'FAILED', [
                  rolloutStep({
                    type: 'com.gitlab.cd.argo.canary.deploy',
                    environment: 'prod-eu',
                    state: 'FAILED',
                    error: 'image pull backoff',
                  }),
                ]),
              ],
            }),
          }),
        });
        await waitForPromises();
      });

      it('passes the failed step to the footer', () => {
        expect(findFooter().props('failedSteps')).toMatchObject([
          { state: 'FAILED', error: 'image pull backoff' },
        ]);
      });
    });

    describe('when a top-level step failed outside any stage', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({
            active: rolloutNode({
              id: 5,
              steps: [
                rolloutStep({
                  type: 'com.gitlab.cd.steps.wait',
                  state: 'FAILED',
                  error: 'unsupported step type: com.gitlab.cd.steps.wait',
                }),
              ],
            }),
          }),
        });
        await waitForPromises();
      });

      it('passes the failed step to the footer', () => {
        expect(findFooter().props('failedSteps')).toMatchObject([
          { state: 'FAILED', error: 'unsupported step type: com.gitlab.cd.steps.wait' },
        ]);
      });
    });

    describe('when a step was rejected', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({
            active: rolloutNode({
              id: 5,
              steps: [stageStep('production', 'FAILED', [approvalStep('REJECTED')])],
            }),
          }),
        });
        await waitForPromises();
      });

      it('passes no failed steps to the footer', () => {
        expect(findFooter().props('failedSteps')).toEqual([]);
      });
    });

    describe('when no step failed', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({ active: rolloutNode({ id: 5, steps: flowSteps() }) }),
        });
        await waitForPromises();
      });

      it('passes no failed steps to the footer', () => {
        expect(findFooter().props('failedSteps')).toEqual([]);
      });
    });

    describe('when the user has no permission to resolve gates', () => {
      beforeEach(async () => {
        createComponent({
          appResponse: appFlowResponse({ active: rolloutNode({ id: 5, steps: flowSteps() }) }),
        });
        await waitForPromises();
      });

      it('renders the gate read-only', () => {
        expect(findFooter().props('canResolve')).toBe(false);
      });
    });
  });

  describe('when a rollout step status is pushed over the subscription', () => {
    const selectedId = 'gid://gitlab/Cd::Rollout/9';
    const STEP_ID = 'gid://gitlab/Cd::RolloutStep/501';

    let mockSubscription;

    beforeEach(async () => {
      const steps = [{ ...waitStep('PENDING'), id: STEP_ID }];

      createComponent({
        rolloutResponse: rolloutFlowResponse(
          rolloutNode({ id: 9, versionSetId: 9, flow: flowDef({ version: 9 }), steps }),
        ),
        selectedDeploymentId: selectedId,
        mountFn: mountExtended,
        subscriptionHandler: jest.fn(() => {
          mockSubscription = createMockSubscription();
          return mockSubscription;
        }),
      });
      await waitForPromises();
    });

    it('subscribes to cdRolloutStepUpdated for the selected rollout', () => {
      expect(rolloutStepSubscriptionHandler).toHaveBeenCalledWith({ rolloutId: selectedId });
    });

    it('updates the step state in the flow canvas without refetching', async () => {
      expect(findStepBoxes().at(1).attributes('title')).toBe('Pending');

      mockSubscription.next({
        data: {
          cdRolloutStepUpdated: {
            __typename: 'CdRolloutStep',
            id: STEP_ID,
            path: '0',
            stepType: 'com.gitlab.cd.steps.wait',
            name: null,
            params: null,
            state: 'FAILED',
            error: 'boom',
            environment: null,
          },
        },
      });
      await waitForPromises();
      await nextTick();

      expect(findStepBoxes().at(1).attributes('title')).toBe('Failed');
      expect(rolloutHandler).toHaveBeenCalledTimes(1);
    });
  });

  describe('when a deploy step is selected and a step state is pushed', () => {
    const selectedId = 'gid://gitlab/Cd::Rollout/9';
    const STEP_ID = 'gid://gitlab/Cd::RolloutStep/701';

    let mockSubscription;

    beforeEach(async () => {
      const steps = [
        {
          ...rolloutStep({
            type: 'com.gitlab.cd.argo.canary.deploy',
            environment: 'prod-eu',
            params: { services: [{ name: 'api' }] },
          }),
          id: STEP_ID,
        },
      ];

      createComponent({
        rolloutResponse: rolloutFlowResponse(
          rolloutNode({ id: 9, versionSetId: 9, flow: flowDef({ version: 9 }), steps }),
        ),
        selectedDeploymentId: selectedId,
        subscriptionHandler: jest.fn(() => {
          mockSubscription = createMockSubscription();
          return mockSubscription;
        }),
      });
      await waitForPromises();

      findSteps()
        .wrappers.find((step) => step.props('category') === 'deploy')
        .vm.$emit('select');
      await nextTick();

      mockSubscription.next({
        data: {
          cdRolloutStepUpdated: {
            __typename: 'CdRolloutStep',
            id: STEP_ID,
            path: '0',
            stepType: 'com.gitlab.cd.argo.canary.deploy',
            name: null,
            params: { services: [{ name: 'api' }] },
            state: 'FAILED',
            error: 'boom',
            environment: null,
          },
        },
      });
      await waitForPromises();
      await nextTick();
    });

    it('keeps the panel open', () => {
      expect(findStepPanel().exists()).toBe(true);
    });

    it('passes the updated step to the panel', () => {
      expect(findStepPanel().props('step')).toMatchObject({ state: 'FAILED' });
    });
  });

  describe('when no deployment is selected', () => {
    const ACTIVE_ID = 'gid://gitlab/Cd::Rollout/5';
    const STEP_ID = 'gid://gitlab/Cd::RolloutStep/601';

    let mockSubscription;

    beforeEach(async () => {
      const steps = [{ ...waitStep('PENDING'), id: STEP_ID }];

      createComponent({
        appResponse: appFlowResponse({ active: rolloutNode({ id: 5, steps }) }),
        mountFn: mountExtended,
        subscriptionHandler: jest.fn(() => {
          mockSubscription = createMockSubscription();
          return mockSubscription;
        }),
      });
      await waitForPromises();
    });

    it('subscribes to cdRolloutStepUpdated for the active rollout', () => {
      expect(rolloutStepSubscriptionHandler).toHaveBeenCalledWith({ rolloutId: ACTIVE_ID });
    });

    it('updates the step state in the flow canvas', async () => {
      expect(findStepBoxes().at(1).attributes('title')).toBe('Pending');

      mockSubscription.next({
        data: {
          cdRolloutStepUpdated: {
            __typename: 'CdRolloutStep',
            id: STEP_ID,
            path: '0',
            stepType: 'com.gitlab.cd.steps.wait',
            name: null,
            params: null,
            state: 'FAILED',
            error: 'boom',
            environment: null,
          },
        },
      });
      await waitForPromises();
      await nextTick();

      expect(findStepBoxes().at(1).attributes('title')).toBe('Failed');
    });
  });

  describe('when a deployment is selected while an active rollout exists', () => {
    it('subscribes to cdRolloutStepUpdated only for the selected rollout', async () => {
      createComponent({
        appResponse: appFlowResponse({ active: rolloutNode({ id: 5 }) }),
        rolloutResponse: rolloutFlowResponse(rolloutNode({ id: 9, versionSetId: 9 })),
        selectedDeploymentId: 'gid://gitlab/Cd::Rollout/9',
      });
      await waitForPromises();

      expect(rolloutStepSubscriptionHandler).toHaveBeenCalledTimes(1);
      expect(rolloutStepSubscriptionHandler).toHaveBeenCalledWith({
        rolloutId: 'gid://gitlab/Cd::Rollout/9',
      });
    });
  });
  describe('step selection', () => {
    const selectStep = async (category) => {
      const step = wrapper
        .findAllComponents(FlowStep)
        .wrappers.find((item) => item.props('category') === category);

      step.vm.$emit('select');
      await nextTick();
    };

    beforeEach(async () => {
      createComponent({
        appResponse: appFlowResponse({ active: rolloutNode({ id: 5, steps: flowSteps() }) }),
        rolloutResponse: rolloutFlowResponse(
          rolloutNode({ id: 9, versionSetId: 9, steps: flowSteps() }),
        ),
      });
      await waitForPromises();
      await wrapper.findAllComponents(FlowStage).at(0).vm.$emit('toggle');
    });

    it('does not render the panel before a step is clicked', () => {
      expect(findStepPanel().exists()).toBe(false);
    });

    describe('when a deploy step is selected', () => {
      beforeEach(async () => {
        await selectStep('deploy');
      });

      it('renders the panel for that step', () => {
        expect(findStepPanel().exists()).toBe(true);
      });

      it('marks the step as selected', () => {
        const selected = findSteps().wrappers.filter((step) => step.props('selected'));

        expect(selected).toHaveLength(1);
        expect(selected[0].props('category')).toBe('deploy');
      });

      it('closes the panel when it emits close', async () => {
        findStepPanel().vm.$emit('close');
        await nextTick();

        expect(findStepPanel().exists()).toBe(false);
      });

      it('asks the page to close any routed panel', () => {
        expect(wrapper.emitted('step-selected')).toHaveLength(1);
      });

      it('hides the panel once a release panel opens', async () => {
        await wrapper.setProps({ routedPanelOpen: true });

        expect(findStepPanel().exists()).toBe(false);
      });

      it('passes the clicked step to the panel', () => {
        expect(findStepPanel().props('step')).toMatchObject({
          category: 'deploy',
          environment: { name: 'dev-eu' },
          services: ['api', 'worker'],
        });
      });
    });

    describe('when the trigger is selected', () => {
      beforeEach(async () => {
        await selectStep('trigger');
      });

      it('keeps the canvas title as Trigger', () => {
        expect(findSteps().at(0).props('title')).toBe('Trigger');
      });

      it('passes the release to the panel', () => {
        expect(findStepPanel().props('step')).toMatchObject({
          category: 'trigger',
          releaseName: 'v2.4.1',
          author: 'data-platform',
        });
      });
    });
  });
});
