import { GlCollapse } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import DecisionLogContext from 'ee/work_items/components/decision_log/decision_log_context.vue';
import { mockDecision } from './mock_data';

describe('DecisionLogContext', () => {
  let wrapper;

  const context = mockDecision.description;
  const rationale = mockDecision.resolutionRationale;

  const createComponent = (props = {}) => {
    wrapper = mountExtended(DecisionLogContext, {
      propsData: { context, rationale, ...props },
    });
  };

  const findContext = () => wrapper.findByTestId('decision-context');
  const findWhy = () => wrapper.findByTestId('decision-why');
  const findToggle = () => wrapper.findComponentByTestId('decision-context-toggle');
  const findCollapse = () => wrapper.findComponent(GlCollapse);

  describe('by default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('keeps the blocks collapsed, so a long log stays scannable', () => {
      expect(findCollapse().props('visible')).toBe(false);
      expect(findToggle().text()).toBe('Show context');
    });

    it('expands the blocks when the toggle is clicked', async () => {
      await findToggle().vm.$emit('click');

      expect(findCollapse().props('visible')).toBe(true);
      expect(findContext().text()).toBe(context);
      expect(findWhy().text()).toBe(rationale);
      expect(findToggle().text()).toBe('Hide context');
    });
  });

  describe('when nobody argued for the decision', () => {
    beforeEach(() => {
      createComponent({ rationale: null });
    });

    it('omits the why block', () => {
      expect(findContext().exists()).toBe(true);
      expect(findWhy().exists()).toBe(false);
    });
  });

  describe('when there is no context behind the decision', () => {
    beforeEach(() => {
      createComponent({ context: null });
    });

    it('omits the context block', () => {
      expect(findContext().exists()).toBe(false);
      expect(findWhy().exists()).toBe(true);
    });
  });
});
