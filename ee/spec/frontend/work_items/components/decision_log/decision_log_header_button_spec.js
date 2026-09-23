import { GlButton } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import DecisionLogHeaderButton from 'ee/work_items/components/decision_log/decision_log_header_button.vue';

describe('DecisionLogHeaderButton', () => {
  let wrapper;

  const createComponent = ({ count = 3, isPanelOpen = false } = {}) => {
    wrapper = mountExtended(DecisionLogHeaderButton, {
      propsData: { count, isPanelOpen },
    });
  };

  // The component's root element is the button, so it is out of reach of the DOM queries.
  const findButton = () => wrapper.findComponent(GlButton);
  const findCount = () => wrapper.findByTestId('decision-log-count');

  describe.each([1, 3])('with %i decisions', (count) => {
    beforeEach(() => {
      createComponent({ count });
    });

    it('shows the count', () => {
      expect(findCount().text()).toBe(String(count));
    });
  });

  describe('with no decisions', () => {
    beforeEach(() => {
      createComponent({ count: 0 });
    });

    it('shows no count', () => {
      expect(findCount().exists()).toBe(false);
    });

    describe('when the button is clicked', () => {
      beforeEach(() => {
        findButton().trigger('click');
      });

      it('still opens the panel, because that is where a decision gets created', () => {
        expect(wrapper.emitted('open')).toHaveLength(1);
      });
    });
  });

  describe('when the panel is closed', () => {
    beforeEach(() => {
      createComponent({ isPanelOpen: false });
    });

    it('is not marked as pressed', () => {
      expect(findButton().attributes('aria-pressed')).toBe('false');
    });

    describe('when the button is clicked', () => {
      beforeEach(() => {
        findButton().trigger('click');
      });

      it('asks to open the panel', () => {
        expect(wrapper.emitted('open')).toHaveLength(1);
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });
  });

  describe('when the panel is open', () => {
    beforeEach(() => {
      createComponent({ isPanelOpen: true });
    });

    it('is marked as pressed', () => {
      expect(findButton().attributes('aria-pressed')).toBe('true');
    });

    describe('when the button is clicked', () => {
      beforeEach(() => {
        findButton().trigger('click');
      });

      it('asks to close the panel', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
        expect(wrapper.emitted('open')).toBeUndefined();
      });
    });
  });
});
