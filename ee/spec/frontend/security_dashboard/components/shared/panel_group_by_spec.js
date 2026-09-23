import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PanelGroupBy from 'ee/security_dashboard/components/shared/panel_group_by.vue';

describe('OverTimeGroupBy', () => {
  let wrapper;

  const createComponent = (props = { value: 'severity' }) => {
    wrapper = shallowMountExtended(PanelGroupBy, {
      propsData: {
        ...props,
      },
    });
  };

  const findSeverityButton = () => wrapper.findComponentByTestId('severity-button');
  const findReportTypeButton = () => wrapper.findComponentByTestId('reportType-button');
  const findAllButton = () => wrapper.findComponentByTestId('all-button');

  it('renders severity group by button', () => {
    createComponent();
    expect(findSeverityButton().text()).toBe('Severity');
  });

  it('renders reportType group by button', () => {
    createComponent();
    expect(findReportTypeButton().text()).toBe('Report Type');
  });

  it('does not render the "All" group by button by default', () => {
    createComponent();
    expect(findAllButton().exists()).toBe(false);
  });

  describe('when showAll is true', () => {
    it('renders the "All" group by button', () => {
      createComponent({ value: 'all', showAll: true });
      expect(findAllButton().text()).toBe('All');
    });

    it('marks the "All" button as selected when its value is passed', () => {
      createComponent({ value: 'all', showAll: true });

      expect(findAllButton().props('selected')).toBe(true);
      expect(findSeverityButton().props('selected')).toBe(false);
    });

    it('emits input event with "all" when the button is clicked', () => {
      createComponent({ value: 'severity', showAll: true });
      findAllButton().vm.$emit('click');

      expect(wrapper.emitted('input')).toMatchObject([['all']]);
    });
  });

  it.each([
    ['severity', findSeverityButton, findReportTypeButton],
    ['reportType', findReportTypeButton, findSeverityButton],
  ])(
    'when %p value is passed, set correct button as selected',
    (value, selectedFn, unselectedFn) => {
      createComponent({ value });

      expect(selectedFn().props('selected')).toBe(true);
      expect(unselectedFn().props('selected')).toBe(false);
    },
  );

  it.each([
    ['severity', findSeverityButton],
    ['reportType', findReportTypeButton],
  ])('when %p button is clicked, emit correct event', (value, findFn) => {
    createComponent({ value });
    findFn().vm.$emit('click');
    expect(wrapper.emitted('input')).toMatchObject([[value]]);
  });
});
