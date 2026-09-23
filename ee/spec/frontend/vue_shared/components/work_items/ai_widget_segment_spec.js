import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AiWidgetSegment from 'ee/vue_shared/components/work_items/ai_widget_segment.vue';

describe('AiWidgetSegment', () => {
  let wrapper;

  const createComponent = ({ slots = {} } = {}) => {
    wrapper = shallowMountExtended(AiWidgetSegment, {
      propsData: { label: 'Workplan' },
      slots,
    });
  };

  const findLabelAppend = () => wrapper.findByTestId('label-append');

  describe('by default', () => {
    beforeEach(() => {
      createComponent({ slots: { default: '<span data-testid="value">Ready</span>' } });
    });

    it('shows the label', () => {
      expect(wrapper.text()).toContain('Workplan');
    });

    it('shows the value from the default slot', () => {
      expect(wrapper.findByTestId('value').text()).toBe('Ready');
    });

    it('renders nothing next to the label', () => {
      expect(findLabelAppend().exists()).toBe(false);
    });
  });

  describe('when the label-append slot is filled', () => {
    beforeEach(() => {
      createComponent({
        slots: { 'label-append': '<span data-testid="label-append">?</span>' },
      });
    });

    it('renders the slot content next to the label', () => {
      expect(findLabelAppend().exists()).toBe(true);
    });
  });
});
