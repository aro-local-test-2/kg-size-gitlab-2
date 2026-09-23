import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskRationale from 'ee/vue_merge_request_widget/widgets/risk_classification/components/risk_rationale.vue';

describe('RiskRationale', () => {
  let wrapper;

  const rationale =
    'Touches authentication logic without adding new test coverage, which drives the score.';

  beforeEach(() => {
    wrapper = shallowMountExtended(RiskRationale, { propsData: { rationale } });
  });

  it('renders a heading', () => {
    expect(wrapper.find('h5').text()).toBe('Rationale');
  });

  it('renders the rationale', () => {
    expect(wrapper.findByTestId('risk-rationale').text()).toBe(rationale);
  });
});
