import { GlButton } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import BatchUpdateButton from 'ee/ai/shared/feature_settings/batch_update_button.vue';

describe('BatchUpdateButton', () => {
  let wrapper;

  const tooltipTitle = 'Apply to all Code Suggestions sub-features';

  const createComponent = (props = {}) => {
    wrapper = mountExtended(BatchUpdateButton, {
      propsData: {
        tooltipTitle,
        ...props,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
    });
  };

  const findBatchUpdateButton = () => wrapper.findComponent(BatchUpdateButton);
  const findBatchUpdateButtonTooltip = () =>
    getBinding(wrapper.findByTestId('model-batch-assignment-tooltip').element, 'gl-tooltip');

  beforeEach(() => {
    createComponent();
  });

  it('renders the component', () => {
    expect(findBatchUpdateButton().props()).toMatchObject({
      tooltipTitle,
      disabled: false,
    });
  });

  it('displays a tooltip title', () => {
    expect(findBatchUpdateButtonTooltip().value.title).toBe(
      'Apply to all Code Suggestions sub-features',
    );
    expect(findBatchUpdateButtonTooltip().value.boundary).toBe('viewport');
  });

  it('does not emit batch update event when button is disabled', () => {
    createComponent({ disabled: true });

    const button = findBatchUpdateButton().findComponent(GlButton);
    button.trigger('click');

    expect(wrapper.emitted('batch-update')).toBeUndefined();
  });

  it('triggers onClick callback when the button is clicked', () => {
    const button = findBatchUpdateButton().findComponent(GlButton);
    button.trigger('click');

    expect(wrapper.emitted('batch-update')).toHaveLength(1);
  });
});
