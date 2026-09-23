import { gql } from '@apollo/client/core';
import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { createAlert } from '~/alert';
import ErrorsAlert from '~/vue_shared/components/errors_alert.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import NotFound from 'ee/packages_and_registries/artifact_registry/components/not_found.vue';
import FormatLogo from 'ee/packages_and_registries/artifact_registry/repositories/components/format_logo.vue';
import RepositoryForm from 'ee/packages_and_registries/artifact_registry/repositories/components/repository_form.vue';
import RemoteSourceSection from 'ee/packages_and_registries/artifact_registry/repositories/components/remote_source_section.vue';
import RepositoriesEditForm from 'ee/packages_and_registries/artifact_registry/repositories/edit/repositories_edit_form.vue';
import { typePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import { mockResolvers } from 'ee/packages_and_registries/artifact_registry/graphql/mock_resolvers';
import updateRepositoryMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/update_repository.mutation.graphql';
import getRepositoriesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repositories.query.graphql';
import getRepositoryQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository.query.graphql';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import {
  BASE_PATH,
  ORGANIZATION_GID,
  REPOSITORY_CACHE_ID,
  hasCachedRepositoriesConnection,
  mockRepositoryPage,
  mockRepositoryPermissions,
  mockRepositoryResponse,
  mockPrefilledRepository,
  mockUpdateRepositoryResponse,
  mockWritableRemoteSettings,
  mockWrittenRepository,
} from '../../mock_data';

const CHANGED_URL = 'https://mirror.example.com/maven2';

jest.mock('~/alert');

Vue.use(VueApollo);

const REPOSITORY_DETAILS_TYPENAME = 'ArtifactRegistryRepositoryDetails';

const mockRemotePrefill = (overrides = {}) =>
  mockPrefilledRepository({
    kind: 'REMOTE',
    format: 'MAVEN',
    settings: mockWritableRemoteSettings,
    ...overrides,
  });

describe('ArtifactRegistryRepositoriesEditForm', () => {
  let wrapper;
  let router;
  let mockApollo;
  let cache;
  let storedRepository;
  let permissions;
  let prefillHandler;
  let updateHandler;
  let toastShow;

  const mockErrorResponse = (errors) => mockUpdateRepositoryResponse({ repository: null, errors });

  const mockPrefillResponse = () =>
    mockRepositoryResponse({ ...storedRepository, userPermissions: permissions });

  const findHeading = () => wrapper.findComponent(PageHeading);
  const findHeadingLogo = () => wrapper.findComponent(FormatLogo);
  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findHeadingSkeleton = () => findHeading().findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findNotFound = () => wrapper.findComponent(NotFound);
  const findForm = () => wrapper.findComponent(RepositoryForm);
  const findErrorsAlert = () => wrapper.findComponent(ErrorsAlert);
  const findDescription = () => wrapper.findByTestId('repository-description');
  const findSourceSection = () => wrapper.findComponent(RemoteSourceSection);
  const findUrlInput = () => wrapper.findByTestId('remote-source-url');
  const findUsernameInput = () => wrapper.findByTestId('remote-source-username');
  const findPasswordInput = () => wrapper.findByTestId('remote-source-password');

  const seedRepositoriesList = () => {
    cache.writeQuery({
      query: getRepositoriesQuery,
      variables: { organizationId: ORGANIZATION_GID },
      data: {
        organization: {
          __typename: 'Organization',
          id: ORGANIZATION_GID,
          artifactRegistryRepositories: mockRepositoryPage,
        },
      },
    });
  };

  const createComponent = async ({ name = 'my-repository', primed = false } = {}) => {
    toastShow = jest.fn();

    mockApollo = createMockApollo(
      [
        [getRepositoryQuery, prefillHandler],
        [updateRepositoryMutation, updateHandler],
      ],
      mockResolvers,
      { typePolicies: { ...globalTypePolicies, ...typePolicies } },
    );
    cache = mockApollo.clients.defaultClient.cache;

    if (primed) {
      cache.writeQuery({
        query: getRepositoryQuery,
        variables: { organizationId: ORGANIZATION_GID, name },
        data: mockPrefillResponse().data,
      });
    }

    router = createRouter(BASE_PATH);
    await router.push({ name: 'repository_edit', params: { id: name } });

    wrapper = mountExtended(RepositoriesEditForm, {
      router,
      apolloProvider: mockApollo,
      provide: { organizationGid: ORGANIZATION_GID },
      mocks: { $toast: { show: toastShow } },
      attachTo: document.body,
    });
  };

  const createResolvedComponent = async (options) => {
    await createComponent(options);
    await waitForPromises();
  };

  const submitForm = async () => {
    await wrapper.find('form').trigger('submit');
    await waitForPromises();
  };

  beforeEach(() => {
    // The prefill and the write answer from one stored repository, because a save moves the
    // route while the form is still mounted and the prefill re-reads: a read that answered the
    // pre-save repository would overwrite the write in the cache.
    storedRepository = mockWrittenRepository();
    permissions = mockRepositoryPermissions();

    prefillHandler = jest.fn(mockPrefillResponse);
    updateHandler = jest.fn(({ input }) => {
      // Artifact Registry leaves a field the input omits alone, so a write that carries no
      // visibility keeps the stored one rather than clearing it.
      storedRepository = {
        ...storedRepository,
        description: input.description,
        ...(input.visibility ? { visibility: input.visibility } : {}),
      };

      return mockUpdateRepositoryResponse({
        repository: { ...storedRepository, __typename: 'ArtifactRegistryRepository' },
      });
    });
  });

  describe('while the prefill is in flight', () => {
    beforeEach(async () => {
      // Never answers, so the in-flight state is what renders rather than whatever the microtask
      // order leaves on screen.
      prefillHandler.mockReturnValue(new Promise(() => {}));
      await createResolvedComponent();
    });

    it('shows a skeleton', () => {
      expect(findSkeleton().exists()).toBe(true);
    });

    it('does not render the form yet', () => {
      expect(findForm().exists()).toBe(false);
    });
  });

  describe('once the repository resolves', () => {
    beforeEach(async () => {
      await createResolvedComponent();
    });

    it('asks the server for the repository named in the route', () => {
      expect(prefillHandler).toHaveBeenCalledWith({
        organizationId: ORGANIZATION_GID,
        name: 'my-repository',
      });
    });

    it('carries the format logo in the heading', () => {
      expect(findHeadingLogo().props()).toMatchObject({ format: 'MAVEN', size: 48 });
    });

    it('prefills the form with what it read', () => {
      expect(findForm().props('repository')).toMatchObject({
        name: 'my-repository',
        description: 'A hosted Maven repository',
      });
    });

    it('shows the name read-only and offers no format, because both are immutable', () => {
      expect(findForm().props()).toMatchObject({ nameReadonly: true, showFormat: false });
      expect(wrapper.findByTestId('repository-format').exists()).toBe(false);
    });

    // An edit is reached from the repository it edits, so abandoning one returns there
    // rather than to the list the viewer has already left.
    it('cancels back to the repository being edited', () => {
      expect(findForm().props('cancelRoute')).toEqual({
        name: 'repository_detail',
        params: { id: 'my-repository' },
      });
    });

    it('drops the skeleton', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  describe('the page heading', () => {
    it('stands in a skeleton until the prefill answers with a kind to name', async () => {
      prefillHandler.mockReturnValue(new Promise(() => {}));
      await createResolvedComponent();

      expect(findHeadingSkeleton().exists()).toBe(true);
    });

    it('drops the heading skeleton once the prefill answers', async () => {
      await createResolvedComponent();

      expect(findHeadingSkeleton().exists()).toBe(false);
    });

    it.each([
      ['HOSTED', 'Edit hosted repository'],
      ['REMOTE', 'Edit remote repository'],
      ['VIRTUAL', 'Edit virtual repository'],
    ])('names the kind of the %s repository it loaded', async (kind, heading) => {
      storedRepository = mockWrittenRepository({ kind });
      await createResolvedComponent();

      expect(findHeading().text()).toContain(heading);
    });
  });

  describe('when the repository does not resolve', () => {
    beforeEach(async () => {
      prefillHandler.mockResolvedValue(mockRepositoryResponse(null));
      await createResolvedComponent({ name: 'no-such-repository' });
    });

    it('renders the not-found state', () => {
      expect(findNotFound().exists()).toBe(true);
    });

    it('renders nothing else', () => {
      expect(findHeading().exists()).toBe(false);
      expect(findForm().exists()).toBe(false);
    });
  });

  describe('the update verdict', () => {
    describe('when it allows', () => {
      beforeEach(async () => {
        await createResolvedComponent();
      });

      it('renders the form', () => {
        expect(findForm().exists()).toBe(true);
        expect(findNotFound().exists()).toBe(false);
      });
    });

    describe('when it denies', () => {
      beforeEach(async () => {
        permissions = mockRepositoryPermissions({ updateRepository: false });
        await createResolvedComponent();
      });

      it('renders the not-found state', () => {
        expect(findNotFound().exists()).toBe(true);
      });

      it('renders nothing else', () => {
        expect(findHeading().exists()).toBe(false);
        expect(findForm().exists()).toBe(false);
      });
    });
  });

  describe('when the cache already holds the repository', () => {
    let resolvePrefill;

    beforeEach(async () => {
      prefillHandler.mockReturnValue(
        new Promise((resolve) => {
          resolvePrefill = resolve;
        }),
      );
      await createResolvedComponent({ primed: true });
    });

    it('re-reads it from the network', () => {
      expect(prefillHandler).toHaveBeenCalledTimes(1);
    });

    it('holds the form until the network answers', () => {
      expect(findForm().exists()).toBe(false);
      expect(findSkeleton().exists()).toBe(true);
    });

    it('renders the form once the network answer allows', async () => {
      resolvePrefill(mockPrefillResponse());
      await waitForPromises();

      expect(findForm().exists()).toBe(true);
    });
  });

  describe('when the read fails', () => {
    beforeEach(async () => {
      prefillHandler.mockRejectedValue(new Error('Service unavailable'));
      await createResolvedComponent();
    });

    it('says the service is unavailable and nothing else, having no kind to name', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findHeading().exists()).toBe(false);
    });

    it('renders no form to submit', () => {
      expect(findForm().exists()).toBe(false);
    });
  });

  describe('when the form is submitted', () => {
    beforeEach(async () => {
      await createResolvedComponent();
      seedRepositoriesList();
      await findDescription().setValue('Updated');
      await waitForPromises();
      await submitForm();
    });

    // `name` addresses the repository rather than renaming it, and `format` is absent outright:
    // both are immutable at Artifact Registry.
    it('sends the identity and the writable fields only', () => {
      expect(updateHandler).toHaveBeenCalledWith({
        input: {
          name: 'my-repository',
          description: 'Updated',
        },
      });
    });

    it('patches the repository in the cache rather than refetching it', () => {
      expect(cache.extract()[REPOSITORY_CACHE_ID]).toMatchObject({ description: 'Updated' });
    });

    it('leaves the cached repositories connection in place', () => {
      expect(hasCachedRepositoriesConnection(cache)).toBe(true);
    });

    it('shows a success toast', () => {
      expect(toastShow).toHaveBeenCalledWith('Repository was successfully updated.');
    });

    it('lands on the updated repository', () => {
      expect(router.currentRoute.name).toBe('repository_detail');
      expect(router.currentRoute.params.id).toBe('my-repository');
    });

    it('raises no alert', () => {
      expect(createAlert).not.toHaveBeenCalled();
    });
  });

  describe('when the mutation returns a recoverable error', () => {
    beforeEach(async () => {
      updateHandler.mockResolvedValue(mockErrorResponse(['Repository not found.']));
      await createResolvedComponent();
      await submitForm();
    });

    it('renders it above the form rather than as a page-level alert', () => {
      expect(findErrorsAlert().props('errors')).toEqual(['Repository not found.']);
      expect(createAlert).not.toHaveBeenCalled();
    });

    it('stays on the edit view', () => {
      expect(router.currentRoute.name).toBe('repository_edit');
      expect(toastShow).not.toHaveBeenCalled();
    });

    // Otherwise a retry that fails differently shows both sets at once.
    it('drops them when the form is submitted again', async () => {
      updateHandler.mockRejectedValue(new Error('Service unavailable'));
      await submitForm();

      expect(findErrorsAlert().props('errors')).toEqual([]);
    });

    it('clears the errors when the alert is dismissed', async () => {
      findErrorsAlert().vm.$emit('dismiss');
      await waitForPromises();

      expect(findErrorsAlert().props('errors')).toEqual([]);
    });
  });

  describe('when the mutation throws a top-level error', () => {
    beforeEach(async () => {
      updateHandler.mockRejectedValue(new Error('Service unavailable'));
      await createResolvedComponent();
      await submitForm();
    });

    it('raises a generic alert, reports it, and leaves the form rendered', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Something went wrong. Please try again.',
        error: expect.any(Error),
        captureError: true,
      });
      expect(findForm().exists()).toBe(true);
    });
  });

  it('renders no source section when the repository it loaded is hosted', async () => {
    storedRepository = mockPrefilledRepository({ kind: 'HOSTED' });
    await createResolvedComponent();

    expect(findSourceSection().exists()).toBe(false);
  });

  describe('when the repository it loaded is remote', () => {
    beforeEach(async () => {
      storedRepository = mockRemotePrefill();
      await createResolvedComponent();
    });

    it('hands the source section the format the read resolved', () => {
      expect(findSourceSection().props('format')).toBe('MAVEN');
    });

    it('prefills the section with the settings the read resolved', () => {
      expect(findSourceSection().props('settings')).toEqual(mockWritableRemoteSettings);
    });

    it('carries no metadata window through on a container remote', async () => {
      storedRepository = mockRemotePrefill({
        format: 'DOCKER',
        settings: { ...mockWritableRemoteSettings, metadataCacheValidityHours: null },
      });
      await createResolvedComponent();

      expect(findSourceSection().props('settings').metadataCacheValidityHours).toBeNull();
    });
  });

  it('seeds the section empty when the read resolved no settings', async () => {
    storedRepository = mockRemotePrefill({ settings: null });
    await createResolvedComponent();

    expect(findSourceSection().props('settings')).toEqual({});
  });

  it('does not write a remote repository whose credential pair is half filled', async () => {
    storedRepository = mockRemotePrefill();
    await createResolvedComponent();

    await findUsernameInput().setValue('robot');
    await waitForPromises();
    await submitForm();

    expect(updateHandler).not.toHaveBeenCalled();
  });

  it('does not write a remote repository whose upstream URL is empty', async () => {
    storedRepository = mockRemotePrefill();
    await createResolvedComponent();

    await findUrlInput().setValue('');
    await waitForPromises();
    await submitForm();

    expect(updateHandler).not.toHaveBeenCalled();
  });

  it('clears a page-level error from the last attempt when this one fails validation', async () => {
    storedRepository = mockRemotePrefill();
    await createResolvedComponent();

    updateHandler.mockResolvedValue(mockErrorResponse(['Repository not found.']));

    await submitForm();

    expect(findErrorsAlert().props('errors')).toEqual(['Repository not found.']);

    await findUsernameInput().setValue('robot');
    await submitForm();

    expect(findErrorsAlert().props('errors')).toEqual([]);
    expect(findPasswordInput().classes()).toContain('is-invalid');
  });

  describe('when a remote repository is submitted', () => {
    beforeEach(async () => {
      storedRepository = mockRemotePrefill();
      await createResolvedComponent();

      await findUrlInput().setValue(CHANGED_URL);
      await findUsernameInput().setValue('robot');
      await findPasswordInput().setValue('s3cret');
      await waitForPromises();
      await submitForm();
    });

    it('writes through the schema’s own update, the document the hosted edit uses', () => {
      expect(updateHandler).toHaveBeenCalledTimes(1);
    });

    it('carries every value the source section collected', () => {
      expect(updateHandler).toHaveBeenCalledWith({
        input: {
          name: 'my-repository',
          description: storedRepository.description,
          settings: {
            url: CHANGED_URL,
            cacheValidityHours: mockWritableRemoteSettings.cacheValidityHours,
            metadataCacheValidityHours: mockWritableRemoteSettings.metadataCacheValidityHours,
            credentials: { username: 'robot', password: 's3cret' },
          },
        },
      });
    });

    it('shows a success toast and lands on the updated repository', () => {
      expect(toastShow).toHaveBeenCalledWith('Repository was successfully updated.');
      expect(router.currentRoute.name).toBe('repository_detail');
      expect(router.currentRoute.params.id).toBe('my-repository');
    });
  });

  it('sends no credentials key when the pair was left alone', async () => {
    storedRepository = mockRemotePrefill();
    await createResolvedComponent();

    await findUrlInput().setValue(CHANGED_URL);
    await waitForPromises();
    await submitForm();

    expect(updateHandler.mock.calls[0][0].input.settings).toEqual({
      url: CHANGED_URL,
      cacheValidityHours: mockWritableRemoteSettings.cacheValidityHours,
      metadataCacheValidityHours: mockWritableRemoteSettings.metadataCacheValidityHours,
    });
  });

  describe('the cached artifact fields after a remote update', () => {
    const CACHED_IMAGES_FRAGMENT = gql`
      fragment CachedImages on ArtifactRegistryRepositoryDetails {
        images {
          nodes {
            id
          }
        }
      }
    `;

    const repositoryDetailsCacheId = () =>
      cache.identify({
        __typename: REPOSITORY_DETAILS_TYPENAME,
        name: storedRepository.name,
      });

    const seedCachedImages = () =>
      cache.writeFragment({
        id: repositoryDetailsCacheId(),
        fragment: CACHED_IMAGES_FRAGMENT,
        data: {
          __typename: REPOSITORY_DETAILS_TYPENAME,
          images: {
            __typename: 'ArtifactRegistryImageConnection',
            nodes: [
              { __typename: 'ArtifactRegistryImage', id: 'gid://gitlab/ArtifactRegistry::Image/1' },
            ],
          },
        },
      });

    const cachedImages = () => cache.extract()[repositoryDetailsCacheId()]?.images;

    beforeEach(async () => {
      storedRepository = mockRemotePrefill();
      await createResolvedComponent();
      seedCachedImages();
    });

    it('are gone, the write having moved the upstream out from under them', async () => {
      expect(cachedImages()).toBeDefined();

      await findUrlInput().setValue(CHANGED_URL);
      await waitForPromises();
      await submitForm();

      expect(cachedImages()).toBeUndefined();
    });
  });
});
