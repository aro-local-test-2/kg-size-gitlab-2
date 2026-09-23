import { GlToggle } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import DisplayOptions from 'ee/security_inventory/components/display_options.vue';
import { TOGGLEABLE_COLUMNS } from 'ee/security_inventory/constants';

describe('DisplayOptions', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(DisplayOptions, {
      propsData: {
        columns: TOGGLEABLE_COLUMNS,
        ...props,
      },
    });
  };

  const findButton = () => wrapper.findComponentByTestId('display-options-button');
  const findDrawer = () => wrapper.findComponentByTestId('display-options-drawer');
  const findColumnToggles = () => wrapper.findAllComponents(GlToggle);
  const findColumnToggle = (key) => wrapper.findComponentByTestId(`column-toggle-${key}`);

  beforeEach(() => {
    createComponent();
  });

  it('renders a closed drawer and a trigger button', () => {
    expect(findButton().text()).toBe('Display');
    expect(findButton().props('selected')).toBe(false);
    expect(findDrawer().props('open')).toBe(false);
  });

  describe('when the button is clicked', () => {
    beforeEach(async () => {
      await findButton().vm.$emit('click');
    });

    it('opens the drawer', () => {
      expect(findDrawer().props('open')).toBe(true);
    });

    it('offers a toggle for every column it was given', () => {
      expect(findColumnToggles().wrappers.map((toggle) => toggle.text())).toEqual([
        'Vulnerabilities',
        'Tool coverage',
        'Security attributes',
      ]);
      expect(findColumnToggle('vulnerabilities').props('value')).toBe(true);
    });

    it('emits the column as hidden when a toggle is switched off', async () => {
      await findColumnToggle('vulnerabilities').vm.$emit('change');

      expect(wrapper.emitted('input')).toEqual([[['vulnerabilities']]]);
    });

    it('closes the drawer when it is dismissed', async () => {
      await findDrawer().vm.$emit('close');

      expect(findDrawer().props('open')).toBe(false);
      expect(findButton().props('selected')).toBe(false);
    });
  });

  describe('when a column is already hidden', () => {
    beforeEach(async () => {
      createComponent({ props: { hiddenColumns: ['vulnerabilities'] } });
      await findButton().vm.$emit('click');
    });

    it('shows that column as toggled off', () => {
      expect(findColumnToggle('vulnerabilities').props('value')).toBe(false);
      expect(findColumnToggle('toolCoverage').props('value')).toBe(true);
    });

    it('emits an empty list when the toggle is switched back on', async () => {
      await findColumnToggle('vulnerabilities').vm.$emit('change');

      expect(wrapper.emitted('input')).toEqual([[[]]]);
    });
  });
});
