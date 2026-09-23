import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkItemAiWidget from 'ee/work_items/components/ai_widget/work_item_ai_widget.vue';
import WorkItemConfidenceScore from 'ee/work_items/components/ai_widget/work_item_confidence_score.vue';
import WorkPlan from 'ee/work_items/components/ai_widget/work_plan.vue';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import workItemAgentPlanUpdatedSubscription from 'ee/work_items/graphql/work_item_agent_plan.subscription.graphql';
import { buildAgentPlanWidgetMock } from 'ee_jest/work_items/mock_data';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { AGENT_PLAN_PANEL } from '~/work_items/constants';
import { ACTIVE_RUN_POLL_INTERVAL_MS } from 'ee/work_items/components/ai_widget/constants';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('WorkItemAiWidget', () => {
  let wrapper;

  const mockWorkItemId = 'gid://gitlab/WorkItem/1';
  const workItem = { id: mockWorkItemId };

  const agentPlanResponse = ({
    content = 'a plan',
    contentHtml = '<p>a plan</p>',
    aiPlanningEnabled = true,
    readinessScore = null,
    generationStatus = null,
    useWorkItemFeatures = false,
  } = {}) => {
    const agentPlan = buildAgentPlanWidgetMock({
      content,
      contentHtml,
      aiPlanningEnabled,
      readinessScore,
      generationStatus,
    });

    return {
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: mockWorkItemId,
          iid: '1',
          ...(useWorkItemFeatures
            ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
            : { widgets: [agentPlan] }),
        },
      },
    };
  };

  const createComponent = ({
    props = {},
    glFeatures = {},
    queryHandler = jest.fn().mockResolvedValue(agentPlanResponse()),
    subscriptionHandler = jest.fn().mockResolvedValue({ data: null }),
  } = {}) => {
    wrapper = shallowMountExtended(WorkItemAiWidget, {
      apolloProvider: createMockApollo([
        [workItemAgentPlanQuery, queryHandler],
        [workItemAgentPlanUpdatedSubscription, subscriptionHandler],
      ]),
      propsData: { workItem, ...props },
      provide: { glFeatures },
    });
  };

  const findConfidenceScore = () => wrapper.findComponent(WorkItemConfidenceScore);
  const findWorkPlan = () => wrapper.findComponent(WorkPlan);

  it('always renders the work plan child', () => {
    createComponent();
    expect(findWorkPlan().exists()).toBe(true);
  });

  it('forwards props to the work plan child', () => {
    createComponent({
      props: { canUpdate: true, workItemWebUrl: '/url', isInDrawer: true, isPanelOpen: true },
    });
    expect(findWorkPlan().props()).toMatchObject({
      workItem,
      canUpdate: true,
      workItemWebUrl: '/url',
      isInDrawer: true,
      isPanelOpen: true,
    });
  });

  it('re-emits request-panel from the work plan child', () => {
    createComponent();
    findWorkPlan().vm.$emit('request-panel', AGENT_PLAN_PANEL);
    expect(wrapper.emitted('request-panel')).toEqual([[AGENT_PLAN_PANEL]]);
  });

  describe('agent plan query', () => {
    it('marks the work plan as loading until the query settles', async () => {
      createComponent();

      expect(findWorkPlan().props('isLoading')).toBe(true);

      await waitForPromises();

      expect(findWorkPlan().props('isLoading')).toBe(false);
    });

    it('passes the queried plan down to the work plan child', async () => {
      createComponent();
      await waitForPromises();

      expect(findWorkPlan().props('agentPlan')).toMatchObject({
        content: 'a plan',
        contentHtml: '<p>a plan</p>',
      });
    });

    describe('when the work item has no id yet', () => {
      const queryHandler = jest.fn().mockResolvedValue(agentPlanResponse());

      beforeEach(async () => {
        createComponent({ props: { workItem: {} }, queryHandler });
        await waitForPromises();
      });

      it('does not query', () => {
        expect(queryHandler).not.toHaveBeenCalled();
      });
    });

    describe('when workItemFeaturesField is enabled', () => {
      const queryHandler = jest
        .fn()
        .mockResolvedValue(agentPlanResponse({ useWorkItemFeatures: true }));

      beforeEach(async () => {
        createComponent({ queryHandler, glFeatures: { workItemFeaturesField: true } });
        await waitForPromises();
      });

      it('reads the plan from the features field', () => {
        expect(queryHandler).toHaveBeenCalledWith(
          expect.objectContaining({ useWorkItemFeatures: true }),
        );
        expect(findWorkPlan().props('agentPlan')).toMatchObject({
          content: 'a plan',
          contentHtml: '<p>a plan</p>',
        });
      });
    });

    describe('when the query errors', () => {
      beforeEach(async () => {
        createComponent({ queryHandler: jest.fn().mockRejectedValue(new Error('boom')) });
        await waitForPromises();
      });

      it('reports to Sentry and leaves the plan empty', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
        expect(findWorkPlan().props('agentPlan')).toBe(null);
      });
    });
  });

  describe('readiness score', () => {
    describe('when the workplanScore feature flag is disabled', () => {
      const queryHandler = jest.fn().mockResolvedValue(agentPlanResponse({ readinessScore: 85 }));

      beforeEach(async () => {
        createComponent({ glFeatures: { workplanScore: false }, queryHandler });
        await waitForPromises();
      });

      it('does not render the score', () => {
        expect(findConfidenceScore().exists()).toBe(false);
      });

      it('does not request the score field', () => {
        expect(queryHandler).toHaveBeenCalledWith(
          expect.objectContaining({ includeReadinessScore: false }),
        );
      });
    });

    describe('when the workplanScore feature flag is enabled', () => {
      const queryHandler = jest.fn().mockResolvedValue(agentPlanResponse({ readinessScore: 85 }));

      beforeEach(async () => {
        createComponent({ glFeatures: { workplanScore: true }, queryHandler });
        await waitForPromises();
      });

      it('requests the score field', () => {
        expect(queryHandler).toHaveBeenCalledWith(
          expect.objectContaining({ includeReadinessScore: true }),
        );
      });

      it('renders the score', () => {
        expect(findConfidenceScore().exists()).toBe(true);
      });

      it('passes the queried readiness score to the score component', () => {
        expect(findConfidenceScore().props('score')).toBe(85);
      });
    });

    describe('when the flag is enabled but the query is still loading', () => {
      const queryHandler = jest.fn().mockResolvedValue(agentPlanResponse({ readinessScore: 85 }));

      it('does not render the score until the query settles', async () => {
        createComponent({ glFeatures: { workplanScore: true }, queryHandler });

        expect(findConfidenceScore().exists()).toBe(false);

        await waitForPromises();

        expect(findConfidenceScore().props('score')).toBe(85);
      });
    });

    describe('when the flag is enabled but the score is not available yet', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: { workplanScore: true },
          queryHandler: jest.fn().mockResolvedValue(agentPlanResponse({ readinessScore: null })),
        });
        await waitForPromises();
      });

      it('does not render the score', () => {
        expect(findConfidenceScore().exists()).toBe(false);
      });
    });

    describe('when the flag is enabled and the score is zero', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: { workplanScore: true },
          queryHandler: jest.fn().mockResolvedValue(agentPlanResponse({ readinessScore: 0 })),
        });
        await waitForPromises();
      });

      it('renders the score', () => {
        expect(findConfidenceScore().props('score')).toBe(0);
      });
    });
  });
  describe('polling while a run is active', () => {
    // A subscription that never emits, so the poll is the only thing re-reading the plan.
    const mountWithStatus = async (generationStatus) => {
      const queryHandler = jest.fn().mockResolvedValue(agentPlanResponse({ generationStatus }));
      createComponent({ queryHandler, subscriptionHandler: jest.fn(() => new Promise(() => {})) });
      await waitForPromises();

      return queryHandler;
    };

    const advanceWorkplanPollTimer = async (intervals = 1) => {
      jest.advanceTimersByTime(ACTIVE_RUN_POLL_INTERVAL_MS * intervals);
      await waitForPromises();
    };

    beforeEach(() => {
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    it.each(['GENERATING', 'NEEDS_INPUT'])(
      're-reads the plan while the run is %s, since the terminal status push can go missing',
      async (generationStatus) => {
        const queryHandler = await mountWithStatus(generationStatus);

        expect(queryHandler).toHaveBeenCalledTimes(1);

        await advanceWorkplanPollTimer();

        expect(queryHandler).toHaveBeenCalledTimes(2);
      },
    );

    it.each(['COMPLETED', 'FAILED', null])(
      'stops once the run has settled on %s',
      async (generationStatus) => {
        const queryHandler = await mountWithStatus(generationStatus);

        await advanceWorkplanPollTimer(3);

        expect(queryHandler).toHaveBeenCalledTimes(1);
      },
    );

    // The refetch after a mutation is a single shot, so a stale read there would
    // otherwise leave a running flow with nothing watching it.
    it('polls while an action is in flight, even though the run still reads as settled', async () => {
      const queryHandler = await mountWithStatus('COMPLETED');
      await advanceWorkplanPollTimer();

      expect(queryHandler).toHaveBeenCalledTimes(1);

      findWorkPlan().vm.$emit('run-active', true);
      await waitForPromises();
      await advanceWorkplanPollTimer();

      expect(queryHandler).toHaveBeenCalledTimes(2);
    });
  });
});
