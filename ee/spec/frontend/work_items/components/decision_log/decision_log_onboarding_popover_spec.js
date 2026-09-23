import { nextTick } from 'vue';
import { GlLink, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DecisionLogOnboardingPopover from 'ee/work_items/components/decision_log/decision_log_onboarding_popover.vue';

describe('DecisionLogOnboardingPopover', () => {
  let wrapper;
  let notifyResize;
  let disconnect;

  const target = 'decision-log-button-1';
  const settleDelay = 300;

  const findPopover = () => wrapper.findComponent(GlPopover);
  const findLink = () => wrapper.findComponent(GlLink);
  const isPopoverShown = () => findPopover().props('show');

  const renderActionsRow = () => {
    document.body.innerHTML = `
      <div class="js-panel-actions-portal-target"><button id="${target}"></button></div>
    `;
  };

  const createComponent = ({ hasOpenedDecisionLog = false } = {}) => {
    wrapper = shallowMountExtended(DecisionLogOnboardingPopover, {
      propsData: { target, hasOpenedDecisionLog },
    });
  };

  beforeEach(() => {
    disconnect = jest.fn();
    notifyResize = null;
    jest.spyOn(global, 'ResizeObserver').mockImplementation(function mockObserver(callback) {
      notifyResize = callback;
      this.observe = jest.fn();
      this.disconnect = disconnect;
    });
    renderActionsRow();
  });

  describe('when it is rendered', () => {
    beforeEach(() => {
      createComponent();
      jest.advanceTimersByTime(settleDelay);
    });

    it('anchors itself to the button it is introducing', () => {
      expect(findPopover().props('target')).toBe('decision-log-button-1');
      expect(findPopover().props()).toMatchObject({
        placement: 'bottom',
        showCloseButton: true,
        triggers: 'manual',
      });
    });

    it('says what the log is for and that decisions can be recorded by hand', () => {
      expect(wrapper.text()).toContain(
        'Keep a record of decisions and the reasoning behind them. You can add a decision at any time, and GitLab Duo can also capture decisions during planning.',
      );
    });

    it('points at the documentation', () => {
      expect(findLink().attributes('href')).toBe('/help/user/work_items/workplan#decision-log');
      expect(findLink().text()).toBe('Learn more about the decision log');
    });
  });

  describe('while the header action row is still settling', () => {
    beforeEach(() => {
      createComponent();
    });

    it('does not position itself yet', () => {
      expect(isPopoverShown()).toBe(false);
    });

    it('keeps waiting while the row is still changing size', () => {
      jest.advanceTimersByTime(settleDelay - 1);
      notifyResize();
      jest.advanceTimersByTime(settleDelay - 1);

      expect(isPopoverShown()).toBe(false);
    });
  });

  describe('when the header action row has stopped changing size', () => {
    beforeEach(() => {
      createComponent();
      notifyResize();
      jest.advanceTimersByTime(settleDelay);
    });

    it('positions itself against the settled button', () => {
      expect(isPopoverShown()).toBe(true);
    });

    it('stops watching the row', () => {
      expect(disconnect).toHaveBeenCalled();
    });
  });

  describe('when the button is not inside a header action row', () => {
    beforeEach(() => {
      document.body.innerHTML = `<button id="${target}"></button>`;
      createComponent();
    });

    it('still shows itself', async () => {
      jest.advanceTimersByTime(settleDelay);
      await nextTick();

      expect(isPopoverShown()).toBe(true);
    });
  });

  describe('when it is destroyed before the row settles', () => {
    beforeEach(() => {
      createComponent();
      wrapper.destroy();
    });

    it('stops watching the row', () => {
      expect(disconnect).toHaveBeenCalled();
    });
  });

  describe('when the user closes the popover', () => {
    beforeEach(() => {
      createComponent();
      findPopover().vm.$emit('close-button-clicked');
    });

    it('asks to be dismissed for good', () => {
      expect(wrapper.emitted('dismiss')).toEqual([[]]);
    });
  });

  describe('when the user has opened the decision log', () => {
    beforeEach(() => {
      createComponent({ hasOpenedDecisionLog: true });
    });

    it('treats that as acknowledgement and asks to be dismissed', () => {
      expect(wrapper.emitted('dismiss')).toEqual([[]]);
    });

    it('does not show itself over the open log', () => {
      expect(findPopover().exists()).toBe(false);
    });
  });
});
