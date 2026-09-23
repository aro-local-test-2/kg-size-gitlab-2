import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { copyToClipboard } from '~/lib/utils/copy_to_clipboard';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ConfirmDangerModal from '~/vue_shared/components/confirm_danger/confirm_danger_modal.vue';
import { typePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import clearRepositoryCacheMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/clear_repository_cache.mutation.graphql';
import deleteRepositoryMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_repository.mutation.graphql';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.query.graphql';
import DeleteRepositoryModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_repository_modal.vue';
import RepositoryActions from 'ee/packages_and_registries/artifact_registry/repositories/detail/repository_actions.vue';
import {
  CLIENT_BASE_URL,
  ORGANIZATION_GID,
  SLUG,
  REPOSITORY_ID,
  mockClearRepositoryCacheResponse,
  mockDeleteRepositoryResponse,
  mockDeniedRepositoryPermissions,
  mockDetailRepository,
  mockRepositoryPermissions,
  mockRemoteImagePage,
  mockRemoteMavenPackagePage,
  mockRemoteSettings,
  mockRepository,
  mockRepositoryResponse,
} from '../../mock_data';

jest.mock('~/alert');
jest.mock('~/lib/utils/copy_to_clipboard');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('ArtifactRegistryRepositoryActions', () => {
  let wrapper;
  let mockApollo;
  let detailHandler;
  let imagesHandler;
  let packagesHandler;
  let clearHandler;
  let deleteHandler;

  const mockToast = { show: jest.fn() };

  const remoteRepository = (overrides = {}) => ({
    ...mockRepository,
    kind: 'REMOTE',
    settings: mockRemoteSettings,
    ...overrides,
  });

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findItems = () => wrapper.findAllComponents(GlDisclosureDropdownItem);
  const findItemTexts = () => findItems().wrappers.map((item) => item.props('item').text);
  const findCopyItem = () => wrapper.findComponentByTestId('copy-repository-url');
  const findClearCacheItem = () => wrapper.findComponentByTestId('clear-repository-cache');
  const findDeleteItem = () => wrapper.findComponentByTestId('delete-repository');
  const findDeleteModal = () => wrapper.findComponent(DeleteRepositoryModal);
  const findConfirmModal = () => wrapper.findComponent(ConfirmDangerModal);

  const createComponent = (overrides = {}, provide = {}, { props = {}, stubs = {} } = {}) => {
    const repository = { ...mockRepository, ...overrides };
    const artifactRepository = (connection) => ({
      __typename: 'ArtifactRegistryRepository',
      id: REPOSITORY_ID,
      name: repository.name,
      format: repository.format,
      ...connection,
    });

    detailHandler = jest.fn().mockResolvedValue(
      mockRepositoryResponse(
        mockDetailRepository(repository.format, {
          ...repository,
          userPermissions: mockRepositoryPermissions(),
        }),
      ),
    );
    imagesHandler = jest
      .fn()
      .mockResolvedValue(
        mockRepositoryResponse(artifactRepository({ images: mockRemoteImagePage })),
      );
    packagesHandler = jest
      .fn()
      .mockResolvedValue(
        mockRepositoryResponse(artifactRepository({ packages: mockRemoteMavenPackagePage })),
      );
    clearHandler = jest.fn().mockResolvedValue(mockClearRepositoryCacheResponse());
    deleteHandler = jest.fn().mockResolvedValue(mockDeleteRepositoryResponse());

    mockApollo = createMockApollo(
      [
        [getRepositoryDetailQuery, detailHandler],
        [getRepositoryImagesQuery, imagesHandler],
        [getRepositoryPackagesQuery, packagesHandler],
        [clearRepositoryCacheMutation, clearHandler],
        [deleteRepositoryMutation, deleteHandler],
      ],
      {},
      { typePolicies: { ...globalTypePolicies, ...typePolicies } },
    );

    wrapper = shallowMountExtended(RepositoryActions, {
      apolloProvider: mockApollo,
      propsData: { repository, permissions: mockRepositoryPermissions(), ...props },
      provide: {
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
        ...provide,
      },
      mocks: { $toast: mockToast },
      stubs,
    });
  };

  const watchQuery = (query, variables) =>
    mockApollo.clients.defaultClient
      .watchQuery({ query, variables: { organizationId: ORGANIZATION_GID, ...variables } })
      .subscribe(() => {});

  const watchPageQueries = (connectionQuery) => {
    watchQuery(getRepositoryDetailQuery, { name: mockRepository.name });
    watchQuery(connectionQuery, { name: mockRepository.name, first: 20 });

    return waitForPromises();
  };

  const clearCache = async () => {
    findClearCacheItem().props('item').action();
    await waitForPromises();
  };

  beforeEach(() => {
    createComponent();
  });

  it('names the repository in the toggle, which renders as an icon alone', () => {
    createComponent({ name: 'payment-core' });

    expect(findDropdown().props('toggleText')).toBe('More actions for payment-core');
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

  it('offers the read action before the destructive one', () => {
    expect(findItemTexts()).toEqual(['Copy repository URL', 'Delete repository']);
  });

  // Copy reads and delete destroys, so copy comes first and delete is marked out.
  it('marks the delete action as destructive', () => {
    expect(findDeleteItem().props('item')).toMatchObject({
      text: 'Delete repository',
      variant: 'danger',
    });
  });

  describe('copying the repository URL', () => {
    it('copies the URL a client is pointed at for this repository and format', async () => {
      createComponent({ name: 'payment-core', format: 'NPM' });

      findCopyItem().props('item').action();
      await waitForPromises();

      expect(copyToClipboard).toHaveBeenCalledWith(`${CLIENT_BASE_URL}/${SLUG}/npm/payment-core`);
    });

    // A menu item shows nothing once it is chosen, so the toast is the only report that
    // the copy happened, and being a live region it is also the announcement.
    it('reports the copy through a toast', async () => {
      copyToClipboard.mockResolvedValue();

      findCopyItem().props('item').action();
      await waitForPromises();

      expect(mockToast.show).toHaveBeenCalledWith('Repository URL copied to clipboard.');
    });

    it('reports a failed copy rather than claiming it succeeded', async () => {
      const error = new Error('Clipboard write failed');
      copyToClipboard.mockRejectedValue(error);

      findCopyItem().props('item').action();
      await waitForPromises();

      expect(Sentry.captureException).toHaveBeenCalledWith(error);
      expect(mockToast.show).not.toHaveBeenCalled();
    });

    // Nothing composes a URL without the Artifact Registry origin, which an instance
    // that has not configured the service does not have.
    it('is left out when no client base URL is provided', () => {
      createComponent({}, { clientBaseUrl: null });

      expect(findCopyItem().exists()).toBe(false);
      expect(findDeleteItem().exists()).toBe(true);
    });
  });

  describe('the Clear cache item', () => {
    it('renders on a remote repository, between the copy and delete items', () => {
      createComponent(remoteRepository());

      expect(findItemTexts()).toEqual(['Copy repository URL', 'Clear cache', 'Delete repository']);
    });

    it('is not marked destructive, because nothing published is removed', () => {
      createComponent(remoteRepository());

      expect(findClearCacheItem().props('item')).toEqual({
        text: 'Clear cache',
        action: expect.any(Function),
      });
    });

    it('is absent on a hosted repository', () => {
      createComponent();

      expect(findClearCacheItem().exists()).toBe(false);
    });

    it('is absent on a virtual repository, whose caches clear from its upstream rows', () => {
      createComponent({ kind: 'VIRTUAL' });

      expect(findItemTexts()).toEqual(['Copy repository URL', 'Delete repository']);
    });
  });

  describe('clearing the cache', () => {
    describe('when the mutation resolves', () => {
      beforeEach(async () => {
        createComponent(remoteRepository());
        await watchPageQueries(getRepositoryPackagesQuery);
        await clearCache();
      });

      it('issues the mutation once, addressing the repository by name', () => {
        expect(clearHandler).toHaveBeenCalledTimes(1);
        expect(clearHandler).toHaveBeenCalledWith({ input: { name: mockRepository.name } });
      });

      it('reports the clear through the toast, with no count', () => {
        expect(mockToast.show).toHaveBeenCalledTimes(1);
        expect(mockToast.show).toHaveBeenCalledWith('Cache successfully cleared.');
      });

      it('refetches the repository and its artifact connection once each', () => {
        expect(detailHandler).toHaveBeenCalledTimes(2);
        expect(packagesHandler).toHaveBeenCalledTimes(2);
        expect(imagesHandler).not.toHaveBeenCalled();
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('on a container repository', () => {
      beforeEach(async () => {
        createComponent(remoteRepository({ format: 'DOCKER' }));
        await watchPageQueries(getRepositoryImagesQuery);
        await clearCache();
      });

      it('refetches the images connection rather than the packages one', () => {
        expect(detailHandler).toHaveBeenCalledTimes(2);
        expect(imagesHandler).toHaveBeenCalledTimes(2);
        expect(packagesHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the payload carries errors', () => {
      beforeEach(async () => {
        createComponent(remoteRepository());
        clearHandler.mockResolvedValue(
          mockClearRepositoryCacheResponse({ errors: ['Repository not found.'] }),
        );
        await watchPageQueries(getRepositoryPackagesQuery);
        await clearCache();
      });

      it('surfaces the error and shows no success toast', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Repository not found.' });
        expect(mockToast.show).not.toHaveBeenCalled();
      });
    });

    describe('when the mutation fails outright', () => {
      beforeEach(async () => {
        createComponent(remoteRepository());
        clearHandler.mockRejectedValue(new Error('Artifact Registry is down'));
        await clearCache();
      });

      it('reports the failure as a page-level alert and shows no success toast', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong. Please try again.',
          error: expect.any(Error),
          captureError: true,
        });
        expect(mockToast.show).not.toHaveBeenCalled();
      });
    });
  });

  describe('the verdicts', () => {
    describe('when the delete repository verdict alone denies', () => {
      beforeEach(() => {
        createComponent(
          remoteRepository(),
          {},
          { props: { permissions: mockRepositoryPermissions({ deleteRepository: false }) } },
        );
      });

      it('renders no Delete repository item', () => {
        expect(findDeleteItem().exists()).toBe(false);
      });

      it('keeps the Clear cache item', () => {
        expect(findItemTexts()).toEqual(['Copy repository URL', 'Clear cache']);
      });
    });

    describe('when the delete artifact verdict alone denies', () => {
      beforeEach(() => {
        createComponent(
          remoteRepository(),
          {},
          { props: { permissions: mockRepositoryPermissions({ deleteArtifact: false }) } },
        );
      });

      it('renders no Clear cache item', () => {
        expect(findClearCacheItem().exists()).toBe(false);
      });

      it('keeps the Delete repository item', () => {
        expect(findItemTexts()).toEqual(['Copy repository URL', 'Delete repository']);
      });
    });

    describe('when every verdict denies', () => {
      describe('and a client base URL is configured', () => {
        beforeEach(() => {
          createComponent(
            remoteRepository(),
            {},
            { props: { permissions: mockDeniedRepositoryPermissions() } },
          );
        });

        it('still renders the kebab, with Copy repository URL as its only item', () => {
          expect(findDropdown().exists()).toBe(true);
          expect(findItemTexts()).toEqual(['Copy repository URL']);
        });
      });

      describe('and no client base URL is configured', () => {
        beforeEach(() => {
          createComponent(
            {},
            { clientBaseUrl: null },
            { props: { permissions: mockDeniedRepositoryPermissions() } },
          );
        });

        it('renders no toggle, because no item remains behind it', () => {
          expect(findDropdown().exists()).toBe(false);
          expect(findItems()).toHaveLength(0);
        });
      });
    });

    describe('before the block has resolved', () => {
      beforeEach(() => {
        createComponent(remoteRepository(), {}, { props: { permissions: undefined } });
      });

      it('renders only the ungated Copy repository URL item', () => {
        expect(findItemTexts()).toEqual(['Copy repository URL']);
      });
    });
  });

  describe('a write the verdict allows and Artifact Registry denies', () => {
    const denial = 'You are not allowed to perform this action.';

    describe('clearing the cache', () => {
      beforeEach(async () => {
        createComponent(
          remoteRepository(),
          {},
          { props: { permissions: mockDeniedRepositoryPermissions({ deleteArtifact: true }) } },
        );
        clearHandler.mockResolvedValue(mockClearRepositoryCacheResponse({ errors: [denial] }));
        await watchPageQueries(getRepositoryPackagesQuery);
        await clearCache();
      });

      it('dispatches the mutation and renders the error it returns', () => {
        expect(clearHandler).toHaveBeenCalledWith({ input: { name: mockRepository.name } });
        expect(createAlert).toHaveBeenCalledWith({ message: denial });
        expect(mockToast.show).not.toHaveBeenCalled();
      });
    });

    describe('deleting the repository', () => {
      beforeEach(async () => {
        createComponent(
          {},
          {},
          {
            props: { permissions: mockDeniedRepositoryPermissions({ deleteRepository: true }) },
            stubs: { DeleteRepositoryModal },
          },
        );
        deleteHandler.mockResolvedValue(mockDeleteRepositoryResponse({ errors: [denial] }));

        findDeleteItem().props('item').action();
        await nextTick();
        findConfirmModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('dispatches the mutation and renders the error it returns', () => {
        expect(deleteHandler).toHaveBeenCalledWith({ input: { name: mockRepository.name } });
        expect(createAlert).toHaveBeenCalledWith({ message: denial });
        expect(mockToast.show).not.toHaveBeenCalled();
      });
    });
  });

  describe('the delete modal', () => {
    it('hands the repository to the modal', () => {
      expect(findDeleteModal().props('repository')).toStrictEqual(mockRepository);
    });

    it('stays closed until the action is chosen', () => {
      expect(findDeleteModal().props('visible')).toBe(false);
    });

    it('opens when the action is chosen', async () => {
      findDeleteItem().props('item').action();
      await nextTick();

      expect(findDeleteModal().props('visible')).toBe(true);
    });

    it('closes again when the modal reports it was dismissed', async () => {
      findDeleteItem().props('item').action();
      await nextTick();

      findDeleteModal().vm.$emit('change', false);
      await nextTick();

      expect(findDeleteModal().props('visible')).toBe(false);
    });
  });
});
