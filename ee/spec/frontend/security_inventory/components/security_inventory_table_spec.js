import { nextTick } from 'vue';
import { GlTableLite, GlSkeletonLoader, GlFormCheckbox } from '@gitlab/ui';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import SecurityInventoryTable from 'ee/security_inventory/components/security_inventory_table.vue';
import NameCell from 'ee/security_inventory/components/name_cell.vue';
import VulnerabilityCell from 'ee/security_inventory/components/vulnerability_cell.vue';
import ToolCoverageCell from 'ee/security_inventory/components/tool_coverage_cell.vue';
import ActionCell from 'ee/security_inventory/components/action_cell.vue';
import AttributesCell from 'ee/security_inventory/components/attributes_cell.vue';
import CheckboxCell from 'ee/security_inventory/components/checkbox_cell.vue';
import {
  ACTION_TYPE_BULK_EDIT_SCANNERS,
  ACTION_TYPE_BULK_EDIT_ATTRIBUTES,
} from 'ee/security_inventory/constants';
import { subgroupsAndProjects } from '../mock_data';

const mockProject = subgroupsAndProjects.data.group.projects.nodes[0];
const anotherProject = subgroupsAndProjects.data.group.projects.nodes[1];
const mockGroup = subgroupsAndProjects.data.group.descendantGroups.nodes[0];
const items = [mockGroup, mockProject];
const allColumnKeys = ['name', 'vulnerabilities', 'toolCoverage', 'securityAttributes', 'actions'];

describe('SecurityInventoryTable', () => {
  let wrapper;
  let openDrawerSpy;

  const createComponentFactory = ({ mountFn = shallowMountExtended } = {}) => {
    return ({
      props = {},
      stubs = {},
      provide = {
        groupFullPath: 'path/to/group',
        canManageAttributes: false,
        canReadAttributes: true,
        canApplyProfiles: false,
      },
    } = {}) => {
      wrapper = mountFn(SecurityInventoryTable, {
        propsData: {
          items,
          currentPath: 'path/to/group',
          ...props,
        },
        stubs: {
          GlTableLite: { ...stubComponent(GlTableLite), props: ['items', 'fields'] },
          ...stubs,
        },
        provide,
      });

      return wrapper;
    };
  };

  const createComponent = createComponentFactory();
  const createFullComponent = createComponentFactory({ mountFn: mountExtended });

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findColumnKeys = () =>
    findTable()
      .props('fields')
      .map((field) => field.key);
  const findColumnWidths = () =>
    findTable()
      .props('fields')
      .map((field) => field.thStyle.width);
  const findTableRows = () => findTable().findAll('tbody tr');
  const findNthTableRow = (n) => findTableRows().at(n);
  const findSelectAllCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findItemCheckbox = () => wrapper.findComponent(CheckboxCell);
  const findTooltipButton = () =>
    wrapper.find('[data-testid="security-attributes-tooltip-button"]');

  beforeEach(() => {
    createComponent();
  });

  describe('component rendering', () => {
    it('renders the table component', () => {
      expect(findTable().exists()).toBe(true);
    });

    it('passes fields to GlTableLite component', () => {
      const width = { width: expect.any(String) };

      expect(findTable().props('fields')).toEqual([
        { key: 'name', label: 'Name', thStyle: width },
        { key: 'vulnerabilities', label: 'Vulnerabilities', thStyle: width },
        { key: 'toolCoverage', label: 'Tool coverage', thStyle: width },
        { key: 'securityAttributes', label: 'Security attributes', thStyle: width },
        { key: 'actions', label: '', tdClass: 'gl-text-right', thStyle: width },
      ]);
    });

    it('passes items to GlTableLite component', () => {
      expect(findTable().props('items')).toEqual(items);
    });

    it('sizes each visible column in proportion to its width weight', () => {
      expect(findColumnKeys()).toEqual(allColumnKeys);
      expect(findColumnWidths()).toEqual([
        'calc((100% - 4rem) * 18 / 72)',
        'calc((100% - 4rem) * 14 / 72)',
        'calc((100% - 4rem) * 26 / 72)',
        'calc((100% - 4rem) * 14 / 72)',
        '4rem',
      ]);
    });

    it('gives the checkbox column a static width when it is shown', () => {
      createComponent({
        provide: {
          groupFullPath: 'path/to/group',
          canManageAttributes: true,
          canReadAttributes: true,
          canApplyProfiles: false,
        },
      });

      expect(findColumnKeys()).toEqual(['checkbox', ...allColumnKeys]);
      expect(findColumnWidths()).toEqual([
        '3rem',
        'calc((100% - 3rem - 4rem) * 18 / 72)',
        'calc((100% - 3rem - 4rem) * 14 / 72)',
        'calc((100% - 3rem - 4rem) * 26 / 72)',
        'calc((100% - 3rem - 4rem) * 14 / 72)',
        '4rem',
      ]);
    });
  });

  describe('loading state', () => {
    beforeEach(() => {
      createFullComponent({ props: { items: [], isLoading: true }, stubs: { GlTableLite: false } });
    });

    it('shows the correct number of skeleton rows when loading', () => {
      expect(findTableRows()).toHaveLength(3);
    });

    it('shows skeleton loaders for each column in a row', () => {
      const firstRow = findNthTableRow(0);
      const firstRowLoaders = firstRow.findAllComponents(GlSkeletonLoader);
      expect(firstRowLoaders).toHaveLength(5);
    });
  });

  describe('cell rendering', () => {
    beforeEach(() => {
      createFullComponent({ stubs: { GlTableLite: false } });
    });

    it('renders all required cell components', () => {
      expect(findTableRows()).toHaveLength(items.length);

      const firstRow = findNthTableRow(0);
      expect(firstRow.findComponent(NameCell).exists()).toBe(true);
      expect(firstRow.findComponent(VulnerabilityCell).exists()).toBe(true);
      expect(firstRow.findComponent(ToolCoverageCell).exists()).toBe(true);
      expect(firstRow.findComponent(AttributesCell).exists()).toBe(true);
      expect(firstRow.findComponent(ActionCell).exists()).toBe(true);
      expect(firstRow.findComponent(CheckboxCell).exists()).toBe(false);
    });
  });

  describe('security attributes header tooltip', () => {
    const TOOLTIP_TEXT =
      'You must have at least the Maintainer role in this group to manage security attributes.';

    beforeEach(() => {
      createFullComponent({ stubs: { GlTableLite: false } });
    });

    it('renders a focusable tooltip button with the expected title and aria-label', () => {
      const button = findTooltipButton();

      expect(button.exists()).toBe(true);
      expect(button.attributes('type')).toBe('button');
      expect(button.attributes('title')).toBe(TOOLTIP_TEXT);
      expect(button.attributes('aria-label')).toBe(TOOLTIP_TEXT);
    });
  });

  describe('subgroup navigation', () => {
    // mockProject.fullPath is 'flightjs/security-reports-example', so its parent is 'flightjs'
    const findProjectNameCell = () => findNthTableRow(1).findComponent(NameCell);

    it('passes a hash link to the parent path when not already viewing it', () => {
      createFullComponent({
        props: { currentPath: 'other/path' },
        stubs: { GlTableLite: false },
      });

      expect(findProjectNameCell().props('subgroupHref')).toBe('#flightjs');
    });

    it('passes no link when already viewing the parent path', () => {
      createFullComponent({
        props: { currentPath: 'flightjs' },
        stubs: { GlTableLite: false },
      });

      expect(findProjectNameCell().props('subgroupHref')).toBe('');
    });
  });

  describe('bulk selection', () => {
    describe('with permission', () => {
      beforeEach(() => {
        createFullComponent({
          props: { items },
          stubs: { GlTableLite: false },
          provide: {
            canReadAttributes: true,
            canManageAttributes: true,
            canApplyProfiles: false,
            groupFullPath: 'path/to/group',
          },
        });
      });

      it('select all checkbox selects and deselects all visible items', () => {
        findSelectAllCheckbox().vm.$emit('change', true);

        expect(wrapper.emitted('selected-count')[0]).toStrictEqual([2]);

        findSelectAllCheckbox().vm.$emit('change', false);

        expect(wrapper.emitted('selected-count')[1]).toStrictEqual([0]);
      });

      it('checkbox cell selects and deselects a single item', () => {
        findItemCheckbox().vm.$emit('select-item', items[0], true);

        expect(wrapper.emitted('selected-count')[0]).toStrictEqual([1]);

        findItemCheckbox().vm.$emit('select-item', items[0], false);

        expect(wrapper.emitted('selected-count')[1]).toStrictEqual([0]);
      });
    });
  });

  describe('when user does not have permission', () => {
    beforeEach(() => {
      createComponent({
        provide: {
          canManageAttributes: false,
          canReadAttributes: false,
          canApplyProfiles: false,
        },
      });
    });

    it('does not show the security attributes column', () => {
      expect(findTable().props('fields')).not.toContain(
        expect.objectContaining({ key: 'securityAttributes' }),
      );
    });
  });

  describe('when columns are hidden', () => {
    it('drops them from the table and resizes the rest', () => {
      createComponent({ props: { hiddenColumns: ['vulnerabilities'] } });

      expect(findColumnKeys()).toEqual(['name', 'toolCoverage', 'securityAttributes', 'actions']);
      expect(findColumnWidths()).toEqual([
        'calc((100% - 4rem) * 18 / 58)',
        'calc((100% - 4rem) * 26 / 58)',
        'calc((100% - 4rem) * 14 / 58)',
        '4rem',
      ]);
    });

    it('keeps the actions column the same width when a column is hidden', () => {
      createComponent();
      const [actionsWidth] = findColumnWidths().slice(-1);

      createComponent({ props: { hiddenColumns: ['vulnerabilities'] } });

      expect(findColumnWidths().slice(-1)).toEqual([actionsWidth]);
    });

    it('does not hide columns that are not toggleable', () => {
      createComponent({ props: { hiddenColumns: ['name'] } });

      expect(findColumnKeys()).toEqual(allColumnKeys);
    });
  });

  describe('bulkEdit method with action types', () => {
    beforeEach(() => {
      createFullComponent({
        stubs: {
          GlTableLite: false,
          BulkAttributesUpdateDrawer: stubComponent({
            methods: { openDrawer: jest.fn() },
          }),
          BulkScannersUpdateDrawer: stubComponent({
            methods: { openDrawer: jest.fn() },
          }),
        },
        provide: {
          canApplyProfiles: true,
          canManageAttributes: true,
          canReadAttributes: true,
          groupFullPath: 'path/to/group',
        },
      });

      findSelectAllCheckbox().vm.$emit('change', true);
    });

    it('opens attributes drawer when called with attributes action type', async () => {
      await nextTick(); // Wait for drawer to be rendered after selection

      openDrawerSpy = jest.spyOn(wrapper.vm.$refs.bulkAttributesDrawer, 'openDrawer');

      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_EDIT_ATTRIBUTES);
      await nextTick();

      expect(openDrawerSpy).toHaveBeenCalled();
    });

    it('opens scanners drawer when called with scanners action type', async () => {
      openDrawerSpy = jest.spyOn(wrapper.vm.$refs.bulkScannersDrawer, 'openDrawer');

      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_EDIT_SCANNERS);
      await nextTick();

      expect(openDrawerSpy).toHaveBeenCalled();
    });
  });

  describe('openAttributesDrawer method', () => {
    beforeEach(() => {
      createFullComponent({
        stubs: {
          GlTableLite: false,
          ProjectAttributesUpdateDrawer: stubComponent({
            methods: { openDrawer: jest.fn() },
          }),
        },
      });
    });

    it('recreates drawer component when switching between different projects', async () => {
      wrapper.vm.openAttributesDrawer(mockProject);
      await nextTick();

      const firstDrawerInstance = wrapper.vm.$refs.attributesDrawer;

      wrapper.vm.openAttributesDrawer(anotherProject);
      await nextTick();

      const secondDrawerInstance = wrapper.vm.$refs.attributesDrawer;

      expect(firstDrawerInstance).not.toBe(secondDrawerInstance);
    });
  });
});
