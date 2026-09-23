import { GlButton } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import WorkItemPlanCta from 'ee/work_items/components/work_item_plan_cta.vue';
import workItemEnableAiPlanningMutation from 'ee/work_items/graphql/work_item_enable_ai_planning.mutation.graphql';
import workItemGenerateWorkplanMutation from 'ee/work_items/graphql/work_item_generate_workplan.mutation.graphql';
import {
  buildAgentPlanWidgetMock,
  buildWorkplanFlowMutationResponse,
} from 'ee_else_ce_jest/work_items/mock_data';
import { eventHub, REFETCH_SESSIONS } from 'ee/ai/events/panel';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('WorkItemPlanCta component', () => {
  let wrapper;

  const mockWorkItemId = 'gid://gitlab/WorkItem/1';

  const buildWorkItem = ({ useFeatures = false } = {}) => ({
    id: mockWorkItemId,
    ...(useFeatures
      ? { features: { agentPlan: buildAgentPlanWidgetMock() } }
      : { widgets: [buildAgentPlanWidgetMock()] }),
  });

  const successMutationHandler = jest.fn().mockResolvedValue({
    data: {
      workItemEnableAiPlanning: {
        __typename: 'WorkItemEnableAiPlanningPayload',
        workItem: null,
        errors: [],
      },
    },
  });

  const generateHandlerFor = (options) =>
    jest
      .fn()
      .mockResolvedValue(buildWorkplanFlowMutationResponse('workItemGenerateWorkplan', options));

  const createComponent = ({
    workItem = buildWorkItem(),
    mutationHandler = successMutationHandler,
    generateHandler = generateHandlerFor(),
    glFeatures = {},
  } = {}) => {
    wrapper = shallowMountExtended(WorkItemPlanCta, {
      apolloProvider: createMockApollo([
        [workItemEnableAiPlanningMutation, mutationHandler],
        [workItemGenerateWorkplanMutation, generateHandler],
      ]),
      propsData: { workItem },
      provide: { glFeatures },
    });
  };

  const findPlanButton = () => wrapper.findComponent(GlButton);

  let emitSpy;

  beforeEach(() => {
    successMutationHandler.mockClear();
    emitSpy = jest.spyOn(eventHub, '$emit');
  });

  afterEach(() => {
    emitSpy.mockRestore();
  });

  describe('when clicking the button', () => {
    beforeEach(async () => {
      createComponent();
      findPlanButton().vm.$emit('click');
      await waitForPromises();
    });

    it('fires the mutation with the work item id', () => {
      expect(successMutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          input: { id: mockWorkItemId },
        }),
      );
    });

    describe('when the work item features field is enabled', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: { workItemFeaturesField: true },
          workItem: buildWorkItem({ useFeatures: true }),
        });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('passes useWorkItemFeatures to the mutation', () => {
        expect(successMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({ useWorkItemFeatures: true }),
        );
      });
    });

    it('sets the button to loading while the mutation is in flight', async () => {
      const mutationHandler = jest.fn().mockReturnValue(new Promise(() => {}));
      createComponent({ mutationHandler });

      findPlanButton().vm.$emit('click');
      await nextTick();

      expect(findPlanButton().props('loading')).toBe(true);
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        const mutationHandler = jest.fn().mockResolvedValue({
          data: {
            workItemEnableAiPlanning: {
              __typename: 'WorkItemEnableAiPlanningPayload',
              workItem: null,
              errors: ['AI planning is not available for this work item'],
            },
          },
        });
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('emits the backend reason', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['AI planning is not available for this work item'],
        ]);
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });

    describe('when the mutation rejects', () => {
      beforeEach(async () => {
        const mutationHandler = jest.fn().mockRejectedValue(new Error('network error'));
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('emits the generic error and reports to Sentry', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['Something went wrong while enabling planning for this item. Please try again.'],
        ]);
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });

    describe('when the mutation fails without a message', () => {
      beforeEach(async () => {
        const mutationHandler = jest.fn().mockRejectedValue(new Error());
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('emits the generic fallback and reports to Sentry', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['Something went wrong while enabling planning for this item. Please try again.'],
        ]);
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });
  });

  describe('when duo_workplan_async_flow is enabled', () => {
    const asyncFlowFeatures = { duoWorkplanAsyncFlow: true };

    // Generation has to come first so the widget's first query, fired as soon as
    // enabling planning mounts it, already sees the running flow.
    it('starts workplan generation before enabling planning', async () => {
      const generateHandler = generateHandlerFor();
      createComponent({ glFeatures: asyncFlowFeatures, generateHandler });
      findPlanButton().vm.$emit('click');
      await waitForPromises();

      expect(generateHandler).toHaveBeenCalledWith({ input: { id: mockWorkItemId } });
      expect(generateHandler.mock.invocationCallOrder[0]).toBeLessThan(
        successMutationHandler.mock.invocationCallOrder[0],
      );
    });

    describe('when generation cannot start', () => {
      const generateErrorHandler = generateHandlerFor({
        errors: ['Async workplan generation is not enabled for this project'],
      });

      beforeEach(async () => {
        createComponent({
          glFeatures: asyncFlowFeatures,
          generateHandler: generateErrorHandler,
        });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('emits the backend reason', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['Async workplan generation is not enabled for this project'],
        ]);
      });
    });

    describe('when the generate mutation rejects', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: asyncFlowFeatures,
          generateHandler: jest.fn().mockRejectedValue(new Error('network error')),
        });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('still enables planning', () => {
        expect(successMutationHandler).toHaveBeenCalled();
      });

      it('emits a generation-specific message and reports to Sentry', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['Something went wrong while starting workplan generation.'],
        ]);
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });
  });

  describe('when duo_workplan_async_flow is disabled', () => {
    it('does not start workplan generation', async () => {
      const generateHandler = generateHandlerFor();
      createComponent({ generateHandler });
      findPlanButton().vm.$emit('click');
      await waitForPromises();

      expect(generateHandler).not.toHaveBeenCalled();
    });
  });

  describe('refetching the agent sessions list', () => {
    const asyncFlowFeatures = { duoWorkplanAsyncFlow: true };

    describe('when generation starts successfully', () => {
      beforeEach(async () => {
        createComponent({ glFeatures: asyncFlowFeatures });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('signals that the sessions list is stale', () => {
        expect(emitSpy).toHaveBeenCalledWith(REFETCH_SESSIONS);
      });
    });

    describe('when generation returns errors', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: asyncFlowFeatures,
          generateHandler: generateHandlerFor({ errors: ['nope'] }),
        });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('does not signal that the sessions list is stale', () => {
        expect(emitSpy).not.toHaveBeenCalledWith(REFETCH_SESSIONS);
      });
    });

    describe('when duo_workplan_async_flow is disabled', () => {
      beforeEach(async () => {
        createComponent();
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('does not signal that the sessions list is stale', () => {
        expect(emitSpy).not.toHaveBeenCalledWith(REFETCH_SESSIONS);
      });
    });
  });
});
