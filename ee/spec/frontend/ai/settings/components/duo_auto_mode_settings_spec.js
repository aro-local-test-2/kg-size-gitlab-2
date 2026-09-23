import { GlCollapsibleListbox, GlFormGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoAutoModeSettings from 'ee/ai/settings/components/duo_auto_mode_settings.vue';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import { AVAILABILITY_OPTIONS } from 'ee/ai/settings/constants';

describe('DuoAutoModeSettings', () => {
  let wrapper;

  const defaultProvide = {
    isGroupSettings: false,
    duoAutoModeCascadingSettings: {
      lockedByAncestor: false,
      lockedByApplicationSetting: false,
    },
  };

  const createComponent = ({ props = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(DuoAutoModeSettings, {
      propsData: {
        duoAutoModeAvailability: AVAILABILITY_OPTIONS.DEFAULT_OFF,
        ...props,
      },
      provide: {
        ...defaultProvide,
        ...provide,
      },
    });
  };

  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findDropdown = () => wrapper.findComponent(GlCollapsibleListbox);
  const findCascadingLockIcon = () => wrapper.findComponent(CascadingLockIcon);

  describe('component rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the form group with correct label', () => {
      expect(findFormGroup().attributes('label')).toBe('Auto mode');
    });

    it('renders a dropdown with three options', () => {
      const dropdown = findDropdown();
      expect(dropdown.exists()).toBe(true);
      expect(dropdown.props('items')).toHaveLength(3);
    });

    it('renders correct dropdown option labels', () => {
      const items = findDropdown().props('items');
      expect(items.map((i) => i.text)).toEqual(['On by default', 'Off by default', 'Always off']);
    });

    it('renders correct dropdown option values', () => {
      const items = findDropdown().props('items');
      expect(items.map((i) => i.value)).toEqual([
        AVAILABILITY_OPTIONS.DEFAULT_ON,
        AVAILABILITY_OPTIONS.DEFAULT_OFF,
        AVAILABILITY_OPTIONS.NEVER_ON,
      ]);
    });
  });

  describe('dropdown state', () => {
    it.each`
      availability                        | description
      ${AVAILABILITY_OPTIONS.DEFAULT_ON}  | ${'default_on'}
      ${AVAILABILITY_OPTIONS.DEFAULT_OFF} | ${'default_off'}
      ${AVAILABILITY_OPTIONS.NEVER_ON}    | ${'never_on'}
    `('sets initial selected value to $description', ({ availability }) => {
      createComponent({ props: { duoAutoModeAvailability: availability } });

      expect(findDropdown().props('selected')).toBe(availability);
    });
  });

  describe('dropdown interactions', () => {
    beforeEach(() => {
      createComponent();
    });

    it('emits change event when dropdown selection changes', () => {
      findDropdown().vm.$emit('select', AVAILABILITY_OPTIONS.DEFAULT_ON);

      expect(wrapper.emitted('change')).toEqual([[AVAILABILITY_OPTIONS.DEFAULT_ON]]);
    });
  });

  describe('dropdown items include secondary text', () => {
    describe('when isGroupSettings is true', () => {
      beforeEach(() => {
        createComponent({ provide: { isGroupSettings: true } });
      });

      it('includes group-specific secondary text', () => {
        const items = findDropdown().props('items');
        expect(items[0].secondaryText).toBe('Auto mode is available. Subgroups can turn it off.');
        expect(items[2].secondaryText).toBe(
          'Auto mode is not available and cannot be turned on for any subgroup.',
        );
      });
    });

    describe('when isGroupSettings is false', () => {
      beforeEach(() => {
        createComponent({ provide: { isGroupSettings: false } });
      });

      it('includes instance-specific secondary text', () => {
        const items = findDropdown().props('items');
        expect(items[0].secondaryText).toBe(
          'Auto mode is available. Groups and subgroups can turn it off.',
        );
        expect(items[2].secondaryText).toBe(
          'Auto mode is not available and cannot be turned on for any group or subgroup.',
        );
      });
    });
  });

  describe('disabled state', () => {
    it('does not disable dropdown by default', () => {
      createComponent();

      expect(findDropdown().props('disabled')).toBe(false);
    });

    describe('when disabled prop is true', () => {
      beforeEach(() => {
        createComponent({ props: { disabled: true } });
      });

      it('disables the dropdown', () => {
        expect(findDropdown().props('disabled')).toBe(true);
      });
    });
  });

  describe('cascading lock icon', () => {
    it('does not render cascading lock by default', () => {
      createComponent();

      expect(findCascadingLockIcon().exists()).toBe(false);
    });

    describe('when cascading settings is null', () => {
      beforeEach(() => {
        createComponent({
          provide: {
            duoAutoModeCascadingSettings: null,
          },
        });
      });

      it('does not render the cascading lock', () => {
        expect(findCascadingLockIcon().exists()).toBe(false);
        expect(findDropdown().props('disabled')).toBe(false);
      });
    });

    describe('when locked by application setting', () => {
      beforeEach(() => {
        createComponent({
          provide: {
            duoAutoModeCascadingSettings: {
              lockedByAncestor: false,
              lockedByApplicationSetting: true,
            },
          },
        });
      });

      it('shows cascading lock icon', () => {
        expect(findCascadingLockIcon().exists()).toBe(true);
        expect(findCascadingLockIcon().props('isLockedByApplicationSettings')).toBe(true);
      });

      it('disables the dropdown', () => {
        expect(findDropdown().props('disabled')).toBe(true);
      });
    });

    describe('when locked by ancestor', () => {
      beforeEach(() => {
        createComponent({
          provide: {
            duoAutoModeCascadingSettings: {
              lockedByAncestor: true,
              lockedByApplicationSetting: false,
              ancestorNamespace: { path: 'parent-group', fullName: 'Parent Group' },
            },
          },
        });
      });

      it('shows cascading lock icon', () => {
        expect(findCascadingLockIcon().exists()).toBe(true);
        expect(findCascadingLockIcon().props('isLockedByGroupAncestor')).toBe(true);
      });

      it('disables the dropdown', () => {
        expect(findDropdown().props('disabled')).toBe(true);
      });
    });
  });
});
