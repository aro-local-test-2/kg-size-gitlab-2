import { mount, shallowMount } from '@vue/test-utils';
import { GlAlert, GlButton } from '@gitlab/ui';
import { nextTick } from 'vue';
import PipelineAccountVerificationAlert from 'ee/vue_shared/components/pipeline_account_verification_alert.vue';

describe('Identity verification needed to run pipelines alert', () => {
  const DEFAULT_PROVIDES = { identityVerificationRequired: true };

  let wrapper;

  const createWrapper = (
    { props, provide, mountFn = shallowMount } = { props: {}, provide: {} },
  ) => {
    wrapper = mountFn(PipelineAccountVerificationAlert, {
      propsData: props,
      provide: {
        identityVerificationPath: 'identity/verification/path',
        ...DEFAULT_PROVIDES,
        ...provide,
      },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findActionButton = () => wrapper.findComponent(GlButton);

  describe('when identity verification is not required', () => {
    it('does not show alert', () => {
      createWrapper({ provide: { identityVerificationRequired: false } });

      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when identity verification is required', () => {
    beforeEach(() => {
      createWrapper({ mountFn: mount });
    });

    it('shows alert with expected title and variant', () => {
      expect(findAlert().props()).toMatchObject({
        title: 'Before you can run pipelines, we need to verify your account.',
        variant: 'danger',
      });
    });

    it('shows alert with expected description', () => {
      expect(findAlert().text()).toContain(
        `We won't ask you for this information again. It will never be used for marketing purposes.`,
      );
    });

    it('shows the action button with the expected text, link, and variant', () => {
      expect(findActionButton().text()).toBe('Verify my account');
      expect(findActionButton().attributes('href')).toBe('identity/verification/path');
      expect(findActionButton().props('variant')).toBe('confirm');
    });

    it('does not open the link in a new tab by default', () => {
      expect(findActionButton().attributes('target')).toBeUndefined();
    });

    it(`hides the alert when it's dismissed`, async () => {
      findAlert().vm.$emit('dismiss');
      await nextTick();

      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('custom title', () => {
    it('shows alert with expected props', () => {
      createWrapper({ props: { title: 'Custom title' } });

      expect(findAlert().props()).toMatchObject({
        title: 'Custom title',
      });
    });
  });

  describe('custom button text', () => {
    it('shows the action button with the custom text', () => {
      createWrapper({ props: { buttonText: 'Custom button' }, mountFn: mount });

      expect(findActionButton().text()).toBe('Custom button');
    });
  });

  describe('custom description', () => {
    it('shows alert with expected description', () => {
      createWrapper({ props: { description: 'Custom description' } });

      expect(findAlert().text()).toBe('Custom description');
    });
  });

  describe('dismissible', () => {
    it('is dismissible by default', () => {
      createWrapper();

      expect(findAlert().props('dismissible')).toBe(true);
    });

    it('can be made non-dismissible', () => {
      createWrapper({ props: { dismissible: false } });

      expect(findAlert().props('dismissible')).toBe(false);
    });
  });

  describe('buttonVariant', () => {
    it('defaults to confirm', () => {
      createWrapper({ mountFn: mount });

      expect(findActionButton().props('variant')).toBe('confirm');
    });

    it('can be overridden', () => {
      createWrapper({ props: { buttonVariant: 'default' }, mountFn: mount });

      expect(findActionButton().props('variant')).toBe('default');
    });
  });

  describe('sticky', () => {
    it('is not sticky by default', () => {
      createWrapper();

      expect(findAlert().props('sticky')).toBe(false);
    });

    it('can be made sticky', () => {
      createWrapper({ props: { sticky: true } });

      expect(findAlert().props('sticky')).toBe(true);
    });
  });

  describe('openInNewTab', () => {
    it('does not open the link in a new tab by default', () => {
      createWrapper({ mountFn: mount });

      expect(findActionButton().attributes('target')).toBeUndefined();
    });

    it('opens the link in a new tab when enabled', () => {
      createWrapper({ props: { openInNewTab: true }, mountFn: mount });

      expect(findActionButton().attributes()).toMatchObject({
        href: 'identity/verification/path',
        target: '_blank',
      });
      expect(findActionButton().text()).toBe('Verify my account');
    });
  });
});
