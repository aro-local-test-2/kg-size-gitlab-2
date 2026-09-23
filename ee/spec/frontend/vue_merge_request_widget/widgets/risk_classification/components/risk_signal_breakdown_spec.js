import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskSignalBreakdown from 'ee/vue_merge_request_widget/widgets/risk_classification/components/risk_signal_breakdown.vue';

describe('RiskSignalBreakdown', () => {
  let wrapper;

  const contributions = [
    {
      signal: 'touches_auth',
      label: 'Authentication or authorization logic',
      detail: 'touches_auth: true (lib/auth.rb:44)',
    },
    { signal: 'diff_shape.churn', label: 'Size of change', detail: null },
  ];

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(RiskSignalBreakdown, {
      propsData: { contributions, ...props },
      // Rendered for real so the interpolated missing signal names appear in the output.
      stubs: { GlSprintf },
    });
  };

  const findBreakdown = () => wrapper.findByTestId('risk-signal-breakdown');
  const findLowConfidence = () => wrapper.findByTestId('risk-low-confidence');

  describe('default', () => {
    beforeEach(() => createComponent());

    it('renders a heading', () => {
      expect(wrapper.find('h5').text()).toBe('What contributed to this score');
    });

    it('lists every contribution with its label and evidence', () => {
      const rows = findBreakdown().findAll('li');

      expect(rows).toHaveLength(2);
      expect(rows.at(0).text()).toContain('Authentication or authorization logic');
      expect(rows.at(0).text()).toContain('touches_auth: true (lib/auth.rb:44)');
      expect(rows.at(1).text()).toBe('Size of change');
    });

    it('does not show a low confidence notice', () => {
      expect(findLowConfidence().exists()).toBe(false);
    });

    it('does not show a weight, because there are no user facing weights', () => {
      expect(wrapper.text()).not.toContain('weight');
      expect(wrapper.text()).not.toContain('Weight');
    });
  });

  describe('when the server sent no label for a signal', () => {
    beforeEach(() =>
      createComponent({ contributions: [{ signal: 'coverage', label: null, detail: null }] }),
    );

    it('falls back to the signal name', () => {
      expect(findBreakdown().findAll('li').at(0).text()).toBe('coverage');
    });
  });

  describe('when confidence is low', () => {
    beforeEach(() =>
      createComponent({
        isLowConfidence: true,
        missingSignalsText: 'test coverage, commit authorship',
      }),
    );

    it('names what could not be measured', () => {
      expect(findLowConfidence().text()).toBe(
        'Based on a partial picture: test coverage, commit authorship could not be measured.',
      );
    });
  });

  describe('when confidence is low but nothing can be named', () => {
    beforeEach(() => createComponent({ isLowConfidence: true, missingSignalsText: '' }));

    it('drops the notice rather than naming an empty list', () => {
      expect(findLowConfidence().exists()).toBe(false);
    });
  });
});
