import { GlDisclosureDropdown } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CreateButton from 'ee/packages_and_registries/artifact_registry/repositories/components/create_button.vue';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import {
  BASE_PATH,
  mockDeniedNamespacePermissions,
  mockNamespacePermissions,
} from '../../mock_data';

describe('ArtifactRegistryCreateButton', () => {
  let wrapper;

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findEntries = () => wrapper.findAllByRole('link');

  const createComponent = async ({ mountFn = shallowMountExtended, propsData = {} } = {}) => {
    const router = createRouter(BASE_PATH);
    await router.push('/');

    wrapper = mountFn(CreateButton, {
      router,
      propsData: { permissions: mockNamespacePermissions(), ...propsData },
    });
  };

  describe('when the create verdict allows', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('renders the dropdown', () => {
      expect(findDropdown().exists()).toBe(true);
    });

    it('reads as the primary action on the page it sits on', () => {
      expect(findDropdown().props('variant')).toBe('confirm');
    });

    it('opens its menu below and aligned to the toggle', () => {
      expect(findDropdown().props('placement')).toBe('bottom-start');
    });

    it('names what it creates, so the toggle stands alone as an accessible name', () => {
      expect(findDropdown().props('toggleText')).toBe('New repository');
    });
  });

  it('aligns its menu where the surface it sits on asks', async () => {
    await createComponent({ propsData: { placement: 'bottom-end' } });

    expect(findDropdown().props('placement')).toBe('bottom-end');
  });

  it('offers hosted and remote', async () => {
    await createComponent({ mountFn: mountExtended });

    expect(findEntries().wrappers.map((entry) => entry.text())).toEqual([
      'Hosted repository',
      'Remote repository',
    ]);
    expect(findEntries().wrappers.map((entry) => entry.attributes('href'))).toEqual([
      `${BASE_PATH}/new/hosted`,
      `${BASE_PATH}/new/remote`,
    ]);
  });

  describe('when every verdict denies', () => {
    beforeEach(async () => {
      await createComponent({ propsData: { permissions: mockDeniedNamespacePermissions() } });
    });

    it('renders nothing', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('when the create verdict alone denies', () => {
    beforeEach(async () => {
      await createComponent({
        propsData: { permissions: mockNamespacePermissions({ createRepository: false }) },
      });
    });

    it('renders nothing, whatever the other verdicts say', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('when the create verdict alone allows', () => {
    beforeEach(async () => {
      await createComponent({
        propsData: { permissions: mockDeniedNamespacePermissions({ createRepository: true }) },
      });
    });

    it('renders the dropdown, whatever the other verdicts say', () => {
      expect(findDropdown().exists()).toBe(true);
    });
  });

  describe('before the block has resolved', () => {
    beforeEach(async () => {
      await createComponent({ propsData: { permissions: undefined } });
    });

    it('renders nothing', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });
});
