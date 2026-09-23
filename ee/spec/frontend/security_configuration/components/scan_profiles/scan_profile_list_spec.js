import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ScanProfileList from 'ee/security_configuration/components/scan_profiles/scan_profile_list.vue';

describe('ScanProfileList', () => {
  let wrapper;

  const recommendedProfile = {
    id: 'gid://gitlab/Security::ScanProfile/1',
    name: 'Secret Detection (default)',
    description: 'The recommended profile',
    gitlabRecommended: true,
    projectCount: 5,
  };

  const customProfile = {
    id: 'gid://gitlab/Security::ScanProfile/2',
    name: 'A custom profile',
    description: 'One the group made',
    gitlabRecommended: false,
    projectCount: 2,
  };

  const createComponent = ({
    profiles = [recommendedProfile, customProfile],
    selectedId = '',
  } = {}) => {
    wrapper = shallowMountExtended(ScanProfileList, {
      propsData: { profiles, selectedId },
    });
  };

  const findItems = () => wrapper.findAllByTestId('scan-profile-list-item');
  const findItemAt = (index) => findItems().at(index);
  const findProjectCounts = () => wrapper.findAllByTestId('scan-profile-list-item-project-count');
  const findProjectCountAt = (index) => findProjectCounts().at(index);

  it('renders a row per profile', () => {
    createComponent();

    expect(findItems()).toHaveLength(2);
  });

  it('renders the name and description', () => {
    createComponent();

    expect(findItemAt(0).text()).toContain('Secret Detection (default)');
    expect(findItemAt(0).text()).toContain('The recommended profile');
  });

  it.each([
    ['GitLab', 0],
    ['Custom', 1],
  ])('labels a profile as managed by %s', (label, index) => {
    createComponent();

    expect(findItemAt(index).text()).toContain(label);
  });

  it('marks the selected profile as current', () => {
    createComponent({ selectedId: customProfile.id });

    expect(findItemAt(0).attributes('aria-current')).toBeUndefined();
    expect(findItemAt(1).attributes('aria-current')).toBe('true');
  });

  it('emits select with the profile id when a row is clicked', () => {
    createComponent();

    findItemAt(1).trigger('click');

    expect(wrapper.emitted('select')).toEqual([[customProfile.id]]);
  });

  it('renders nothing for an empty list', () => {
    createComponent({ profiles: [] });

    expect(findItems()).toHaveLength(0);
  });

  it.each([
    [0, 5],
    [1, 2],
  ])(
    'renders the project count with a screen-reader label for the profile at row %i',
    (index, count) => {
      createComponent();

      const projectCount = findProjectCountAt(index);

      expect(projectCount.find('[aria-hidden="true"]').text()).toBe(String(count));
      expect(projectCount.find('.gl-sr-only').text()).toBe(`${count} projects`);
    },
  );

  it('uses the singular form in the screen-reader label when the count is 1', () => {
    createComponent({
      profiles: [{ ...recommendedProfile, projectCount: 1 }],
    });

    expect(findProjectCountAt(0).find('.gl-sr-only').text()).toBe('1 project');
  });
});
