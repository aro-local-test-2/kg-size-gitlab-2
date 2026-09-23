import { GlCard, GlLink, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SecretsTrialEmptyState from 'ee/ci/secrets/components/secrets_table/secrets_trial_empty_state.vue';

describe('SecretsTrialEmptyState component', () => {
  let wrapper;

  const createComponent = ({
    isOpenbaoHealthy = true,
    isSaas = false,
    isTrialOnboarding = false,
    isEnablingAddOn = false,
  } = {}) => {
    wrapper = shallowMountExtended(SecretsTrialEmptyState, {
      provide: {
        isOpenbaoHealthy,
        isSaas,
        isTrialOnboarding,
        isEnablingAddOn,
      },
      stubs: { GlCard },
    });
  };

  const findBillingInfo = () => wrapper.findByTestId('billing-info');
  const findBillingLink = () => findBillingInfo().findComponent(GlLink);
  const findCard = () => wrapper.findComponent(GlCard);
  const findStartTrialButton = () => wrapper.findComponentByTestId('start-trial-button');
  const findEnableAddOnButton = () => wrapper.findComponentByTestId('enable-add-on-button');
  const findConfigureOpenbaoLink = () => wrapper.findByTestId('configure-openbao-link');
  const findGroupSubheader = () => wrapper.findByTestId('group-subheader');
  const findPopover = () => wrapper.findComponent(GlPopover);

  describe('template', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders title and description', () => {
      expect(findCard().text()).toContain('Secure your sensitive information');
      expect(findCard().text()).toContain(
        'Use the secrets manager to store your sensitive credentials, and then safely use them in your processes.',
      );
    });

    it('renders the trial help page link next to the trial button', () => {
      const link = wrapper.findByTestId('learn-more-trial-link');

      expect(link.attributes('href')).toBe(
        '/help/ci/secrets/secrets_manager/credit_usage#start-a-trial',
      );
    });
  });

  describe('subheader', () => {
    it('renders the subheader', () => {
      createComponent();

      expect(findGroupSubheader().text()).toBe(
        'By default, all subgroups and projects can use stored secrets in their pipelines.',
      );
    });
  });

  describe('when OpenBao is healthy', () => {
    beforeEach(() => {
      createComponent({ isOpenbaoHealthy: true });
    });

    it('renders the start trial button', () => {
      expect(findStartTrialButton().exists()).toBe(true);
    });

    it('does not render the configure openbao link', () => {
      expect(findConfigureOpenbaoLink().exists()).toBe(false);
    });
  });

  describe('when OpenBao is unhealthy', () => {
    describe('if on SaaS', () => {
      beforeEach(() => {
        createComponent({ isOpenbaoHealthy: false, isSaas: true });
      });

      it('does not render the configure openbao link', () => {
        expect(findConfigureOpenbaoLink().exists()).toBe(false);
      });

      it('does not render the start trial button', () => {
        expect(findStartTrialButton().exists()).toBe(false);
      });

      it('does not render the enable add-on button', () => {
        expect(findEnableAddOnButton().exists()).toBe(false);
      });
    });

    describe('if on self-managed', () => {
      beforeEach(() => {
        createComponent({ isOpenbaoHealthy: false, isSaas: false });
      });

      it('renders the configure openbao link', () => {
        expect(findConfigureOpenbaoLink().attributes('href')).toBe(
          '/help/administration/secrets_manager/_index',
        );
      });

      it('does not render the start trial button', () => {
        expect(findStartTrialButton().exists()).toBe(false);
      });

      it('does not render the enable add-on button', () => {
        expect(findEnableAddOnButton().exists()).toBe(false);
      });
    });
  });

  describe('billing info', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the billing footer text', () => {
      expect(findBillingInfo().text()).toContain(
        'GitLab Secrets Manager consumes GitLab Credits to store and fetch secrets.',
      );
    });

    it('renders docs link', () => {
      expect(findBillingLink().attributes('href')).toBe(
        '/help/ci/secrets/secrets_manager/credit_usage',
      );
    });
  });

  describe('start trial button', () => {
    it('emits `start-trial` when clicked', () => {
      createComponent();

      findStartTrialButton().vm.$emit('click');

      expect(wrapper.emitted('start-trial')).toHaveLength(1);
    });

    it('reflects the loading state while onboarding is in progress', () => {
      createComponent({ isTrialOnboarding: true });

      expect(findStartTrialButton().props('loading')).toBe(true);
    });

    it('is not loading when not onboarding', () => {
      createComponent({ isTrialOnboarding: false });

      expect(findStartTrialButton().props('loading')).toBe(false);
    });
  });

  describe('enable add-on button', () => {
    it('renders when OpenBao is healthy', () => {
      createComponent();

      expect(findEnableAddOnButton().exists()).toBe(true);
    });

    it('emits `enable-add-on` when clicked', () => {
      createComponent();

      findEnableAddOnButton().vm.$emit('click');

      expect(wrapper.emitted('enable-add-on')).toHaveLength(1);
    });

    it('reflects the loading state while enabling is in progress', () => {
      createComponent({ isEnablingAddOn: true });

      expect(findEnableAddOnButton().props('loading')).toBe(true);
    });

    it('disables the start trial button while enabling', () => {
      createComponent({ isEnablingAddOn: true });

      expect(findStartTrialButton().props('disabled')).toBe(true);
    });

    it('is disabled while a trial is being started', () => {
      createComponent({ isTrialOnboarding: true });

      expect(findEnableAddOnButton().props('disabled')).toBe(true);
    });
  });

  describe('trial popover', () => {
    it('shows the popover while the onboarding chain is running', () => {
      createComponent({ isTrialOnboarding: true });

      expect(findPopover().props('show')).toBe(true);
    });

    it('does not show the popover when idle', () => {
      createComponent({ isTrialOnboarding: false });

      expect(findPopover().props('show')).toBe(false);
    });
  });
});
