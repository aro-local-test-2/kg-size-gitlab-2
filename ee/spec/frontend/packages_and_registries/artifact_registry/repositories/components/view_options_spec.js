import { GlDisclosureDropdown, GlDisclosureDropdownGroup, GlToggle } from '@gitlab/ui';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ViewOptions from 'ee/packages_and_registries/artifact_registry/repositories/components/view_options.vue';

describe('ArtifactRegistryViewOptions', () => {
  let wrapper;

  const columns = [
    { key: 'kind', label: 'Type' },
    { key: 'downloadsCount', label: 'Downloads' },
    { key: 'sizeBytes', label: 'Size' },
  ];

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findGroup = () => wrapper.findComponent(GlDisclosureDropdownGroup);
  const findGroupLabel = () => {
    const labelId = findGroup().find('ul').attributes('aria-labelledby');

    return findGroup().find(`#${labelId}`);
  };
  const findItem = (key) => wrapper.findByTestId(`column-item-${key}`);
  const findColumnToggles = () =>
    wrapper
      .findAll('[data-testid^="column-item-"]')
      .wrappers.map((item) => item.findComponent(GlToggle));
  const findColumnLabels = () => findColumnToggles().map((toggle) => toggle.props('label'));
  const findColumnValues = () => findColumnToggles().map((toggle) => toggle.props('value'));

  const createComponent = ({ props = {}, slots = {} } = {}) => {
    wrapper = mountExtended(ViewOptions, {
      propsData: { columns, ...props },
      slots,
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const toggleColumn = async (key) => {
    await findItem(key).find('button').trigger('click');
  };

  describe('when nothing is hidden', () => {
    beforeEach(() => createComponent());

    it('offers one switch per column, in the given order', () => {
      expect(findColumnLabels()).toEqual(['Type', 'Downloads', 'Size']);
    });

    it('groups the switches under a labelled section', () => {
      expect(findGroupLabel().text()).toBe('Columns');
    });

    it('renders every switch on', () => {
      expect(findColumnValues()).toEqual([true, true, true]);
    });

    it('adds the column to the hidden set when its switch is turned off', async () => {
      await toggleColumn('sizeBytes');

      expect(wrapper.emitted('input')).toEqual([[['sizeBytes']]]);
    });

    it('keeps the panel open across a change', () => {
      expect(findDropdown().props('autoClose')).toBe(false);
    });

    it('names itself for assistive technology without rendering the name beside the icon', () => {
      expect(findDropdown().props()).toMatchObject({
        toggleText: 'View options',
        textSrOnly: true,
        icon: 'preferences',
      });
    });

    it('renders its name as a tooltip', () => {
      expect(getBinding(findDropdown().element, 'gl-tooltip').value).toBe('View options');
    });
  });

  describe('when columns are hidden', () => {
    beforeEach(() => createComponent({ props: { hiddenColumns: ['kind', 'sizeBytes'] } }));

    it('renders their switches off, leaving the rest on', () => {
      expect(findColumnValues()).toEqual([false, true, false]);
    });

    it('removes the column from the hidden set when its switch is turned back on', async () => {
      await toggleColumn('sizeBytes');

      expect(wrapper.emitted('input')).toEqual([[['kind']]]);
    });
  });

  describe('when default slot content is given', () => {
    beforeEach(() =>
      createComponent({ slots: { default: '<div data-testid="extra-group">extra</div>' } }),
    );

    it('renders it inside the dropdown', () => {
      expect(findDropdown().find('[data-testid="extra-group"]').exists()).toBe(true);
    });
  });
});
