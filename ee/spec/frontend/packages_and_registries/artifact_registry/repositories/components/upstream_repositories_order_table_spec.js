import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import UpstreamRepositoriesOrderTable from 'ee/packages_and_registries/artifact_registry/repositories/components/upstream_repositories_order_table.vue';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import { BASE_PATH, mockUpstreamSources } from '../../mock_data';

describe('ArtifactRegistryUpstreamRepositoriesOrderTable', () => {
  let wrapper;

  const findHeaders = () => wrapper.findAll('thead th');
  const findRows = () => wrapper.findAll('tbody tr');
  const findRow = (index) => findRows().at(index);
  const findNames = () =>
    wrapper.findAllByTestId('source-name').wrappers.map((cell) => cell.text());
  const findKinds = () =>
    wrapper.findAllByTestId('source-kind').wrappers.map((cell) => cell.text());
  const findUpArrow = (index) => findRow(index).find('[data-testid="move-source-up"]');
  const findDownArrow = (index) => findRow(index).find('[data-testid="move-source-down"]');
  const findRemove = (index) => findRow(index).find('[data-testid="remove-source"]');
  const findEdit = (index) => findRow(index).find('[data-testid="edit-source"]');
  const findJumpItems = (index) =>
    findRow(index)
      .findAllComponents(GlDisclosureDropdownItem)
      .wrappers.map((item) => item.props('item'));
  const findJumpItem = (index, text) => findJumpItems(index).find((item) => item.text === text);

  const createComponent = ({ sources = mockUpstreamSources } = {}) => {
    wrapper = mountExtended(UpstreamRepositoriesOrderTable, {
      router: createRouter(BASE_PATH),
      propsData: { sources },
    });
  };

  describe('the columns', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders Order, Repository, Type, Size, and Actions', () => {
      expect(findHeaders().wrappers.map((header) => header.text())).toEqual([
        'Order',
        'Repository',
        'Type',
        'Size',
        'Actions',
      ]);
    });

    it('offers no sort control, because the order carries meaning', () => {
      expect(wrapper.findAll('th[aria-sort]')).toHaveLength(0);
    });
  });

  describe('the rows', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders one row per source, in the order it was given them', () => {
      expect(findRows()).toHaveLength(3);
      expect(findNames()).toEqual([
        'maven-central-proxy',
        'payments-releases',
        'platform-snapshots',
      ]);
    });

    it('renders the kind as a word rather than as its enum value', () => {
      expect(findKinds()).toEqual(['Remote', 'Hosted', 'Hosted']);
    });

    it('renders the URL only on the row that carries one', () => {
      const urls = wrapper.findAllByTestId('source-url');

      expect(urls).toHaveLength(1);
      expect(urls.at(0).text()).toBe('https://repo.maven.apache.org/maven2');
    });

    it('renders a human size only on the rows that carry one', () => {
      const sizes = wrapper.findAllByTestId('source-size');

      expect(sizes.wrappers.map((cell) => cell.text())).toEqual(['2.00 KiB', '1.00 MiB']);
    });

    it('offers no drag handle and no cache action', () => {
      expect(wrapper.findByTestId('drag-source').exists()).toBe(false);
      expect(wrapper.findByTestId('clear-source-cache').exists()).toBe(false);
    });

    it('links each row to that repository\u2019s own edit page', () => {
      expect(findEdit(0).attributes('aria-label')).toBe('Edit maven-central-proxy');
      expect(findEdit(0).attributes('href')).toBe(`${BASE_PATH}/maven-central-proxy/edit`);
    });
  });

  describe('the arrow controls', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the source each arrow moves', () => {
      expect(findUpArrow(0).attributes('aria-label')).toBe('Move maven-central-proxy up');
      expect(findDownArrow(0).attributes('aria-label')).toBe('Move maven-central-proxy down');
    });

    it.each([
      [0, 'true'],
      [1, undefined],
      [2, undefined],
    ])('marks the up arrow on row %i disabled: %s', (index, disabled) => {
      expect(findUpArrow(index).attributes('aria-disabled')).toBe(disabled);
    });

    it.each([
      [0, undefined],
      [1, undefined],
      [2, 'true'],
    ])('marks the down arrow on row %i disabled: %s', (index, disabled) => {
      expect(findDownArrow(index).attributes('aria-disabled')).toBe(disabled);
    });

    it('leaves a disabled arrow in the tab order, so it is conveyed rather than discovered', () => {
      expect(findUpArrow(0).element.tagName).toBe('BUTTON');
      expect(findUpArrow(0).attributes('disabled')).toBeUndefined();
      expect(findUpArrow(0).attributes('tabindex')).toBeUndefined();
    });

    it.each([
      [1, { from: 1, to: 0 }],
      [2, { from: 2, to: 1 }],
    ])('moves row %i one position up', async (index, expected) => {
      await findUpArrow(index).trigger('click');

      expect(wrapper.emitted('move')).toEqual([[expected]]);
    });

    it.each([
      [0, { from: 0, to: 1 }],
      [1, { from: 1, to: 2 }],
    ])('moves row %i one position down', async (index, expected) => {
      await findDownArrow(index).trigger('click');

      expect(wrapper.emitted('move')).toEqual([[expected]]);
    });
  });

  describe('the row menu', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the source in the toggle, because the menu repeats once per row', () => {
      expect(findRow(1).findComponent(GlDisclosureDropdown).props('toggleText')).toBe(
        'More actions for payments-releases',
      );
    });

    it.each([
      [0, ['Move to end of list']],
      [1, ['Move to start of list', 'Move to end of list']],
      [2, ['Move to start of list']],
    ])('offers row %i only the jumps its position allows', (index, expected) => {
      expect(findJumpItems(index).map(({ text }) => text)).toEqual(expected);
    });

    it.each([1, 2])('jumps row %i to the start in one move', (index) => {
      findJumpItem(index, 'Move to start of list').action();

      expect(wrapper.emitted('move')).toEqual([[{ from: index, to: 0 }]]);
    });

    it.each([0, 1])('jumps row %i to the end in one move', (index) => {
      findJumpItem(index, 'Move to end of list').action();

      expect(wrapper.emitted('move')).toEqual([[{ from: index, to: 2 }]]);
    });

    describe('when a single source leaves no jump to offer', () => {
      beforeEach(() => {
        createComponent({ sources: [mockUpstreamSources[0]] });
      });

      it('renders no menu at all, rather than an empty one', () => {
        expect(wrapper.findComponent(GlDisclosureDropdown).exists()).toBe(false);
      });

      it('still offers the remove action, and disables both arrows', () => {
        expect(findRemove(0).exists()).toBe(true);
        expect(findUpArrow(0).attributes('aria-disabled')).toBe('true');
        expect(findDownArrow(0).attributes('aria-disabled')).toBe('true');
      });
    });
  });

  describe('the remove action', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the source it removes', () => {
      expect(findRemove(2).attributes('aria-label')).toBe('Remove platform-snapshots');
    });

    it.each([0, 1, 2])('emits the index of row %i', async (index) => {
      await findRemove(index).trigger('click');

      expect(wrapper.emitted('remove')).toEqual([[index]]);
    });
  });

  describe('keyboard reachability', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders every row control as a button rather than a clickable element', () => {
      const controls = [
        ...wrapper.findAllByTestId('move-source-up').wrappers,
        ...wrapper.findAllByTestId('move-source-down').wrappers,
        ...wrapper.findAllByTestId('remove-source').wrappers,
      ];

      expect(controls).toHaveLength(9);
      expect(controls.map((control) => control.element.tagName)).toEqual(
        Array.from({ length: 9 }, () => 'BUTTON'),
      );
    });

    it('renders every jump item as a button', () => {
      const items = wrapper.findAllComponents(GlDisclosureDropdownItem);

      expect(items).toHaveLength(4);
      expect(items.wrappers.every((item) => item.find('button').exists())).toBe(true);
    });
  });
});
