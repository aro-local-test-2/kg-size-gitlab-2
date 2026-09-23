import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import RiskClassificationApp from 'ee/vue_merge_request_widget/widgets/risk_classification/app.vue';
import RiskClassificationWidget from 'ee/vue_merge_request_widget/widgets/risk_classification/index.vue';
import riskAssessmentQuery from 'ee/vue_merge_request_widget/widgets/risk_classification/graphql/risk_assessment.query.graphql';

Vue.use(VueApollo);

describe('WidgetRiskClassificationApp', () => {
  let wrapper;

  const mergeRequest = {
    iid: 1,
    targetProjectFullPath: 'gitlab-org/gitlab',
    sourceProjectFullPath: 'gitlab-org/gitlab-fork',
  };

  const completedAssessment = {
    status: 'COMPLETE',
    riskTier: 'LOW',
    confidenceTier: 'HIGH',
    rationale: null,
    stale: false,
    duoWorkflowId: null,
    contributingSignals: [],
    missingSignals: [],
  };

  const queryResponse = (riskAssessment) => ({
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        mergeRequest: {
          id: 'gid://gitlab/MergeRequest/1',
          riskAssessment,
        },
      },
    },
  });

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(queryResponse(completedAssessment)),
    propsData = {},
  } = {}) => {
    wrapper = shallowMountExtended(RiskClassificationApp, {
      propsData: { mergeRequest, ...propsData },
      apolloProvider: createMockApollo([[riskAssessmentQuery, handler]]),
    });

    return handler;
  };

  const findWidget = () => wrapper.findComponent(RiskClassificationWidget);

  describe('while the assessment is loading', () => {
    it('does not render the widget', () => {
      createComponent();

      expect(findWidget().exists()).toBe(false);
    });
  });

  describe('once the assessment arrives', () => {
    it('requests the assessment for the target project', async () => {
      const handler = createComponent();
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({ projectPath: 'gitlab-org/gitlab', iid: '1' });
    });

    it('falls back to the source project when there is no target project', async () => {
      const handler = createComponent({
        propsData: { mergeRequest: { ...mergeRequest, targetProjectFullPath: null } },
      });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        projectPath: 'gitlab-org/gitlab-fork',
        iid: '1',
      });
    });

    it('passes the assessment to the widget', async () => {
      createComponent();
      await waitForPromises();

      expect(findWidget().props()).toMatchObject({
        riskAssessment: completedAssessment,
        isLoading: false,
        hasError: false,
      });
    });
  });

  describe('when the project is not classifying merge requests', () => {
    it('does not render the widget', async () => {
      createComponent({ handler: jest.fn().mockResolvedValue(queryResponse(null)) });
      await waitForPromises();

      expect(findWidget().exists()).toBe(false);
    });
  });

  describe('when the query fails', () => {
    it('renders the widget in its error state', async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('nope')) });
      await waitForPromises();

      expect(findWidget().props()).toMatchObject({
        riskAssessment: null,
        isLoading: false,
        hasError: true,
      });
    });
  });
});
