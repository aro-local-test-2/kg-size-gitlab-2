import { GlBadge, GlButton, GlFormInputGroup, GlToggle } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FlatUserCapControl from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/flat_user_cap_control.vue';

describe('CreditCapsFlatUserCapControl', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;

  const createComponent = ({ propsData = {} } = {}) => {
    wrapper = shallowMountExtended(FlatUserCapControl, { propsData });
  };

  const findRoot = () => wrapper.findByTestId('flat-user-cap-control');
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findToggle = () => wrapper.findComponent(GlToggle);
  const findInput = () => wrapper.findComponent(GlFormInputGroup);
  const findSaveButton = () => wrapper.findComponent(GlButton);
  const findForm = () => wrapper.find('form');

  describe('root element', () => {
    beforeEach(() => {
      createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
    });

    it('renders root with correct data-testid', () => {
      expect(findRoot().exists()).toBe(true);
    });
  });

  describe('badge', () => {
    describe('when flatUserCapEnabled is true', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
      });

      it('renders info badge', () => {
        expect(findBadge().attributes('variant')).toBe('info');
      });
    });

    describe('when flatUserCapEnabled is false', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: false } });
      });

      it('renders neutral badge', () => {
        expect(findBadge().attributes('variant')).toBe('neutral');
      });
    });
  });

  describe('toggle', () => {
    describe('when flatUserCapEnabled is true', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
      });

      it('has value true', () => {
        expect(findToggle().props('value')).toBe(true);
      });
    });

    describe('when flatUserCapEnabled is false', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: false } });
      });

      it('has value false', () => {
        expect(findToggle().props('value')).toBe(false);
      });
    });
  });

  describe('input', () => {
    describe('when flatUserCap is a positive number', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
      });

      it('displays the correct value', () => {
        expect(findInput().attributes('value')).toBe('500');
      });
    });

    describe('when flatUserCap is 0', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 0, flatUserCapEnabled: true } });
      });

      it('displays zero', () => {
        expect(findInput().attributes('value')).toBe('0');
      });
    });
  });

  describe('save button', () => {
    describe('when isSaving is false (default)', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
      });

      it('renders save button', () => {
        expect(findSaveButton().exists()).toBe(true);
      });

      it('is not in loading state', () => {
        expect(findSaveButton().props('loading')).toBe(false);
      });
    });

    describe('when isSaving is true', () => {
      beforeEach(() => {
        createComponent({
          propsData: { flatUserCap: 500, flatUserCapEnabled: true, isSaving: true },
        });
      });

      it('puts button in loading state', () => {
        expect(findSaveButton().props('loading')).toBe(true);
      });

      it('disables the input', () => {
        // Vue 3: disabled=false removes the attribute entirely (undefined); disabled=true renders as "disabled"
        expect(findInput().attributes('disabled')).toBeDefined();
        // Vue 2: disabled=false renders as the string "false"; disabled=true renders as "true"
        expect(findInput().attributes('disabled')).not.toBe('false');
      });

      it('disables the toggle', () => {
        expect(findToggle().props('disabled')).toBe(true);
      });
    });

    describe('when submitted', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
      });

      it('emits save with current draft values', async () => {
        await findForm().trigger('submit');

        expect(wrapper.emitted('save')).toEqual([[{ flatUserCap: 500, flatUserCapEnabled: true }]]);
      });
    });
  });

  describe('draft state', () => {
    describe('initialisation', () => {
      beforeEach(() => {
        createComponent({ propsData: { flatUserCap: 300, flatUserCapEnabled: false } });
      });

      it('initialises draft cap from prop', () => {
        expect(findInput().attributes('value')).toBe('300');
      });

      it('initialises draft enabled from prop', () => {
        expect(findToggle().props('value')).toBe(false);
      });
    });

    describe('when props update after a successful save', () => {
      beforeEach(async () => {
        createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
        await wrapper.setProps({ flatUserCap: 200, flatUserCapEnabled: false });
        await nextTick();
      });

      it('syncs draft cap to updated prop', () => {
        expect(findInput().attributes('value')).toBe('200');
      });

      it('syncs draft enabled to updated prop', () => {
        expect(findToggle().props('value')).toBe(false);
      });
    });
  });

  describe('save emit payload', () => {
    beforeEach(() => {
      createComponent({ propsData: { flatUserCap: 500, flatUserCapEnabled: true } });
    });

    it('emits save with flatUserCap and flatUserCapEnabled', async () => {
      await findForm().trigger('submit');

      const [payload] = wrapper.emitted('save')[0];
      expect(payload).toEqual({ flatUserCap: 500, flatUserCapEnabled: true });
    });
  });
});
