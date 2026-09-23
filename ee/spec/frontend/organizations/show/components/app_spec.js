import { mountExtended } from 'helpers/vue_test_utils_helper';
import App from 'ee/organizations/show/components/app.vue';

describe('OrganizationShowApp EE', () => {
  let wrapper;

  const ARTIFACT_REGISTRY_PATH = '/o/gitlab/-/artifact_registry/my-registry/repositories';

  const defaultPropsData = {
    organization: {
      name: 'GitLab',
      path: 'gitlab',
    },
    canAdminOrganization: true,
    artifactRegistryPath: ARTIFACT_REGISTRY_PATH,
  };

  const createComponent = ({ propsData } = {}) => {
    wrapper = mountExtended(App, {
      propsData: { ...defaultPropsData, ...propsData },
    });
  };

  const findArtifactRegistryLink = () =>
    wrapper.findByRole('link', { name: 'Go to Artifact Registry' });

  describe('when the server supplies an artifact registry path', () => {
    describe('when the user can admin the organization', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders empty state with the artifact registry and settings description', () => {
        expect(wrapper.text()).toContain(
          "GitLab is your organization's home. Manage Artifact Registry and settings from the sidebar. Learn more.",
        );
      });

      it('links to the path the server chose', () => {
        expect(findArtifactRegistryLink().attributes('href')).toBe(ARTIFACT_REGISTRY_PATH);
      });
    });

    describe('when the user cannot admin the organization', () => {
      beforeEach(() => {
        createComponent({ propsData: { canAdminOrganization: false } });
      });

      it('renders empty state with the artifact registry description', () => {
        expect(wrapper.text()).toContain(
          "GitLab is your organization's home. Manage Artifact Registry from the sidebar. Learn more.",
        );
      });

      it('links to the path the server chose', () => {
        expect(findArtifactRegistryLink().attributes('href')).toBe(ARTIFACT_REGISTRY_PATH);
      });
    });

    describe('when the path is the setup page', () => {
      beforeEach(() => {
        createComponent({ propsData: { artifactRegistryPath: '/o/gitlab/-/artifact_registry' } });
      });

      it('links there rather than composing a repositories path of its own', () => {
        expect(findArtifactRegistryLink().attributes('href')).toBe('/o/gitlab/-/artifact_registry');
      });
    });
  });

  describe('when the server supplies no artifact registry path', () => {
    beforeEach(() => {
      createComponent({ propsData: { artifactRegistryPath: null } });
    });

    it('does not render link to artifact registry', () => {
      expect(findArtifactRegistryLink().exists()).toBe(false);
    });

    it('does not render artifact registry empty state copy', () => {
      expect(wrapper.text()).not.toContain('Artifact Registry');
    });
  });
});
