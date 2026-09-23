import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import MrWidget from '~/vue_merge_request_widget/components/widget/widget.vue';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import RiskClassificationWidget from 'ee/vue_merge_request_widget/widgets/risk_classification/index.vue';
import RiskRationale from 'ee/vue_merge_request_widget/widgets/risk_classification/components/risk_rationale.vue';
import RiskSignalBreakdown from 'ee/vue_merge_request_widget/widgets/risk_classification/components/risk_signal_breakdown.vue';
import RiskStaleWarning from 'ee/vue_merge_request_widget/widgets/risk_classification/components/risk_stale_warning.vue';

describe('WidgetRiskClassification', () => {
  let wrapper;

  const completedAssessment = {
    status: 'COMPLETE',
    riskTier: 'HIGH',
    confidenceTier: 'MEDIUM',
    rationale: null,
    stale: false,
    duoWorkflowId: null,
    contributingSignals: [
      {
        signal: 'touches_auth',
        label: 'Authentication or authorization logic',
        detail: 'touches_auth: true (lib/auth.rb:44)',
      },
      { signal: 'gate.auth', label: 'Auth', detail: 'Authentication domain (lib/auth.rb)' },
      { signal: 'diff_shape.churn', label: 'Size of change', detail: null },
    ],
    missingSignals: [],
  };

  const createComponent = async ({
    riskAssessment = completedAssessment,
    isLoading = false,
    hasError = false,
  } = {}) => {
    wrapper = shallowMountExtended(RiskClassificationWidget, {
      propsData: { riskAssessment, isLoading, hasError },
      stubs: { MrWidget },
    });

    await waitForPromises();
  };

  const findWidget = () => wrapper.findComponent(MrWidget);
  // The framework renders the content slot only once expanded.
  const expandWidget = async () => {
    await wrapper.findComponentByTestId('toggle-button').vm.$emit('click');
    await waitForPromises();
  };
  const findSummary = () => wrapper.findByTestId('risk-summary');
  const findTierBadge = () => wrapper.findComponentByTestId('risk-tier-badge');
  const findConfidenceBadge = () => wrapper.findComponentByTestId('risk-confidence-badge');
  const findBreakdown = () => wrapper.findComponent(RiskSignalBreakdown);
  const findStaleWarning = () => wrapper.findComponent(RiskStaleWarning);
  const findRationale = () => wrapper.findComponent(RiskRationale);
  const findDuoSessionLink = () => wrapper.findComponentByTestId('risk-duo-session-link');

  describe('when the classification completed', () => {
    beforeEach(() => createComponent());

    it('renders the widget', () => {
      expect(wrapper.findByTestId('mr-risk-classification-widget').exists()).toBe(true);
    });

    it('shows a generic title, leaving score and confidence to the pills', () => {
      expect(findSummary().text()).toBe('Risk assessment');
    });

    it('shows a confidence badge from the confidenceTier field', () => {
      expect(findConfidenceBadge().text()).toBe('Medium confidence');
      expect(findConfidenceBadge().props('variant')).toBe('warning');
    });

    it('shows a tier badge before the confidence badge, banded by severity', () => {
      expect(findTierBadge().text()).toBe('High risk');
      expect(findTierBadge().props('variant')).toBe('danger');

      const pills = wrapper.findAllComponents(GlBadge);

      expect(pills.at(0).attributes('data-testid')).toBe('risk-tier-badge');
      expect(pills.at(1).attributes('data-testid')).toBe('risk-confidence-badge');
    });

    it('is collapsible', () => {
      expect(findWidget().props('isCollapsible')).toBe(true);
    });

    it('shows a success icon, because the icon reflects lifecycle status, not the result', () => {
      expect(findWidget().props('statusIconName')).toBe(EXTENSION_ICONS.success);
    });

    it('does not show a staleness warning', () => {
      expect(findStaleWarning().exists()).toBe(false);
    });

    it('does not show a duo session link, because no session produced this classification', () => {
      expect(findDuoSessionLink().exists()).toBe(false);
    });

    describe('once expanded', () => {
      beforeEach(() => expandWidget());

      it('hands every contribution to the signal breakdown', () => {
        expect(findBreakdown().props('contributions')).toEqual(
          completedAssessment.contributingSignals,
        );
      });

      it('does not flag the breakdown as low confidence', () => {
        expect(findBreakdown().props('isLowConfidence')).toBe(false);
        expect(findBreakdown().props('missingSignalsText')).toBe('');
      });

      it('does not show a rationale section, because there is none', () => {
        expect(findRationale().exists()).toBe(false);
      });
    });
  });

  describe('when the tier and confidence are at their worst', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, riskTier: 'CRITICAL', confidenceTier: 'LOW' },
      }),
    );

    it('keeps the success icon', () => {
      expect(findWidget().props('statusIconName')).toBe(EXTENSION_ICONS.success);
    });
  });

  describe('when the assessment has a rationale', () => {
    const rationale =
      'Touches authentication logic without adding new test coverage, which drives the score.';

    beforeEach(async () => {
      await createComponent({ riskAssessment: { ...completedAssessment, rationale } });
      await expandWidget();
    });

    it('shows the rationale', () => {
      expect(findRationale().props('rationale')).toBe(rationale);
    });
  });

  describe('when a Duo workflow session produced the classification', () => {
    beforeEach(() =>
      createComponent({ riskAssessment: { ...completedAssessment, duoWorkflowId: 7 } }),
    );

    it('shows a small link to view the session, passing its ID through', () => {
      expect(findDuoSessionLink().props('sessionId')).toBe(7);
      expect(findDuoSessionLink().props('size')).toBe('small');
    });
  });

  describe('when confidence is low', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: {
          ...completedAssessment,
          confidenceTier: 'LOW',
          missingSignals: [
            { signal: 'coverage', label: 'test coverage' },
            { signal: 'ai_authorship', label: 'commit authorship' },
          ],
        },
      }),
    );

    it('bands the confidence badge as low', () => {
      expect(findConfidenceBadge().text()).toBe('Low confidence');
      expect(findConfidenceBadge().props('variant')).toBe('danger');
    });

    it('names what could not be measured once expanded', async () => {
      await expandWidget();

      expect(findBreakdown().props('isLowConfidence')).toBe(true);
      expect(findBreakdown().props('missingSignalsText')).toBe('test coverage, commit authorship');
    });
  });

  describe('when a missing signal has no label', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: {
          ...completedAssessment,
          confidenceTier: 'LOW',
          missingSignals: [
            { signal: 'coverage', label: 'test coverage' },
            { signal: 'authentication', label: null },
          ],
        },
      }),
    );

    it('leaves the unnameable signal out of the sentence', async () => {
      await expandWidget();

      expect(findBreakdown().props('missingSignalsText')).toBe('test coverage');
    });
  });

  describe('when no missing signal can be named', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: {
          ...completedAssessment,
          confidenceTier: 'LOW',
          missingSignals: [{ signal: 'authentication', label: null }],
        },
      }),
    );

    it('passes no text, so the breakdown can drop the notice', async () => {
      await expandWidget();

      expect(findBreakdown().props('missingSignalsText')).toBe('');
    });
  });

  describe('when confidence is very high', () => {
    beforeEach(() =>
      createComponent({ riskAssessment: { ...completedAssessment, confidenceTier: 'CRITICAL' } }),
    );

    it('bands the confidence badge as very high', () => {
      expect(findConfidenceBadge().text()).toBe('Very high confidence');
      expect(findConfidenceBadge().props('variant')).toBe('success');
    });
  });

  describe('when the merge request changed after classification', () => {
    beforeEach(async () => {
      await createComponent({ riskAssessment: { ...completedAssessment, stale: true } });
      await expandWidget();
    });

    it('warns that the assessment reflects an earlier diff', () => {
      expect(findStaleWarning().exists()).toBe(true);
    });
  });

  describe('when the classification is still running', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, status: 'PENDING', riskTier: null },
      }),
    );

    it('says classification is pending', () => {
      expect(findSummary().text()).toBe('Risk assessment pending');
    });

    it('is not collapsible, since there is nothing to expand yet', () => {
      expect(findWidget().props('isCollapsible')).toBe(false);
    });

    it('shows a neutral icon, since there is nothing to report yet', () => {
      expect(findWidget().props('statusIconName')).toBe(EXTENSION_ICONS.neutral);
    });

    it('does not show the tier or confidence pills', () => {
      expect(findTierBadge().exists()).toBe(false);
      expect(findConfidenceBadge().exists()).toBe(false);
    });
  });

  describe('when a first classification is queued', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, status: 'QUEUED', riskTier: null },
      }),
    );

    it('says a new assessment is queued, not merely pending', () => {
      expect(findSummary().text()).toBe('New risk assessment queued');
    });

    it('shows a notice icon, since a run is in progress', () => {
      expect(findWidget().props('statusIconName')).toBe(EXTENSION_ICONS.notice);
    });

    it('shows no pills and cannot be expanded', () => {
      expect(findTierBadge().exists()).toBe(false);
      expect(findWidget().props('isCollapsible')).toBe(false);
    });
  });

  describe('when a re-classification is queued over a previous result', () => {
    beforeEach(() =>
      createComponent({ riskAssessment: { ...completedAssessment, status: 'QUEUED' } }),
    );

    it('says the classification is updating', () => {
      expect(findSummary().text()).toBe('Risk assessment updating');
    });

    it('keeps showing the previous pills rather than dropping the result', () => {
      expect(findTierBadge().text()).toBe('High risk');
      expect(findConfidenceBadge().text()).toBe('Medium confidence');
    });

    it('stays expandable so the previous rationale and signals remain reachable', async () => {
      expect(findWidget().props('isCollapsible')).toBe(true);

      await expandWidget();

      expect(findBreakdown().exists()).toBe(true);
    });
  });

  describe('when the record is complete but carries no score', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, riskTier: null, confidenceTier: null },
      }),
    );

    it('renders no pills, rather than blank ones', () => {
      expect(findTierBadge().exists()).toBe(false);
      expect(findConfidenceBadge().exists()).toBe(false);
    });

    it('cannot be expanded, since there is no result to show', () => {
      expect(findWidget().props('isCollapsible')).toBe(false);
    });
  });

  describe('when the classification failed', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, status: 'FAILED', riskTier: null },
      }),
    );

    it('says the classification failed', () => {
      expect(findSummary().text()).toBe('Risk assessment failed');
    });

    it('shows a failed icon', () => {
      expect(findWidget().props('statusIconName')).toBe(EXTENSION_ICONS.failed);
    });

    it('shows no pills and cannot be expanded, since there is no score', () => {
      expect(findTierBadge().exists()).toBe(false);
      expect(findConfidenceBadge().exists()).toBe(false);
      expect(findWidget().props('isCollapsible')).toBe(false);
    });
  });

  describe('when a failed run left a previous score behind', () => {
    beforeEach(() =>
      createComponent({ riskAssessment: { ...completedAssessment, status: 'FAILED' } }),
    );

    it('still reports the failure rather than the stale score', () => {
      expect(findSummary().text()).toBe('Risk assessment failed');
    });

    it('does not leak the previous pills', () => {
      expect(findTierBadge().exists()).toBe(false);
      expect(findConfidenceBadge().exists()).toBe(false);
    });
  });

  describe('when the assessment is still being fetched', () => {
    beforeEach(() => createComponent({ riskAssessment: null, isLoading: true }));

    it('says the classification is loading', () => {
      expect(findSummary().text()).toBe('Loading the risk assessment');
    });

    it('falls back to a neutral icon and no pills', () => {
      expect(findWidget().props('statusIconName')).toBe(EXTENSION_ICONS.neutral);
      expect(findTierBadge().exists()).toBe(false);
    });
  });

  describe('when the fetch failed', () => {
    beforeEach(() => createComponent({ riskAssessment: null, hasError: true }));

    it('puts the widget into its error state', () => {
      expect(findWidget().props('hasError')).toBe(true);
    });
  });
});
