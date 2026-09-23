import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import registryPermissionsFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_registry_permissions.query.graphql.json';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ErrorsAlert from '~/vue_shared/components/errors_alert.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import NotFound from 'ee/packages_and_registries/artifact_registry/components/not_found.vue';
import RemoteSourceSection from 'ee/packages_and_registries/artifact_registry/repositories/components/remote_source_section.vue';
import RepositoriesCreateForm from 'ee/packages_and_registries/artifact_registry/repositories/create/repositories_create_form.vue';
import { typePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import createRepositoryMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/create_repository.mutation.graphql';
import getRegistryPermissionsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_registry_permissions.query.graphql';
import getRepositoriesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repositories.query.graphql';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import {
  BASE_PATH,
  ORGANIZATION_GID,
  REGISTRY_ID,
  cachedRepositoriesConnections,
  hasCachedRepositoriesConnection,
  mockArtifactRegistryResponse,
  mockCreateRepositoryResponse,
  mockDeniedNamespacePermissions,
  mockEmptyRepositoryPage,
  mockWrittenRepository,
} from '../../mock_data';

const UPSTREAM_URL = 'https://repo.maven.apache.org/maven2';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('ArtifactRegistryRepositoriesCreateForm', () => {
  let wrapper;
  let router;
  let cache;
  let createHandler;
  let permissionsHandler;
  let toastShow;

  const mockErrorResponse = (errors) => mockCreateRepositoryResponse({ repository: null, errors });

  const mockDeniedPermissionsResponse = (overrides = {}) =>
    mockArtifactRegistryResponse({
      __typename: 'ArtifactRegistry',
      id: REGISTRY_ID,
      userPermissions: mockDeniedNamespacePermissions(overrides),
    });

  const findHeading = () => wrapper.findComponent(PageHeading);
  const findHeadingDescription = () => wrapper.findByTestId('page-heading-description');
  const findErrorsAlert = () => wrapper.findComponent(ErrorsAlert);
  const findNameInput = () => wrapper.findByTestId('repository-name');
  const findDescription = () => wrapper.findByTestId('repository-description');
  const findFormatListbox = () => wrapper.findComponentByTestId('repository-format');
  const findSubmitButton = () => wrapper.findComponentByTestId('submit-repository');
  const findSourceSection = () => wrapper.findComponent(RemoteSourceSection);
  const findUrlInput = () => wrapper.findByTestId('remote-source-url');
  const findCacheInput = () => wrapper.findByTestId('remote-source-cache-validity');
  const findMetadataCacheInput = () =>
    wrapper.findByTestId('remote-source-metadata-cache-validity');
  const findForm = () => wrapper.find('form');
  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findNotFound = () => wrapper.findComponent(NotFound);
  const findUnavailableAlert = () => wrapper.findComponent(GlAlert);

  const seedRepositoriesList = (variables = {}) => {
    cache.writeQuery({
      query: getRepositoriesQuery,
      variables: { organizationId: ORGANIZATION_GID, ...variables },
      data: {
        organization: {
          __typename: 'Organization',
          id: ORGANIZATION_GID,
          artifactRegistryRepositories: mockEmptyRepositoryPage,
        },
      },
    });
  };

  const createComponent = async ({ path = '/new/hosted', primed = false } = {}) => {
    // A describe that needs another route mounts on top of the outer beforeEach's wrapper,
    // and `GlFormFields` resolves the shared form id to whichever mounted first.
    wrapper?.destroy();

    createHandler = jest.fn().mockResolvedValue(mockCreateRepositoryResponse());
    toastShow = jest.fn();

    const mockApollo = createMockApollo(
      [
        [getRegistryPermissionsQuery, permissionsHandler],
        [createRepositoryMutation, createHandler],
      ],
      {},
      { typePolicies: { ...globalTypePolicies, ...typePolicies } },
    );
    cache = mockApollo.clients.defaultClient.cache;

    if (primed) {
      cache.writeQuery({
        query: getRegistryPermissionsQuery,
        variables: { organizationId: ORGANIZATION_GID },
        data: mockDeniedPermissionsResponse().data,
      });
    }

    router = createRouter(BASE_PATH);
    await router.push(path);

    wrapper = mountExtended(RepositoriesCreateForm, {
      router,
      apolloProvider: mockApollo,
      provide: { organizationGid: ORGANIZATION_GID },
      mocks: { $toast: { show: toastShow } },
      attachTo: document.body,
    });

    await waitForPromises();
  };

  const updateForm = async ({ name = 'my-repository', description } = {}) => {
    await findNameInput().setValue(name);
    if (description !== undefined) await findDescription().setValue(description);
    await waitForPromises();
  };

  const submitForm = async () => {
    await wrapper.find('form').trigger('submit');
    await waitForPromises();
  };

  beforeEach(async () => {
    permissionsHandler = jest.fn().mockResolvedValue(registryPermissionsFixture);

    await createComponent();
  });

  describe('the create verdict', () => {
    it('is asked for with the organization alone', () => {
      expect(permissionsHandler).toHaveBeenCalledTimes(1);
      expect(permissionsHandler).toHaveBeenCalledWith({ organizationId: ORGANIZATION_GID });
    });

    describe('when it allows', () => {
      it('renders the form', () => {
        expect(findForm().exists()).toBe(true);
        expect(findNotFound().exists()).toBe(false);
      });
    });

    describe('when it alone allows among denied verdicts', () => {
      beforeEach(async () => {
        permissionsHandler.mockResolvedValue(
          mockDeniedPermissionsResponse({ createRepository: true }),
        );
        await createComponent();
      });

      it('renders the form', () => {
        expect(findForm().exists()).toBe(true);
        expect(findNotFound().exists()).toBe(false);
      });
    });

    describe('when it denies', () => {
      beforeEach(async () => {
        permissionsHandler.mockResolvedValue(mockDeniedPermissionsResponse());
        await createComponent();
      });

      it('renders the not-found state', () => {
        expect(findNotFound().exists()).toBe(true);
      });

      it('renders nothing else', () => {
        expect(findHeading().exists()).toBe(false);
        expect(findForm().exists()).toBe(false);
      });
    });

    describe('while the read is in flight', () => {
      beforeEach(async () => {
        permissionsHandler.mockReturnValue(new Promise(() => {}));
        await createComponent();
      });

      it('renders neither the form nor the not-found state', () => {
        expect(findForm().exists()).toBe(false);
        expect(findNotFound().exists()).toBe(false);
        expect(findSkeleton().exists()).toBe(true);
      });
    });
  });

  describe('when the cache already holds a denying verdict', () => {
    let resolveRead;

    beforeEach(async () => {
      permissionsHandler.mockClear().mockReturnValue(
        new Promise((resolve) => {
          resolveRead = resolve;
        }),
      );
      await createComponent({ primed: true });
    });

    it('re-reads it from the network', () => {
      expect(permissionsHandler).toHaveBeenCalledTimes(1);
    });

    it('holds both the form and the not-found state until the network answers', () => {
      expect(findForm().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
      expect(findSkeleton().exists()).toBe(true);
    });

    it('renders the form once the network answer allows', async () => {
      resolveRead(registryPermissionsFixture);
      await waitForPromises();

      expect(findForm().exists()).toBe(true);
      expect(findNotFound().exists()).toBe(false);
    });
  });

  describe('when the read fails', () => {
    const readError = new Error('Service unavailable');

    beforeEach(async () => {
      permissionsHandler.mockRejectedValue(readError);
      await createComponent();
    });

    it('renders the unavailable alert alone', () => {
      expect(findUnavailableAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findForm().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
      expect(findHeading().exists()).toBe(false);
    });

    it('reports the error', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
    });
  });

  describe('the page heading', () => {
    it('names the kind the route is creating', () => {
      expect(findHeading().props('heading')).toBe('New hosted repository');
    });

    it('says what a hosted repository is, because the kind is chosen before the form', () => {
      expect(findHeadingDescription().text()).toBe(
        'A hosted repository directly hosts artifacts. You can publish artifacts to and pull them from a hosted repository.',
      );
    });
  });

  describe('on the remote create route', () => {
    beforeEach(async () => {
      await createComponent({ path: '/new/remote' });
    });

    it('names the kind the route is creating', () => {
      expect(findHeading().props('heading')).toBe('New remote repository');
    });

    it('says what a remote repository is', () => {
      expect(findHeadingDescription().text()).toBe(
        'A remote repository points to an external registry. Create a remote repository and connect it to multiple virtual repositories.',
      );
    });
  });

  describe('on the virtual create route', () => {
    beforeEach(async () => {
      await createComponent({ path: '/new/virtual' });
    });

    it('names the kind the route is creating', () => {
      expect(findHeading().props('heading')).toBe('New virtual repository');
    });

    it('says what a virtual repository is', () => {
      expect(findHeadingDescription().text()).toBe(
        'A virtual repository combines other repositories behind one endpoint. It resolves artifacts from an ordered list of upstream repositories.',
      );
    });

    it('renders no source section, which belongs to a remote repository alone', () => {
      expect(findSourceSection().exists()).toBe(false);
    });
  });

  describe('when a virtual repository is submitted', () => {
    beforeEach(async () => {
      await createComponent({ path: '/new/virtual' });
      seedRepositoriesList();
      await updateForm({ description: 'A virtual repository' });
      await submitForm();
    });

    it('issues the create mutation with the kind and the writable fields, and nothing else', () => {
      expect(createHandler).toHaveBeenCalledWith({
        input: {
          kind: 'VIRTUAL',
          format: 'DOCKER',
          name: 'my-repository',
          description: 'A virtual repository',
        },
      });
    });

    it('raises no alert', () => {
      expect(createAlert).not.toHaveBeenCalled();
    });
  });

  describe('when the form is submitted', () => {
    beforeEach(async () => {
      seedRepositoriesList();
      await updateForm({ description: 'A hosted repository' });
      await submitForm();
    });

    it('issues the create mutation with the kind and the writable fields', () => {
      expect(createHandler).toHaveBeenCalledWith({
        input: {
          kind: 'HOSTED',
          format: 'DOCKER',
          name: 'my-repository',
          description: 'A hosted repository',
        },
      });
    });

    it('evicts the cached repositories connection so the list refetches', () => {
      expect(hasCachedRepositoriesConnection(cache)).toBe(false);
    });

    it('shows a success toast', () => {
      expect(toastShow).toHaveBeenCalledWith('Repository was successfully created.');
    });

    it('lands on the created repository', () => {
      expect(router.currentRoute.name).toBe('repository_detail');
      expect(router.currentRoute.params.id).toBe('my-repository');
    });

    it('raises no alert', () => {
      expect(createAlert).not.toHaveBeenCalled();
    });
  });

  describe('when a format other than the default is chosen', () => {
    beforeEach(async () => {
      findFormatListbox().vm.$emit('select', 'MAVEN');
      await updateForm();
      await submitForm();
    });

    it('sends the chosen format', () => {
      expect(createHandler).toHaveBeenCalledWith(
        expect.objectContaining({ input: expect.objectContaining({ format: 'MAVEN' }) }),
      );
    });
  });

  describe('when the mutation returns a recoverable error', () => {
    beforeEach(async () => {
      createHandler.mockResolvedValue(mockErrorResponse(['Name has already been taken.']));
      seedRepositoriesList();
      await updateForm();
      await submitForm();
    });

    it('renders it above the form rather than as a page-level alert', () => {
      expect(findErrorsAlert().props('errors')).toEqual(['Name has already been taken.']);
      expect(createAlert).not.toHaveBeenCalled();
    });

    // Otherwise a retry that fails differently shows both sets at once.
    it('drops them when the form is submitted again', async () => {
      createHandler.mockRejectedValue(new Error('Service unavailable'));
      await submitForm();

      expect(findErrorsAlert().props('errors')).toEqual([]);
    });

    it('clears the errors when the alert is dismissed', async () => {
      findErrorsAlert().vm.$emit('dismiss');
      await waitForPromises();

      expect(findErrorsAlert().props('errors')).toEqual([]);
    });

    it('leaves the cached repositories connection in place', () => {
      expect(hasCachedRepositoriesConnection(cache)).toBe(true);
    });

    it('stays on the create view', () => {
      expect(router.currentRoute.name).toBe('repository_new_hosted');
    });

    it('shows no success toast', () => {
      expect(toastShow).not.toHaveBeenCalled();
    });

    it('re-enables the submit button', () => {
      expect(findSubmitButton().props('loading')).toBe(false);
    });
  });

  describe('when the mutation returns several recoverable errors', () => {
    beforeEach(async () => {
      createHandler.mockResolvedValue(
        mockErrorResponse(['Name has already been taken.', 'Format is not supported.']),
      );
      await updateForm();
      await submitForm();
    });

    it('renders them as a list rather than one run-on sentence', () => {
      expect(findErrorsAlert().props('errors')).toEqual([
        'Name has already been taken.',
        'Format is not supported.',
      ]);
    });
  });

  it('renders no source section on the hosted route, which carries no settings', () => {
    expect(findSourceSection().exists()).toBe(false);
  });

  describe('when a remote repository is created', () => {
    const createRemoteComponent = () => createComponent({ path: '/new/remote' });

    const fillRemoteForm = async () => {
      findFormatListbox().vm.$emit('select', 'MAVEN');
      await updateForm({ name: 'my-remote-repository', description: 'A remote repository' });
      await findUrlInput().setValue(UPSTREAM_URL);
      await waitForPromises();
    };

    beforeEach(async () => {
      await createRemoteComponent();

      createHandler.mockResolvedValue(
        mockCreateRepositoryResponse({ repository: mockWrittenRepository({ kind: 'REMOTE' }) }),
      );
    });

    it('renders the source section in create mode', () => {
      expect(findSourceSection().props('createMode')).toBe(true);
    });

    it('hands the section the format the form is on', async () => {
      expect(findSourceSection().props('format')).toBe('DOCKER');

      findFormatListbox().vm.$emit('select', 'MAVEN');
      await waitForPromises();

      expect(findSourceSection().props('format')).toBe('MAVEN');
    });

    it('makes no write with the upstream URL empty, flagging the field instead', async () => {
      await updateForm({ name: 'my-remote-repository' });
      await submitForm();

      expect(createHandler).not.toHaveBeenCalled();
      expect(findUrlInput().classes()).toContain('is-invalid');
    });

    describe('and the write goes out', () => {
      beforeEach(async () => {
        await fillRemoteForm();
        await submitForm();
      });

      it('sends the kind, the upstream URL, and no window left alone', () => {
        expect(createHandler).toHaveBeenCalledWith({
          input: {
            kind: 'REMOTE',
            format: 'MAVEN',
            name: 'my-remote-repository',
            description: 'A remote repository',
            settings: { url: UPSTREAM_URL },
          },
        });
      });

      it('shows a success toast and lands on the created repository', () => {
        expect(toastShow).toHaveBeenCalledWith('Repository was successfully created.');
        expect(router.currentRoute.name).toBe('repository_detail');
        expect(router.currentRoute.params.id).toBe('my-repository');
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    it('sends the windows the viewer set and omits the one left alone', async () => {
      await fillRemoteForm();
      await findCacheInput().setValue('72');
      await waitForPromises();
      await submitForm();

      expect(createHandler.mock.calls[0][0].input.settings).toEqual({
        url: UPSTREAM_URL,
        cacheValidityHours: 72,
      });
    });

    it('sends both windows once both are set', async () => {
      await fillRemoteForm();
      await findCacheInput().setValue('72');
      await findMetadataCacheInput().setValue('6');
      await waitForPromises();
      await submitForm();

      expect(createHandler.mock.calls[0][0].input.settings).toEqual({
        url: UPSTREAM_URL,
        cacheValidityHours: 72,
        metadataCacheValidityHours: 6,
      });
    });

    it('evicts every cached repositories variant, so each view refetches', async () => {
      seedRepositoriesList();
      seedRepositoriesList({ kind: 'REMOTE' });

      expect(cachedRepositoriesConnections(cache)).toHaveLength(2);

      await fillRemoteForm();
      await submitForm();

      expect(cachedRepositoriesConnections(cache)).toEqual([]);
    });
  });

  describe('when the mutation throws a top-level error', () => {
    beforeEach(async () => {
      createHandler.mockRejectedValue(new Error('Service unavailable'));
      await updateForm();
      await submitForm();
    });

    it('raises a generic alert, reports it, and leaves the view rendered', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Something went wrong. Please try again.',
        error: expect.any(Error),
        captureError: true,
      });
      expect(findFormatListbox().exists()).toBe(true);
      expect(findSubmitButton().exists()).toBe(true);
    });

    it('re-enables the submit button', () => {
      expect(findSubmitButton().props('loading')).toBe(false);
    });
  });
});
