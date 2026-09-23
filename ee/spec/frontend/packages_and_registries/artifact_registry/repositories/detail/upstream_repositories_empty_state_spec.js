import { GlEmptyState, GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import UpstreamRepositoriesEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repositories_empty_state.vue';

describe('ArtifactRegistryUpstreamRepositoriesEmptyState', () => {
  let wrapper;

  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findLink = () => wrapper.findComponent(GlLink);

  const createComponent = ({ slots = {} } = {}) => {
    wrapper = mountExtended(UpstreamRepositoriesEmptyState, { slots });
  };

  describe('by default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the empty state with the virtual heading', () => {
      expect(findEmptyState().props('title')).toBe(
        'No repositories added to this virtual repository yet',
      );
    });

    it('explains what a virtual registry is', () => {
      expect(wrapper.text()).toContain(
        'A virtual registry acts as a single access point that routes requests across one or more hosted and remote repositories.',
      );
    });

    it('links to the documentation', () => {
      expect(findLink().text()).toBe('More information');
      expect(findLink().attributes('href')).toContain('artifact-registry/repositories');
    });
  });

  describe('the actions slot', () => {
    it('renders slot content when a consumer provides it', () => {
      createComponent({ slots: { actions: '<button data-testid="add-affordance">Add</button>' } });

      expect(wrapper.findByTestId('add-affordance').exists()).toBe(true);
    });
  });
});
