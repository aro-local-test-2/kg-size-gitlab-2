import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { makeMockUserGroupCalloutDismisser } from 'helpers/mock_user_group_callout_dismisser';
import UserGroupCalloutDismisser from '~/vue_shared/components/user_group_callout_dismisser.vue';
import ReTrialCard from 'ee/groups/billing/components/components_with_dap_monthly_commit/re_trial_card.vue';

describe('ReTrialCard', () => {
  let wrapper;
  let dismissSpy;

  const defaultProvide = {
    eligibleForRetrial: true,
    canStartTrial: true,
    trialActive: false,
    retrialCardDismissed: false,
    retrialCardFeatureName: 'billing_retrial_card',
    groupId: 7,
    startTrialPath: '/-/trials/new?namespace_id=7',
  };

  const createComponent = ({ provide = {}, shouldShowCallout = true } = {}) => {
    dismissSpy = jest.fn();

    wrapper = shallowMountExtended(ReTrialCard, {
      provide: {
        ...defaultProvide,
        ...provide,
      },
      stubs: {
        UserGroupCalloutDismisser: makeMockUserGroupCalloutDismisser({
          dismiss: dismissSpy,
          shouldShowCallout,
        }),
      },
    });
  };

  const findCard = () => wrapper.findByTestId('re-trial-card');
  const findCta = () => wrapper.findByTestId('re-trial-card-cta');
  const findDismissButton = () => wrapper.findComponentByTestId('re-trial-card-dismiss');
  const findDismisser = () => wrapper.findComponent(UserGroupCalloutDismisser);

  describe('when the namespace is re-trial eligible', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the card', () => {
      expect(findCard().exists()).toBe(true);
    });

    it('passes the callout name and group to the dismisser', () => {
      expect(findDismisser().props()).toMatchObject({
        featureName: 'billing_retrial_card',
        groupId: 7,
        skipQuery: true,
      });
    });

    it('renders the heading and value statement', () => {
      expect(wrapper.text()).toContain('Start a GitLab Ultimate trial');
      expect(wrapper.text()).toContain(
        'Try everything GitLab Ultimate offers for your group. Free for 30 days, no credit card required.',
      );
    });

    it('renders the three benefits', () => {
      expect(wrapper.text()).toContain('Advanced security & compliance');
      expect(wrapper.text()).toContain('GitLab Duo Agent Platform');
      expect(wrapper.text()).toContain('Higher compute & seat limits');
    });

    it('points the CTA at the trial flow for the namespace', () => {
      expect(findCta().attributes('href')).toBe('/-/trials/new?namespace_id=7');
    });

    it('renders a labelled dismiss button', () => {
      expect(findDismissButton().attributes('aria-label')).toBe('Dismiss');
    });
  });

  describe.each`
    reason                              | provide
    ${'not re-trial eligible'}          | ${{ eligibleForRetrial: false }}
    ${'the user cannot start a trial'}  | ${{ canStartTrial: false }}
    ${'a trial is already active'}      | ${{ trialActive: true }}
    ${'the card was already dismissed'} | ${{ retrialCardDismissed: true }}
  `('when $reason', ({ provide }) => {
    beforeEach(() => {
      createComponent({ provide });
    });

    it('renders nothing', () => {
      expect(findDismisser().exists()).toBe(false);
      expect(findCard().exists()).toBe(false);
    });
  });

  describe('when the callout was dismissed in this session', () => {
    beforeEach(() => {
      createComponent({ shouldShowCallout: false });
    });

    it('does not render the card', () => {
      expect(findCard().exists()).toBe(false);
    });
  });

  it('dismisses the callout when the dismiss button is clicked', () => {
    createComponent();

    findDismissButton().vm.$emit('click');

    expect(dismissSpy).toHaveBeenCalled();
  });
});
