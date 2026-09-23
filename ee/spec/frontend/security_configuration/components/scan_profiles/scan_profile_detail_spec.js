import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import ScanProfileDetail from 'ee/security_configuration/components/scan_profiles/scan_profile_detail.vue';
import ScanTriggersDetail from 'ee/security_configuration/components/scan_profiles/scan_triggers_detail.vue';
import { SCAN_PROFILE_TYPE_SECRET_DETECTION } from '~/security_configuration/constants';

describe('ScanProfileDetail', () => {
  let wrapper;

  const profile = {
    id: 'gid://gitlab/Security::ScanProfile/1',
    name: 'Secret Detection (default)',
    description: 'Protect your repository from leaked secrets',
    scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
    gitlabRecommended: true,
    triggers: ['MERGE_REQUEST_PIPELINE', 'GIT_PUSH_EVENT'],
  };

  const createComponent = (overrides = {}) => {
    wrapper = shallowMountExtended(ScanProfileDetail, {
      propsData: { profile: { ...profile, ...overrides } },
      stubs: { CrudComponent },
    });
  };

  const findBadge = () => wrapper.findComponent(GlBadge);
  const findTriggersDetail = () => wrapper.findComponent(ScanTriggersDetail);
  const findDeleteButton = () => wrapper.findComponentByTestId('scan-profile-delete-button');
  const findValues = () => wrapper.findAll('dd').wrappers.map((cell) => cell.text());
  const findTriggers = () => findTriggersDetail().props('triggers');
  const findTriggerAnchors = () => findTriggers().map(({ anchor }) => anchor);

  it('renders the profile name as the heading', () => {
    createComponent();

    expect(wrapper.find('h3').text()).toBe(profile.name);
  });

  it('renders the general details', () => {
    createComponent();

    expect(findValues()).toEqual([
      'Secret Detection (default)',
      'Protect your repository from leaked secrets',
      'Secret detection',
      'GitLab',
    ]);
  });

  it.each([
    [true, 'GitLab'],
    [false, 'Custom'],
  ])('badges gitlabRecommended %s as managed by %s', (gitlabRecommended, label) => {
    createComponent({ gitlabRecommended });

    expect(findBadge().text()).toBe(label);
  });

  it('falls back to the raw scan type when it is not a known category', () => {
    createComponent({ scanType: 'NOT_A_SCANNER' });

    expect(findValues()).toContain('NOT_A_SCANNER');
  });

  it('passes the resolved trigger definitions down', () => {
    createComponent();

    expect(findTriggerAnchors()).toEqual(['merge-request-pipeline', 'secret-push-protection']);
    expect(findTriggers()[0].title).toBe('Merge Request Pipelines');
  });

  it('passes the help link for the scan type down', () => {
    createComponent();

    expect(findTriggersDetail().props('profileHelpLink')).toBe(
      '/help/user/application_security/configuration/security_configuration_profiles',
    );
  });

  it('drops trigger types with no definition rather than rendering blanks', () => {
    createComponent({ triggers: ['MERGE_REQUEST_PIPELINE', 'NOT_A_TRIGGER'] });

    expect(findTriggerAnchors()).toEqual(['merge-request-pipeline']);
  });

  it('handles a profile with no triggers', () => {
    createComponent({ triggers: [] });

    expect(findTriggerAnchors()).toEqual([]);
  });

  describe('delete button', () => {
    it('is always rendered with a Delete aria-label', () => {
      createComponent();

      expect(findDeleteButton().exists()).toBe(true);
      expect(findDeleteButton().attributes('aria-label')).toBe('Delete');
    });

    it('is disabled for a GitLab-recommended profile and explains why', () => {
      createComponent({ gitlabRecommended: true });

      expect(findDeleteButton().props('disabled')).toBe(true);
      expect(findDeleteButton().attributes('title')).toBe(
        "GitLab-managed profiles can't be deleted.",
      );
    });

    it('is enabled for a custom profile with a Delete tooltip', () => {
      createComponent({ gitlabRecommended: false });

      expect(findDeleteButton().props('disabled')).toBe(false);
      expect(findDeleteButton().attributes('title')).toBe('Delete');
    });

    it('emits delete when clicked on a custom profile', () => {
      createComponent({ gitlabRecommended: false });

      findDeleteButton().vm.$emit('click');

      expect(wrapper.emitted('delete')).toHaveLength(1);
    });
  });
});
