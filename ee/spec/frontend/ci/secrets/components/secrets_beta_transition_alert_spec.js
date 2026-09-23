import { GlAlert, GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { localeDateFormat } from '~/lib/utils/datetime/locale_dateformat';
import { MILLISECONDS_IN_DAY } from '~/lib/utils/datetime/date_calculation_utility';
import SecretsBetaTransitionAlert from 'ee/ci/secrets/components/secrets_beta_transition_alert.vue';
import { BETA_CUTOFF_DATE } from 'ee/ci/secrets/constants';

const MILLISECONDS_IN_HOUR = MILLISECONDS_IN_DAY / 24;

describe('SecretsBetaTransitionAlert', () => {
  let wrapper;

  const TOP_LEVEL_GROUP = 'top-level-group';
  const cutoffMs = new Date(BETA_CUTOFF_DATE).getTime();

  const createComponent = ({ props = {}, provide = {} } = {}) => {
    wrapper = mountExtended(SecretsBetaTransitionAlert, {
      propsData: {
        isBeta: true,
        isTrialEligible: true,
        ...props,
      },
      provide: {
        canStartTrial: false,
        fullPath: TOP_LEVEL_GROUP,
        isSaas: true,
        topLevelGroupFullPath: TOP_LEVEL_GROUP,
        ...provide,
      },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findCtaButton = () => wrapper.findComponentByTestId('beta-alert-start-trial');
  const findEnableButton = () => wrapper.findComponentByTestId('beta-alert-enable-add-on');
  const findContactOwner = () => wrapper.findByTestId('beta-alert-contact-owner');

  describe('visibility', () => {
    it('renders for a beta namespace in trial_eligible', () => {
      createComponent();

      expect(findAlert().exists()).toBe(true);
    });

    it('does not render for non-beta namespaces', () => {
      createComponent({ props: { isBeta: false } });

      expect(findAlert().exists()).toBe(false);
    });

    it('does not render when the namespace is not trial_eligible', () => {
      createComponent({ props: { isTrialEligible: false } });

      expect(findAlert().exists()).toBe(false);
    });

    // Behavior updated for SaaS only; self-managed to follow
    it('does not render on self-managed', () => {
      createComponent({ provide: { isSaas: false } });

      expect(findAlert().exists()).toBe(false);
    });

    it('still renders when the beta program has ended (danger variant)', () => {
      createComponent({ props: { betaProgramEnded: true } });

      expect(findAlert().exists()).toBe(true);
    });
  });

  describe('variant, title, and description', () => {
    describe('during the grace window (warning variant)', () => {
      // Freeze "now" to a known distance from BETA_CUTOFF_DATE so the countdown
      // renders deterministically. Cleared in afterEach.
      let dateNowSpy;
      const freezeAt = (msBeforeCutoff) => {
        dateNowSpy = jest.spyOn(Date, 'now').mockReturnValue(cutoffMs - msBeforeCutoff);
      };

      afterEach(() => {
        dateNowSpy?.mockRestore();
      });

      it('is the warning variant', () => {
        freezeAt(2 * MILLISECONDS_IN_DAY);
        createComponent();

        expect(findAlert().props('variant')).toBe('warning');
      });

      it('shows a "days remaining" countdown when more than 24h remain', () => {
        freezeAt(2 * MILLISECONDS_IN_DAY);
        createComponent();

        expect(findAlert().props('title')).toBe('Your free beta ends in 2 days.');
      });

      it('switches to hours once less than 24h remain', () => {
        freezeAt(23 * MILLISECONDS_IN_HOUR);
        createComponent();

        expect(findAlert().props('title')).toBe('Your free beta ends in 23 hours.');
      });

      // If the launch is delayed past the cutoff, we clamp to "1 hour"
      // until the FF flips and the danger variant takes over.
      it('clamps to "1 hour" when the cutoff has passed', () => {
        freezeAt(-MILLISECONDS_IN_HOUR);
        createComponent();

        expect(findAlert().props('title')).toBe('Your free beta ends in 1 hour.');
      });

      it('mentions the cutoff timestamp in the description', () => {
        freezeAt(2 * MILLISECONDS_IN_DAY);
        createComponent();

        const expectedCutoff = localeDateFormat.asDateTimeFull.format(new Date(BETA_CUTOFF_DATE));
        expect(findAlert().text()).toContain(expectedCutoff);
      });
    });

    describe('once the beta program has ended (danger variant)', () => {
      beforeEach(() => {
        createComponent({ props: { betaProgramEnded: true }, provide: { canStartTrial: true } });
      });

      it('renders the danger variant with the disabled title and credits description', () => {
        expect(findAlert().props('variant')).toBe('danger');
        expect(findAlert().props('title')).toBe(
          'Your Beta period is over and GitLab Secrets Manager has been disabled',
        );
        expect(findAlert().text()).toContain(
          'Enable with GitLab Credits to continue using GitLab Secrets Manager and avoid service disruptions.',
        );
      });

      it('keeps both CTAs available', () => {
        expect(findEnableButton().text()).toBe('Enable with GitLab Credits');
        expect(findCtaButton().text()).toBe('Start 30-day trial');
      });

      it('emits `enable-add-on` when the enable CTA is clicked', async () => {
        await findEnableButton().trigger('click');

        expect(wrapper.emitted('enable-add-on')).toHaveLength(1);
      });
    });

    describe.each`
      variant      | betaProgramEnded
      ${'warning'} | ${false}
      ${'danger'}  | ${true}
    `('in the $variant variant', ({ betaProgramEnded }) => {
      it('shows a "How does GitLab Secrets Manager use GitLab Credits?" link to the credits docs', () => {
        createComponent({ props: { betaProgramEnded } });

        const link = wrapper.findComponent(GlLink);
        expect(link.text()).toBe('How does GitLab Secrets Manager use GitLab Credits?');
        expect(link.attributes('href')).toBe('/help/ci/secrets/secrets_manager/credit_usage');
      });
    });
  });

  describe('when the current user can start the trial (TLG Owner)', () => {
    beforeEach(() => {
      createComponent({ provide: { canStartTrial: true } });
    });

    it('shows the "Start 30-day trial" CTA', () => {
      expect(findCtaButton().text()).toBe('Start 30-day trial');
    });

    it('shows the "Enable with GitLab Credits" CTA', () => {
      expect(findEnableButton().text()).toBe('Enable with GitLab Credits');
    });

    it('emits `enable-add-on` when the enable CTA is clicked', async () => {
      await findEnableButton().trigger('click');

      expect(wrapper.emitted('enable-add-on')).toHaveLength(1);
    });

    it('disables the trial CTA while the add-on is being enabled', () => {
      createComponent({ props: { isEnablingAddOn: true }, provide: { canStartTrial: true } });

      expect(findCtaButton().props('disabled')).toBe(true);
    });

    it('disables the enable CTA while the trial is being started', () => {
      createComponent({ props: { isTrialOnboarding: true }, provide: { canStartTrial: true } });

      expect(findEnableButton().props('disabled')).toBe(true);
    });

    // The CTA emits `start-trial` so the parent can swap the app into
    // the trial-start flow instead of navigating; see the TODO in
    // https://gitlab.com/gitlab-org/gitlab/-/work_items/612881 for the
    // Vue 3 emit-handling coverage follow-up.
    it('emits `start-trial` when the CTA is clicked', async () => {
      await findCtaButton().trigger('click');

      expect(wrapper.emitted('start-trial')).toHaveLength(1);
    });

    it('does not show the "contact administrator" prompt', () => {
      expect(findContactOwner().exists()).toBe(false);
    });
  });

  describe('when the current user cannot start the trial', () => {
    beforeEach(() => {
      createComponent({ provide: { canStartTrial: false, fullPath: 'sub-group' } });
    });

    it('shows the "contact owner" prompt', () => {
      expect(findContactOwner().exists()).toBe(true);
    });

    it('does not show the CTA', () => {
      expect(findCtaButton().exists()).toBe(false);
    });
  });
});
