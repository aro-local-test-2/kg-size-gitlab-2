import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskStaleWarning from 'ee/vue_merge_request_widget/widgets/risk_classification/components/risk_stale_warning.vue';

describe('RiskStaleWarning', () => {
  let wrapper;

  beforeEach(() => {
    wrapper = shallowMountExtended(RiskStaleWarning);
  });

  it('says the classification reflects an earlier version of the changes', () => {
    expect(wrapper.findByTestId('risk-stale-warning').text()).toBe(
      'New commits were pushed after this assessment. It reflects an earlier version of the changes.',
    );
  });
});
