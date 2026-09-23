import { GlBadge, GlCard, GlFormCheckbox, GlFormGroup, GlCollapsibleListbox } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import EnableScannersSelectScanners from 'ee/security_configuration/components/enable_scanners_wizard/select_scanners.vue';
import ScanProfileDetailsModal from 'ee/security_configuration/components/scan_profiles/scan_profile_details_modal.vue';
import { APPROACH_QUICK } from 'ee/security_configuration/components/enable_scanners_wizard/constants';
import { mockScanner, mockScanner2 } from '../scan_profiles/mock_data';

describe('EnableScannersSelectScanners', () => {
  let wrapper;
  let enableScanners;

  const sastProfile = mockScanner2;
  const secretProfile = mockScanner;
  const customSastProfile = {
    ...sastProfile,
    id: 'gid://gitlab/Security::ScanProfile/99',
    name: 'SAST Custom A',
    gitlabRecommended: false,
  };
  const defaultProfilesByScanType = {
    SAST: [sastProfile],
    SECRET_DETECTION: [secretProfile],
  };
  const profilesWithCustomSast = {
    SAST: [sastProfile, customSastProfile],
    SECRET_DETECTION: [secretProfile],
  };
  const allScanTypes = Object.keys(defaultProfilesByScanType);

  const defaultStubs = {
    GlBadge,
    GlCard,
    GlFormGroup,
    GlCollapsibleListbox: stubComponent(GlCollapsibleListbox, {
      template: `
        <div>
          <div v-for="item in items" :key="item.text">
            <slot name="list-item" :item="item"></slot>
          </div>
        </div>
      `,
    }),
  };

  const createComponent = ({
    approach = APPROACH_QUICK,
    selectedScanners = [],
    profilesByScanType = defaultProfilesByScanType,
    activeProfileForScanType = (scanType) =>
      selectedScanners.find((scanner) => scanner.scanType === scanType) ??
      profilesByScanType[scanType]?.[0],
    toggleScanner = jest.fn(),
    toggleAllScanners = jest.fn(),
    selectScannerProfile = jest.fn(),
    mountFn = shallowMountExtended,
    stubs = defaultStubs,
  } = {}) => {
    enableScanners = {
      approach,
      profilesByScanType,
      allScanTypes: Object.keys(profilesByScanType),
      selectedScanners,
      activeProfileForScanType,
      toggleScanner,
      toggleAllScanners,
      selectScannerProfile,
    };

    wrapper = mountFn(EnableScannersSelectScanners, {
      provide: { enableScanners },
      stubs,
    });
  };

  const findCheckboxes = () => wrapper.findAllComponents(GlFormCheckbox);
  const findSelectAllCheckbox = () => findCheckboxes().at(0);
  const findCardCheckboxes = () => findCheckboxes().wrappers.slice(1);
  const findCards = () => wrapper.findAllComponents(GlCard);
  const findDropdowns = () => wrapper.findAllComponents(GlCollapsibleListbox);
  const findProfileBadges = (dropdownIndex) =>
    findDropdowns().at(dropdownIndex).findAllComponents(GlBadge);
  const findPreviewLink = () => wrapper.findAllComponentsByTestId('preview-profile-link').at(0);
  const findPreviewModal = () => wrapper.findComponent(ScanProfileDetailsModal);

  describe('select all scanners checkbox header', () => {
    it('is checked when every scan type is selected', () => {
      createComponent({ selectedScanners: [sastProfile, secretProfile] });

      expect(findSelectAllCheckbox().props('checked')).toBe(true);
    });

    it('is indeterminate when only some scan types are selected', () => {
      createComponent({ selectedScanners: [sastProfile] });

      expect(findSelectAllCheckbox().props('checked')).toBe(false);
      expect(findSelectAllCheckbox().props('indeterminate')).toBe(true);
    });

    it('calls toggleAllScanners on change', () => {
      const toggleAllScanners = jest.fn();
      createComponent({ toggleAllScanners });

      findSelectAllCheckbox().vm.$emit('change', true);

      expect(toggleAllScanners).toHaveBeenCalledWith(true);
    });

    it('shows the count of selected scan types out of the total', () => {
      createComponent({ selectedScanners: [sastProfile] });

      expect(wrapper.text()).toContain('1 of 2 selected');
    });
  });

  describe('scanner cards', () => {
    it('renders a card for each scan type', () => {
      createComponent();

      expect(findCards()).toHaveLength(allScanTypes.length);
    });

    it('shows a checkbox to select each scanner', () => {
      createComponent();

      expect(findCardCheckboxes()).toHaveLength(allScanTypes.length);
    });

    it('calls toggleScanner with the scan type when a card checkbox changes', () => {
      const toggleScanner = jest.fn();
      createComponent({ toggleScanner });

      findCardCheckboxes()[0].vm.$emit('change', true);

      expect(toggleScanner).toHaveBeenCalledWith('SAST', true);
    });
  });

  describe('profile dropdown', () => {
    it('shows the active profile name', () => {
      createComponent();

      expect(findDropdowns().at(0).props('toggleText')).toBe(sastProfile.name);
    });

    it('disables the dropdown when the scan type is not selected', () => {
      createComponent({ selectedScanners: [] });

      expect(findDropdowns().at(0).props('disabled')).toBe(true);
    });

    it('calls selectScannerProfile when a profile is chosen', () => {
      const selectScannerProfile = jest.fn();
      createComponent({ selectScannerProfile });

      const dropdown = findDropdowns().at(0);
      const chosenItem = dropdown.props('items')[0];
      dropdown.vm.$emit('select', chosenItem.value);

      expect(selectScannerProfile).toHaveBeenCalledWith('SAST', sastProfile);
    });

    it('shows the selected profile name when a non-default profile is selected', () => {
      createComponent({
        profilesByScanType: profilesWithCustomSast,
        selectedScanners: [customSastProfile],
      });

      expect(findDropdowns().at(0).props('toggleText')).toBe(customSastProfile.name);
    });

    it('marks the first profile as selected', () => {
      createComponent();

      expect(findDropdowns().at(0).props('selected')).toBe(sastProfile.id);
    });

    it('badges each profile as GitLab or Custom', () => {
      createComponent({ profilesByScanType: profilesWithCustomSast });

      expect(findProfileBadges(0).wrappers.map((badge) => badge.text())).toEqual([
        'GitLab',
        'Custom',
      ]);
    });

    describe('when an option is clicked in a fully rendered dropdown', () => {
      let selectScannerProfile;
      let optionClick;

      beforeEach(async () => {
        selectScannerProfile = jest.fn();

        createComponent({
          profilesByScanType: profilesWithCustomSast,
          selectedScanners: [sastProfile],
          selectScannerProfile,
          mountFn: mountExtended,
          stubs: {},
        });

        const dropdown = findDropdowns().at(0);
        await dropdown.find('[data-testid="base-dropdown-toggle"]').trigger('click');

        optionClick = null;
        dropdown.element.closest('label').addEventListener('click', (event) => {
          optionClick = event;
        });
        await dropdown.findAll('[role="option"]').at(1).trigger('click');
      });

      it('selects the chosen profile', () => {
        expect(selectScannerProfile).toHaveBeenCalledWith('SAST', customSastProfile);
      });

      it('cancels the click default action that would deselect the card', () => {
        expect(optionClick.defaultPrevented).toBe(true);
      });
    });
  });

  describe('profile preview link', () => {
    it('opens the preview modal for the chosen profile when clicked', async () => {
      createComponent();

      await findPreviewLink().vm.$emit('click');

      expect(findPreviewModal().props()).toMatchObject({
        visible: true,
        profileId: sastProfile.id,
        scanType: 'SAST',
      });
    });

    it('closes the preview modal on the modal close event', async () => {
      createComponent();

      await findPreviewLink().vm.$emit('click');
      await findPreviewModal().vm.$emit('close');

      expect(findPreviewModal().props('visible')).toBe(false);
    });
  });
});
