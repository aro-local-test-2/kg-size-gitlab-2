import { GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FunctionalVerificationCheck from 'ee/ai/settings/components/functional_verifications/functional_verification_check.vue';
import FunctionalVerificationStatusBadge from 'ee/ai/settings/components/functional_verifications/status_badge.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  FUNCTIONAL_VERIFICATION_STATUS,
  MODEL_PROVIDERS,
} from 'ee/ai/settings/components/functional_verifications/constants';

describe('FunctionalVerificationCheck', () => {
  let wrapper;

  const defaultProps = {
    name: 'Agentic chat',
    description: 'Verifies the agentic chat request flow end to end.',
    status: FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN,
    model: { name: 'Mixtral 8x7B', provider: MODEL_PROVIDERS.SELF_HOSTED },
  };

  const findStatusBadge = () => wrapper.findComponent(FunctionalVerificationStatusBadge);
  const findRunButton = () => wrapper.findComponentByTestId('run-check-button');
  const findCheckName = () => wrapper.findByTestId('check-name');
  const findCheckModel = () => wrapper.findByTestId('check-model');
  const findCheckError = () => wrapper.findByTestId('check-error');
  const findConfigureLink = () => wrapper.findComponent(GlLink);
  const findTimeAgoTooltip = () => wrapper.findComponent(TimeAgoTooltip);

  const createComponent = (props = {}, provide = {}) => {
    wrapper = shallowMountExtended(FunctionalVerificationCheck, {
      propsData: { ...defaultProps, ...props },
      provide: { duoInstanceModelSelectionPath: '', ...provide },
      stubs: { GlSprintf },
    });
  };

  it('renders the name and description', () => {
    createComponent();

    expect(findCheckName().text()).toBe(defaultProps.name);
    expect(wrapper.text()).toContain(defaultProps.description);
  });

  it('passes the status down to the status badge', () => {
    createComponent({ status: FUNCTIONAL_VERIFICATION_STATUS.PASSED });

    expect(findStatusBadge().props('status')).toBe(FUNCTIONAL_VERIFICATION_STATUS.PASSED);
  });

  describe('model text', () => {
    describe('when the model is self-hosted', () => {
      beforeEach(() => {
        createComponent({ model: { name: 'Mixtral 8x7B', provider: MODEL_PROVIDERS.SELF_HOSTED } });
      });

      it('renders the self-hosted format', () => {
        expect(findCheckModel().text()).toBe('Mixtral 8x7B (self-hosted)');
      });
    });

    describe('when the model is GitLab-managed', () => {
      beforeEach(() => {
        createComponent({ model: { name: '', provider: MODEL_PROVIDERS.GITLAB_MANAGED } });
      });

      it('renders a generic GitLab-managed label', () => {
        expect(findCheckModel().text()).toBe('GitLab-managed model');
      });
    });

    describe('when the model provider is disabled', () => {
      beforeEach(() => {
        createComponent({ model: { name: '', provider: MODEL_PROVIDERS.DISABLED } });
      });

      it('renders a disabled label', () => {
        expect(findCheckModel().text()).toBe('Disabled');
      });
    });

    describe('when there is no model', () => {
      beforeEach(() => {
        createComponent({ model: null });
      });

      it('does not render the model line', () => {
        expect(findCheckModel().exists()).toBe(false);
      });
    });
  });

  describe('configure link', () => {
    describe('when duoInstanceModelSelectionPath is absent', () => {
      beforeEach(() => {
        createComponent();
      });

      it('does not render the link', () => {
        expect(findConfigureLink().exists()).toBe(false);
      });
    });

    describe('when duoInstanceModelSelectionPath is provided', () => {
      beforeEach(() => {
        createComponent({}, { duoInstanceModelSelectionPath: '/admin/gitlab_duo/model_selection' });
      });

      it('renders the link pointing at the features route', () => {
        expect(findConfigureLink().attributes('href')).toBe(
          '/admin/gitlab_duo/model_selection/features',
        );
      });

      describe('and the check is disabled', () => {
        beforeEach(() => {
          createComponent(
            { disabled: true },
            { duoInstanceModelSelectionPath: '/admin/gitlab_duo/model_selection' },
          );
        });

        it('disables the link', () => {
          expect(findConfigureLink().props('disabled')).toBe(true);
          expect(findConfigureLink().classes()).toEqual(
            expect.arrayContaining(['gl-cursor-not-allowed', 'hover:gl-cursor-not-allowed']),
          );
        });
      });
    });
  });

  describe('last run time', () => {
    it('is not rendered when lastRunAt is absent', () => {
      createComponent();

      expect(findTimeAgoTooltip().exists()).toBe(false);
    });

    it('is rendered when lastRunAt is provided', () => {
      createComponent({
        status: FUNCTIONAL_VERIFICATION_STATUS.PASSED,
        lastRunAt: '2026-09-04T12:00:00Z',
      });

      expect(findTimeAgoTooltip().props('time')).toBe('2026-09-04T12:00:00Z');
    });
  });

  describe('error text', () => {
    it('is not rendered when there is no error text', () => {
      createComponent({ status: FUNCTIONAL_VERIFICATION_STATUS.FAILED, errorText: '' });

      expect(findCheckError().exists()).toBe(false);
    });

    it('is rendered when the status is failed and there is error text', () => {
      createComponent({
        status: FUNCTIONAL_VERIFICATION_STATUS.FAILED,
        errorText: 'websocket/proxy error, code 1006',
      });

      expect(findCheckError().text()).toBe('websocket/proxy error, code 1006');
    });

    it('is rendered even when the status is not failed, e.g. a load error', () => {
      createComponent({
        status: FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN,
        errorText: 'Failed to load last run details.',
      });

      expect(findCheckError().text()).toBe('Failed to load last run details.');
    });
  });

  describe('run button', () => {
    it('is enabled by default', () => {
      createComponent();

      expect(findRunButton().attributes('disabled')).toBeUndefined();
    });

    it('is disabled when the check is disabled', () => {
      createComponent({ disabled: true });

      expect(findRunButton().attributes('disabled')).toBeDefined();
    });

    it('is disabled while the check is running', () => {
      createComponent({ status: FUNCTIONAL_VERIFICATION_STATUS.RUNNING });

      expect(findRunButton().attributes('disabled')).toBeDefined();
    });

    it('emits run when clicked', () => {
      createComponent();

      findRunButton().vm.$emit('click');

      expect(wrapper.emitted('run')).toHaveLength(1);
    });

    it('includes the check name in its aria-label', () => {
      createComponent({ name: 'Agentic chat' });

      expect(findRunButton().attributes('aria-label')).toBe('Run Agentic chat verification');
    });
  });

  it('dims the row when disabled', () => {
    createComponent({ disabled: true });

    expect(wrapper.find('.gl-opacity-5').exists()).toBe(true);
  });

  it('renders the status badge when not disabled', () => {
    createComponent({ disabled: false });

    expect(findStatusBadge().exists()).toBe(true);
  });

  it('does not render the status badge when disabled', () => {
    createComponent({ disabled: true });

    expect(findStatusBadge().exists()).toBe(false);
  });
});
