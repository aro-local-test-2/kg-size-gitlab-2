import { RouterLinkStub } from '@vue/test-utils';
import { GlButton, GlEmptyState } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import VersionListEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/versions/version_list_empty_state.vue';
import { mockRepository } from '../../mock_data';

describe('ArtifactRegistryVersionListEmptyState', () => {
  let wrapper;

  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findRepositoryLink = () => wrapper.findComponent(GlButton);

  const createComponent = ({ format = 'MAVEN', name = mockRepository.name } = {}) => {
    wrapper = mountExtended(VersionListEmptyState, {
      propsData: { format, name },
      stubs: { RouterLink: RouterLinkStub },
    });
  };

  describe('the heading and support text', () => {
    it.each([
      ['MAVEN', 'versions of this package', 'Publish your first version'],
      ['NPM', 'versions of this package', 'Publish your first version'],
      ['DOCKER', 'manifests in this image', 'Push your first manifest'],
      ['OCI', 'manifests in this image', 'Push your first manifest'],
    ])('names what a %s artifact holds', (format, holds, action) => {
      createComponent({ format });

      expect(findEmptyState().props('title')).toBe(`There are no ${holds} yet`);
      expect(findEmptyState().props('description')).toBe(`${action} to get started.`);
    });

    it('renders the illustration', () => {
      createComponent();

      expect(findEmptyState().props('svgPath')).toContain('empty-package');
    });
  });

  describe('the link to the setup instructions', () => {
    beforeEach(() => createComponent());

    it('routes to the repository, which owns them', () => {
      expect(findRepositoryLink().props('to')).toStrictEqual({
        name: 'repository_detail',
        params: { id: 'my-repository' },
      });
    });

    it('names the repository it routes to, so the action reads without its surroundings', () => {
      expect(findRepositoryLink().text()).toBe('Go to repository');
    });

    it('routes rather than linking, so following it does not reload the app', () => {
      expect(findRepositoryLink().props('href')).toBeUndefined();
    });
  });

  it('carries the repository name it was given into the route', () => {
    createComponent({ name: 'another-repository' });

    expect(findRepositoryLink().props('to')).toStrictEqual({
      name: 'repository_detail',
      params: { id: 'another-repository' },
    });
  });
});
