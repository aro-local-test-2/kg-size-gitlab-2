import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { typePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import clearRepositoryCacheMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/clear_repository_cache.mutation.graphql';
import UpstreamRepositoryActions from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repository_actions.vue';
import { mockClearRepositoryCacheResponse, mockUpstreamSummary } from '../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

describe('ArtifactRegistryUpstreamRepositoryActions', () => {
  let wrapper;
  let mockApollo;
  let cache;
  let clearHandler;

  const mockToast = { show: jest.fn() };

  const remoteUpstream = mockUpstreamSummary({ name: 'maven-central-proxy', kind: 'REMOTE' });
  const hostedUpstream = mockUpstreamSummary({ name: 'payments-releases', kind: 'HOSTED' });

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findItems = () => wrapper.findAllComponents(GlDisclosureDropdownItem);
  const findItemTexts = () => findItems().wrappers.map((item) => item.props('item').text);
  const findEditItem = () => wrapper.findComponentByTestId('edit-upstream-repository');
  const findClearCacheItem = () => wrapper.findComponentByTestId('clear-upstream-cache');

  const createComponent = ({ upstreamRepository = remoteUpstream } = {}) => {
    clearHandler = jest.fn().mockResolvedValue(mockClearRepositoryCacheResponse());

    mockApollo = createMockApollo(
      [[clearRepositoryCacheMutation, clearHandler]],
      {},
      {
        typePolicies: { ...globalTypePolicies, ...typePolicies },
      },
    );
    cache = mockApollo.clients.defaultClient.cache;

    wrapper = shallowMountExtended(UpstreamRepositoryActions, {
      apolloProvider: mockApollo,
      propsData: { upstreamRepository },
      mocks: { $toast: mockToast },
    });
  };

  const clearCache = async () => {
    findClearCacheItem().props('item').action();
    await waitForPromises();
  };

  const detailKey = (name) =>
    cache.identify({ __typename: 'ArtifactRegistryRepositoryDetails', name });

  const cachedDetails = (name) => cache.extract()[detailKey(name)];

  // Referenced from ROOT_QUERY, as a real read leaves them: an unreachable entry would be swept
  // by the helper's own `cache.gc()` and the eviction would look broader than it is.
  const seedDetailEntries = (...names) => {
    cache.restore({
      ROOT_QUERY: {
        __typename: 'Query',
        ...Object.fromEntries(names.map((name) => [name, { __ref: detailKey(name) }])),
      },
      ...Object.fromEntries(
        names.map((name) => [
          detailKey(name),
          { __typename: 'ArtifactRegistryRepositoryDetails', name },
        ]),
      ),
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('names the upstream in the toggle, which renders as an icon alone', () => {
    expect(findDropdown().props('toggleText')).toBe('More actions for maven-central-proxy');
  });

  it('renders the toggle as an icon-only tertiary button', () => {
    expect(findDropdown().props()).toMatchObject({
      icon: 'ellipsis_v',
      textSrOnly: true,
      category: 'tertiary',
      noCaret: true,
      placement: 'bottom-end',
    });
  });

  describe('the Edit repository item', () => {
    it('routes to the edit form for the upstream, addressed by its name', () => {
      expect(findEditItem().props('item').to).toEqual({
        name: 'repository_edit',
        params: { id: 'maven-central-proxy' },
      });
    });
  });

  describe('on a remote-source row', () => {
    it('adds Clear cache before Edit repository', () => {
      expect(findItemTexts()).toEqual(['Clear cache', 'Edit repository']);
    });
  });

  describe('on a hosted-source row', () => {
    beforeEach(() => {
      createComponent({ upstreamRepository: hostedUpstream });
    });

    it('carries Edit repository alone', () => {
      expect(findItemTexts()).toEqual(['Edit repository']);
      expect(findClearCacheItem().exists()).toBe(false);
    });
  });

  describe('clearing the cache', () => {
    describe('when the mutation resolves', () => {
      beforeEach(async () => {
        await clearCache();
      });

      it('issues the mutation once, addressing the upstream by name', () => {
        expect(clearHandler).toHaveBeenCalledTimes(1);
        expect(clearHandler).toHaveBeenCalledWith({ input: { name: 'maven-central-proxy' } });
      });

      it('reports acceptance through the toast, naming the upstream and no count', () => {
        expect(mockToast.show).toHaveBeenCalledTimes(1);
        expect(mockToast.show).toHaveBeenCalledWith(
          'Cache clear successfully scheduled for maven-central-proxy.',
        );
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('the cached details of the repositories on the page', () => {
      beforeEach(async () => {
        seedDetailEntries('maven-central-proxy', 'platform-snapshots');
        await clearCache();
      });

      it('drops the entry of the upstream that was cleared', () => {
        expect(cachedDetails('maven-central-proxy')).toBeUndefined();
      });

      it('leaves the other upstreams, which the clear does not touch', () => {
        expect(cachedDetails('platform-snapshots')).toBeDefined();
      });
    });

    describe('while a clear is in flight', () => {
      beforeEach(async () => {
        findClearCacheItem().props('item').action();
        await nextTick();
      });

      it('marks the toggle busy', () => {
        expect(findDropdown().props('loading')).toBe(true);
      });

      it('ignores a second attempt, so one clear cannot be issued twice', async () => {
        await clearCache();

        expect(clearHandler).toHaveBeenCalledTimes(1);
        expect(mockToast.show).toHaveBeenCalledTimes(1);
      });
    });

    it('frees the toggle once the clear is accepted', async () => {
      await clearCache();

      expect(findDropdown().props('loading')).toBe(false);
    });

    describe('when the payload carries errors', () => {
      beforeEach(async () => {
        clearHandler.mockResolvedValue(
          mockClearRepositoryCacheResponse({ errors: ['Repository not found.'] }),
        );
        await clearCache();
      });

      it('surfaces the error and shows no toast', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Repository not found.' });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('frees the toggle, so the clear can be retried', () => {
        expect(findDropdown().props('loading')).toBe(false);
      });
    });

    describe('when the mutation fails outright', () => {
      beforeEach(async () => {
        clearHandler.mockRejectedValue(new Error('Artifact Registry is down'));
        await clearCache();
      });

      it('reports the failure as an alert and shows no toast', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong. Please try again.',
          error: expect.any(Error),
          captureError: true,
        });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('frees the toggle, so the clear can be retried', () => {
        expect(findDropdown().props('loading')).toBe(false);
      });
    });
  });
});
