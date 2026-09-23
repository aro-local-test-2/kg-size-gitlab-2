import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RowActionsMenu from 'ee/packages_and_registries/artifact_registry/repositories/components/row_actions_menu.vue';
import {
  mockDeniedRepositoryPermissions,
  mockRepository,
  mockRepositoryPermissions,
} from '../../mock_data';

describe('ArtifactRegistryRepositoryRowActionsMenu', () => {
  let wrapper;

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findEditItem = () => wrapper.findComponent(GlDisclosureDropdownItem);

  const createComponent = ({ propsData = {} } = {}) => {
    wrapper = shallowMountExtended(RowActionsMenu, {
      propsData: {
        repository: mockRepository,
        permissions: mockRepositoryPermissions(),
        ...propsData,
      },
    });
  };

  describe('when the update verdict allows', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders as an icon-only kebab, so the column stays narrow', () => {
      expect(findDropdown().props()).toMatchObject({
        icon: 'ellipsis_v',
        noCaret: true,
        textSrOnly: true,
        placement: 'bottom-end',
      });
    });

    it('names the repository in the toggle, because the menu repeats once per row', () => {
      expect(findDropdown().props('toggleText')).toBe('More actions for my-repository');
    });

    it('routes to the edit view for its own repository', () => {
      expect(findEditItem().props('item')).toEqual({
        text: 'Edit repository',
        to: { name: 'repository_edit', params: { id: 'my-repository' } },
      });
    });
  });

  describe('when every verdict denies', () => {
    beforeEach(() => {
      createComponent({ propsData: { permissions: mockDeniedRepositoryPermissions() } });
    });

    it('renders no edit item', () => {
      expect(findEditItem().exists()).toBe(false);
    });

    it('renders no toggle, because no item remains behind it', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('when the update verdict alone denies', () => {
    beforeEach(() => {
      createComponent({
        propsData: { permissions: mockRepositoryPermissions({ updateRepository: false }) },
      });
    });

    it('renders nothing, whatever the other verdicts say', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('when the update verdict alone allows', () => {
    beforeEach(() => {
      createComponent({
        propsData: { permissions: mockDeniedRepositoryPermissions({ updateRepository: true }) },
      });
    });

    it('renders the kebab with its edit item, whatever the other verdicts say', () => {
      expect(findDropdown().exists()).toBe(true);
      expect(findEditItem().exists()).toBe(true);
    });
  });

  describe('before the block has resolved', () => {
    beforeEach(() => {
      createComponent({ propsData: { permissions: undefined } });
    });

    it('renders nothing', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });
});
