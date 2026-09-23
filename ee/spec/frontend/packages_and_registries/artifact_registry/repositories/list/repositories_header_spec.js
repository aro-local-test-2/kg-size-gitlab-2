import { GlDisclosureDropdown } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import CreateButton from 'ee/packages_and_registries/artifact_registry/repositories/components/create_button.vue';
import RepositoriesHeader from 'ee/packages_and_registries/artifact_registry/repositories/list/repositories_header.vue';
import { mockDeniedNamespacePermissions, mockNamespacePermissions } from '../../mock_data';

describe('ArtifactRegistryRepositoriesHeader', () => {
  let wrapper;

  const findHeading = () => wrapper.findComponent(PageHeading);
  const findActions = () => wrapper.findByTestId('page-heading-actions');
  const findCreateButton = () => findActions().findComponent(CreateButton);
  const findDropdown = () => findActions().findComponent(GlDisclosureDropdown);

  // The heading is unstubbed so its actions slot renders, which is where the create
  // entry has to land rather than anywhere else in the header.
  const createComponent = ({ propsData = {}, stubs = {} } = {}) => {
    wrapper = shallowMountExtended(RepositoriesHeader, {
      propsData: { permissions: mockNamespacePermissions(), ...propsData },
      stubs: { PageHeading, ...stubs },
    });
  };

  describe('by default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the view in the page-level heading', () => {
      expect(findHeading().props('heading')).toBe('Repositories');
    });

    it('renders the create entry beside the heading', () => {
      expect(findCreateButton().exists()).toBe(true);
    });

    it('opens the create menu inward, because the entry sits at the right edge of the heading', () => {
      expect(findCreateButton().props('placement')).toBe('bottom-end');
    });
  });

  it('hands the namespace block to the create entry, which decides whether it renders', () => {
    const permissions = mockNamespacePermissions();

    createComponent({ propsData: { permissions } });

    expect(findCreateButton().props('permissions')).toEqual(permissions);
  });

  describe('when the create verdict allows', () => {
    beforeEach(() => {
      createComponent({ stubs: { CreateButton } });
    });

    it('renders the create dropdown', () => {
      expect(findDropdown().exists()).toBe(true);
    });
  });

  describe('when the create verdict denies', () => {
    beforeEach(() => {
      createComponent({
        propsData: { permissions: mockDeniedNamespacePermissions() },
        stubs: { CreateButton },
      });
    });

    it('renders the heading with no create dropdown', () => {
      expect(findHeading().props('heading')).toBe('Repositories');
      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('before the block has resolved', () => {
    beforeEach(() => {
      createComponent({ propsData: { permissions: undefined }, stubs: { CreateButton } });
    });

    it('renders no create dropdown', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });
});
