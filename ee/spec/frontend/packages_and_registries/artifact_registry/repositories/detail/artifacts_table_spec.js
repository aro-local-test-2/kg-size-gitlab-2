import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import { RouterLinkStub } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeDate } from 'helpers/fake_date';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_REMOTE,
} from 'ee/packages_and_registries/artifact_registry/constants';
import { typePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import deleteArtifactMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_artifact.mutation.graphql';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.query.graphql';
import ArtifactsTable from 'ee/packages_and_registries/artifact_registry/repositories/detail/artifacts_table.vue';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  ORGANIZATION_GID,
  REMOTE_LAST_DOWNLOADED_AT,
  REPOSITORY_ID,
  mockDeleteArtifactResponse,
  mockDeniedRepositoryPermissions,
  mockDetailRepository,
  mockRepositoryPermissions,
  mockImagePage,
  mockMavenPackagePage,
  mockNpmPackagePage,
  mockRemoteImagePage,
  mockRemoteMavenPackagePage,
  mockRemoteNpmPackagePage,
  mockRemoteSettings,
  mockRepository,
  mockRepositoryResponse,
} from '../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

describe('ArtifactRegistryArtifactsTable', () => {
  let wrapper;
  let mockApollo;
  let detailHandler;
  let imagesHandler;
  let packagesHandler;
  let deleteHandler;

  const mockToast = { show: jest.fn() };

  useFakeDate(2026, 6, 15);

  const findHeaders = () => wrapper.findAll('th').wrappers.map((th) => th.text());
  const findNameCells = () =>
    wrapper.findAllByTestId('artifact-name').wrappers.map((c) => c.text());
  const findVersionsCells = () =>
    wrapper.findAllByTestId('artifact-versions').wrappers.map((c) => c.text());
  const findNameRoutes = () =>
    wrapper.findAllComponents(RouterLinkStub).wrappers.map((link) => link.props('to'));
  const findDownloadTimes = () =>
    wrapper.findAllComponents(TimeAgoTooltip).wrappers.map((cell) => cell.props('time'));
  // Read off the row rather than off a test id, so a row that renders nothing at all in the
  // column is still comparable with one that renders a timestamp.
  const findLastDownloadedCells = () =>
    wrapper.findAll('tbody tr').wrappers.map((row) => {
      const cells = row.findAll('td').wrappers;

      return cells[cells.length - 2].text();
    });
  const findSortStates = () =>
    wrapper.findAllByRole('columnheader').wrappers.map((header) => header.attributes('aria-sort'));
  const findCopyButtons = () => wrapper.findAllComponents(ClipboardButton);
  const findRowMenus = () => wrapper.findAllComponents(GlDisclosureDropdown);
  const findRowItems = (row = 0) =>
    findRowMenus().at(row).findAllComponents(GlDisclosureDropdownItem);
  const findRowItemTexts = (row = 0) =>
    findRowItems(row).wrappers.map((item) => item.props('item').text);
  const findDeleteCacheEntryItem = (row = 0) =>
    findRowMenus().at(row).findComponent('[data-testid="delete-cache-entry"]');
  const findDeleteItem = (row = 0) =>
    findRowMenus().at(row).findComponent('[data-testid="delete-artifact"]');
  const findDeleteModal = () => wrapper.findComponent(DeleteConfirmationModal);

  const createComponent = ({
    format = 'MAVEN',
    kind = REPOSITORY_KIND_HOSTED,
    artifacts = mockMavenPackagePage.nodes,
    name = mockRepository.name,
    permissions = mockRepositoryPermissions(),
  } = {}) => {
    const artifactRepository = (connection) => ({
      __typename: 'ArtifactRegistryRepository',
      id: REPOSITORY_ID,
      name,
      format,
      ...connection,
    });

    detailHandler = jest.fn().mockResolvedValue(
      mockRepositoryResponse(
        mockDetailRepository(format, {
          name,
          kind,
          settings: kind === REPOSITORY_KIND_REMOTE ? mockRemoteSettings : null,
          userPermissions: mockRepositoryPermissions(),
        }),
      ),
    );
    imagesHandler = jest
      .fn()
      .mockResolvedValue(mockRepositoryResponse(artifactRepository({ images: mockImagePage })));
    packagesHandler = jest
      .fn()
      .mockResolvedValue(
        mockRepositoryResponse(artifactRepository({ packages: mockMavenPackagePage })),
      );
    deleteHandler = jest.fn().mockResolvedValue(mockDeleteArtifactResponse());

    mockApollo = createMockApollo(
      [
        [getRepositoryDetailQuery, detailHandler],
        [getRepositoryImagesQuery, imagesHandler],
        [getRepositoryPackagesQuery, packagesHandler],
        [deleteArtifactMutation, deleteHandler],
      ],
      {},
      { typePolicies: { ...globalTypePolicies, ...typePolicies } },
    );

    wrapper = mountExtended(ArtifactsTable, {
      apolloProvider: mockApollo,
      propsData: { format, kind, artifacts, name, permissions },
      stubs: { RouterLink: RouterLinkStub, DeleteConfirmationModal: true },
      mocks: { $toast: mockToast },
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

  const chooseItem = async (item) => {
    item.props('item').action();
    await waitForPromises();
  };

  describe('the columns a hosted repository’s format calls for', () => {
    it.each([
      ['DOCKER', ['Image', 'Actions'], mockImagePage.nodes],
      ['OCI', ['Image', 'Actions'], mockImagePage.nodes],
      ['MAVEN', ['Package', 'Actions'], mockMavenPackagePage.nodes],
      ['NPM', ['Package', 'Versions', 'Actions'], mockNpmPackagePage.nodes],
    ])('gives a %s repository exactly %j', (format, headers, artifacts) => {
      createComponent({ format, artifacts });

      expect(findHeaders()).toEqual(headers);
    });
  });

  describe('the columns a remote repository’s format calls for', () => {
    it.each([
      ['DOCKER', ['Image', 'Last downloaded', 'Actions'], mockRemoteImagePage.nodes],
      ['OCI', ['Image', 'Last downloaded', 'Actions'], mockRemoteImagePage.nodes],
      ['MAVEN', ['Package', 'Last downloaded', 'Actions'], mockRemoteMavenPackagePage.nodes],
      ['NPM', ['Package', 'Last downloaded', 'Actions'], mockRemoteNpmPackagePage.nodes],
    ])('gives a %s repository exactly %j', (format, headers, artifacts) => {
      createComponent({ format, kind: REPOSITORY_KIND_REMOTE, artifacts });

      expect(findHeaders()).toEqual(headers);
    });
  });

  describe('how a row is named', () => {
    it('names a container image outright', () => {
      createComponent({ format: 'DOCKER', artifacts: mockImagePage.nodes });

      expect(findNameCells()).toEqual(['payment-service', 'api-gateway']);
    });

    it('joins Maven coordinates with a colon', () => {
      createComponent({ format: 'MAVEN', artifacts: mockMavenPackagePage.nodes });

      expect(findNameCells()).toEqual(['com.company.payment:core']);
    });

    it('puts a scoped npm package behind its scope and leaves an unscoped one bare', () => {
      createComponent({ format: 'NPM', artifacts: mockNpmPackagePage.nodes });

      expect(findNameCells()).toEqual(['@company/payment-core', 'design-tokens']);
    });
  });

  describe('for an npm repository', () => {
    beforeEach(() => {
      createComponent({ format: 'NPM', artifacts: mockNpmPackagePage.nodes });
    });

    it('renders the version count, which npm alone reports', () => {
      expect(findVersionsCells()).toEqual(['5', '12']);
    });
  });

  describe('the Last downloaded column a remote repository carries', () => {
    // Nothing has pulled the cached copy, so the cell says nothing rather than dating the
    // download to the epoch.
    it('dates a downloaded artifact and leaves a never-downloaded one blank', () => {
      createComponent({
        format: 'DOCKER',
        kind: REPOSITORY_KIND_REMOTE,
        artifacts: mockRemoteImagePage.nodes,
      });

      expect(findDownloadTimes()).toEqual([REMOTE_LAST_DOWNLOADED_AT]);
      expect(findLastDownloadedCells()[1]).toBe('');
    });
  });

  describe('where a row leads', () => {
    it.each([
      ['DOCKER', mockImagePage.nodes],
      ['OCI', mockImagePage.nodes],
      ['MAVEN', mockMavenPackagePage.nodes],
      ['NPM', mockNpmPackagePage.nodes],
    ])('links every hosted %s row to that artifact version list', (format, artifacts) => {
      createComponent({ format, artifacts, name: 'a-repository' });

      expect(findNameRoutes()).toEqual(
        artifacts.map(({ id }) => ({
          name: 'artifact_versions',
          params: { id: 'a-repository', artifactId: id },
        })),
      );
    });

    it('addresses the artifact by id, never by the name the row renders', () => {
      createComponent({ format: 'MAVEN', artifacts: mockMavenPackagePage.nodes });

      expect(findNameCells()).toEqual(['com.company.payment:core']);
      expect(findNameRoutes()[0].params.artifactId).toBe(mockMavenPackagePage.nodes[0].id);
    });

    // Permanently, not until a later slice: the version list a row would open is served for a
    // hosted repository alone, so a remote row is terminal.
    it.each([
      ['DOCKER', mockRemoteImagePage.nodes],
      ['OCI', mockRemoteImagePage.nodes],
      ['MAVEN', mockRemoteMavenPackagePage.nodes],
      ['NPM', mockRemoteNpmPackagePage.nodes],
    ])('names every remote %s row without linking it', (format, artifacts) => {
      createComponent({ format, kind: REPOSITORY_KIND_REMOTE, artifacts });

      expect(findNameRoutes()).toEqual([]);
      expect(findNameCells()).toHaveLength(artifacts.length);
    });
  });

  // Artifact Registry sorts these rows by name and offers no other column, so the headers carry
  // no sort state for a reader to act on.
  it.each([
    ['hosted', REPOSITORY_KIND_HOSTED, mockNpmPackagePage.nodes],
    ['remote', REPOSITORY_KIND_REMOTE, mockRemoteNpmPackagePage.nodes],
  ])('offers no sort control on a %s table', (_label, kind, artifacts) => {
    createComponent({ format: 'NPM', kind, artifacts });

    expect(findSortStates()).toEqual([undefined, undefined, undefined]);
  });

  describe('when a remote repository has cached nothing', () => {
    const findEmptyRow = () => wrapper.find('tbody').text();

    it.each([
      ['DOCKER', 'No images have been cached yet.'],
      ['OCI', 'No images have been cached yet.'],
      ['MAVEN', 'No packages have been cached yet.'],
      ['NPM', 'No packages have been cached yet.'],
    ])('names the empty %s list', (format, message) => {
      createComponent({ format, kind: REPOSITORY_KIND_REMOTE, artifacts: [] });

      expect(findEmptyRow()).toBe(message);
    });

    it('keeps the column headers, so the page reads as a list that is empty', () => {
      createComponent({ format: 'MAVEN', kind: REPOSITORY_KIND_REMOTE, artifacts: [] });

      expect(findHeaders()).toEqual(['Package', 'Last downloaded', 'Actions']);
    });

    it('renders no such row on a hosted repository', () => {
      createComponent({ format: 'MAVEN', artifacts: [] });

      expect(findEmptyRow()).toBe('');
    });
  });

  it.each([REPOSITORY_KIND_HOSTED, REPOSITORY_KIND_REMOTE])(
    'renders no columns for an unknown format on a %s repository',
    (kind) => {
      createComponent({ format: 'CONDA', kind, artifacts: [] });

      expect(findHeaders()).toEqual([]);
    },
  );

  describe('the copy name action', () => {
    it.each`
      format      | artifacts                     | title                  | names
      ${'DOCKER'} | ${mockImagePage.nodes}        | ${'Copy image name'}   | ${['payment-service', 'api-gateway']}
      ${'OCI'}    | ${mockImagePage.nodes}        | ${'Copy image name'}   | ${['payment-service', 'api-gateway']}
      ${'MAVEN'}  | ${mockMavenPackagePage.nodes} | ${'Copy package name'} | ${['com.company.payment:core']}
      ${'NPM'}    | ${mockNpmPackagePage.nodes}   | ${'Copy package name'} | ${['@company/payment-core', 'design-tokens']}
    `(
      'copies each $format row’s rendered name, naming the family it copies',
      ({ format, artifacts, title, names }) => {
        createComponent({ format, artifacts });

        expect(findCopyButtons().wrappers.map((button) => button.props('text'))).toEqual(names);
        expect(findCopyButtons().wrappers.map((button) => button.props('title'))).toEqual(
          names.map(() => title),
        );
      },
    );

    it('offers it on a remote row too', () => {
      createComponent({
        format: 'MAVEN',
        kind: REPOSITORY_KIND_REMOTE,
        artifacts: mockRemoteMavenPackagePage.nodes,
      });

      expect(findCopyButtons().wrappers.map((button) => button.props('text'))).toEqual([
        'com.company.payment:core',
      ]);
    });

    describe('when the delete verdict denies', () => {
      beforeEach(() => {
        createComponent({
          format: 'DOCKER',
          artifacts: mockImagePage.nodes,
          permissions: mockDeniedRepositoryPermissions(),
        });
      });

      it('stays on every row, since copying is a read', () => {
        expect(findCopyButtons()).toHaveLength(2);
        expect(findRowMenus()).toHaveLength(0);
      });
    });
  });

  describe('the row actions menu', () => {
    it('renders one per row, as an icon-only tertiary toggle naming the row', () => {
      createComponent({ format: 'DOCKER', artifacts: mockImagePage.nodes });

      expect(findRowMenus()).toHaveLength(2);
      expect(findRowMenus().at(0).props()).toMatchObject({
        icon: 'ellipsis_v',
        toggleText: 'More actions for payment-service',
        textSrOnly: true,
        category: 'tertiary',
        noCaret: true,
        placement: 'bottom-end',
      });
    });

    it('names a Maven row by its coordinates', () => {
      createComponent({ format: 'MAVEN', artifacts: mockMavenPackagePage.nodes });

      expect(findRowMenus().at(0).props('toggleText')).toBe(
        'More actions for com.company.payment:core',
      );
    });

    describe('on a remote row', () => {
      beforeEach(() => {
        createComponent({
          format: 'DOCKER',
          kind: REPOSITORY_KIND_REMOTE,
          artifacts: mockRemoteImagePage.nodes,
        });
      });

      it('offers Delete cache entry alone', () => {
        expect(findRowItemTexts()).toEqual(['Delete cache entry']);
        expect(findDeleteItem().exists()).toBe(false);
      });

      it('marks Delete cache entry destructive', () => {
        expect(findDeleteCacheEntryItem().props('item')).toEqual({
          text: 'Delete cache entry',
          variant: 'danger',
          action: expect.any(Function),
        });
      });

      it('renders no confirmation', () => {
        expect(findDeleteModal().exists()).toBe(false);
      });
    });

    describe('on a hosted row', () => {
      it.each([
        ['DOCKER', mockImagePage.nodes, 'Delete image'],
        ['OCI', mockImagePage.nodes, 'Delete image'],
        ['MAVEN', mockMavenPackagePage.nodes, 'Delete package'],
        ['NPM', mockNpmPackagePage.nodes, 'Delete package'],
      ])('offers a destructive delete alone on a %s row', (format, artifacts, text) => {
        createComponent({ format, artifacts });

        expect(findRowItemTexts()).toEqual([text]);
        expect(findDeleteCacheEntryItem().exists()).toBe(false);
        expect(findDeleteItem().props('item')).toEqual({
          text,
          variant: 'danger',
          action: expect.any(Function),
        });
      });
    });
  });

  describe('the delete verdict', () => {
    it('renders a row menu on every row when every other verdict denies', () => {
      createComponent({
        format: 'DOCKER',
        artifacts: mockImagePage.nodes,
        permissions: mockDeniedRepositoryPermissions({ deleteArtifact: true }),
      });

      expect(findRowMenus()).toHaveLength(2);
    });

    describe('when it denies on a hosted repository', () => {
      it.each([
        ['DOCKER', mockImagePage.nodes],
        ['OCI', mockImagePage.nodes],
        ['MAVEN', mockMavenPackagePage.nodes],
        ['NPM', mockNpmPackagePage.nodes],
      ])(
        'renders no row menu on a %s row, since the delete was its only item',
        (format, artifacts) => {
          createComponent({ format, artifacts, permissions: mockDeniedRepositoryPermissions() });

          expect(findRowMenus()).toHaveLength(0);
        },
      );

      it('keeps the rows themselves', () => {
        createComponent({
          format: 'DOCKER',
          artifacts: mockImagePage.nodes,
          permissions: mockDeniedRepositoryPermissions(),
        });

        expect(findNameCells()).toEqual(['payment-service', 'api-gateway']);
      });
    });

    describe('when it denies on a remote repository', () => {
      beforeEach(() => {
        createComponent({
          format: 'DOCKER',
          kind: REPOSITORY_KIND_REMOTE,
          artifacts: mockRemoteImagePage.nodes,
          permissions: mockDeniedRepositoryPermissions(),
        });
      });

      it('renders no row menu, since Delete cache entry was its only item', () => {
        expect(findRowMenus()).toHaveLength(0);
      });

      it('keeps the rows themselves', () => {
        expect(findNameCells()).toEqual(['payment-service', 'api-gateway']);
      });
    });

    describe('when it denies the delete alone', () => {
      it('renders no row menu', () => {
        createComponent({
          format: 'DOCKER',
          artifacts: mockImagePage.nodes,
          permissions: mockRepositoryPermissions({ deleteArtifact: false }),
        });

        expect(findRowMenus()).toHaveLength(0);
      });
    });

    describe('before the verdicts resolve', () => {
      it.each([
        ['hosted', REPOSITORY_KIND_HOSTED, mockImagePage.nodes],
        ['remote', REPOSITORY_KIND_REMOTE, mockRemoteImagePage.nodes],
      ])('renders no row menu on a %s repository', (_label, kind, artifacts) => {
        createComponent({ format: 'DOCKER', kind, artifacts, permissions: null });

        expect(findRowMenus()).toHaveLength(0);
        expect(findNameCells()).toHaveLength(2);
      });
    });
  });

  describe('clearing a remote cache entry', () => {
    const remoteImages = () =>
      createComponent({
        format: 'DOCKER',
        kind: REPOSITORY_KIND_REMOTE,
        artifacts: mockRemoteImagePage.nodes,
      });

    describe('when the mutation resolves', () => {
      beforeEach(async () => {
        remoteImages();
        await watchPageQueries(getRepositoryImagesQuery);
        await chooseItem(findDeleteCacheEntryItem(1));
      });

      it('issues the mutation once, addressing that row by id within the repository', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
        expect(deleteHandler).toHaveBeenCalledWith({
          input: { name: mockRepository.name, id: mockRemoteImagePage.nodes[1].id },
        });
      });

      it('reports the deletion as scheduled through the toast, with no count', () => {
        expect(mockToast.show).toHaveBeenCalledTimes(1);
        expect(mockToast.show).toHaveBeenCalledWith(
          'Cache entry successfully scheduled for deletion.',
        );
      });

      it('refetches the repository and its artifact connection once each', () => {
        expect(detailHandler).toHaveBeenCalledTimes(2);
        expect(imagesHandler).toHaveBeenCalledTimes(2);
        expect(packagesHandler).not.toHaveBeenCalled();
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('while a request for the row is pending', () => {
      let resolveDelete;

      beforeEach(async () => {
        remoteImages();
        deleteHandler.mockReturnValue(
          new Promise((resolve) => {
            resolveDelete = resolve;
          }),
        );
        await watchPageQueries(getRepositoryImagesQuery);

        findDeleteCacheEntryItem().props('item').action();
        findDeleteCacheEntryItem().props('item').action();
        await waitForPromises();
      });

      it('drops a second request for the same row', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
      });

      it('marks that row menu alone as loading', () => {
        expect(findRowMenus().at(0).props('loading')).toBe(true);
        expect(findRowMenus().at(1).props('loading')).toBe(false);
      });

      it('keeps the row menu loading until the refetch lands', async () => {
        resolveDelete(mockDeleteArtifactResponse());
        await nextTick();

        expect(findRowMenus().at(0).props('loading')).toBe(true);

        await waitForPromises();

        expect(findRowMenus().at(0).props('loading')).toBe(false);
      });

      it('still sends a request for another row', async () => {
        await chooseItem(findDeleteCacheEntryItem(1));

        expect(deleteHandler).toHaveBeenCalledTimes(2);
      });

      it('accepts a new request once the first has settled', async () => {
        resolveDelete(mockDeleteArtifactResponse());
        await waitForPromises();
        await chooseItem(findDeleteCacheEntryItem());

        expect(deleteHandler).toHaveBeenCalledTimes(2);
      });
    });

    describe('on a package repository', () => {
      beforeEach(async () => {
        createComponent({
          format: 'MAVEN',
          kind: REPOSITORY_KIND_REMOTE,
          artifacts: mockRemoteMavenPackagePage.nodes,
        });
        await watchPageQueries(getRepositoryPackagesQuery);
        await chooseItem(findDeleteCacheEntryItem());
      });

      it('refetches the packages connection rather than the images one', () => {
        expect(detailHandler).toHaveBeenCalledTimes(2);
        expect(packagesHandler).toHaveBeenCalledTimes(2);
        expect(imagesHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the payload carries errors', () => {
      beforeEach(async () => {
        remoteImages();
        deleteHandler.mockResolvedValue(
          mockDeleteArtifactResponse({ errors: ['Artifact not found.'] }),
        );
        await watchPageQueries(getRepositoryImagesQuery);
        await chooseItem(findDeleteCacheEntryItem());
      });

      it('surfaces the error and shows no success toast', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Artifact not found.' });
        expect(mockToast.show).not.toHaveBeenCalled();
      });
    });

    describe('when the mutation fails outright', () => {
      beforeEach(async () => {
        remoteImages();
        deleteHandler.mockRejectedValue(new Error('Artifact Registry is down'));
        await chooseItem(findDeleteCacheEntryItem());
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

  describe('the confirmation copy each format calls for', () => {
    const IMAGE_BODY =
      'This action permanently deletes image %{name} and all of its manifests. This action cannot be undone.';
    const PACKAGE_BODY =
      'This action permanently deletes package %{name} and all of its versions. This action cannot be undone.';

    it.each`
      format      | artifacts                     | title                | body            | actionText          | name
      ${'DOCKER'} | ${mockImagePage.nodes}        | ${'Delete image?'}   | ${IMAGE_BODY}   | ${'Delete image'}   | ${'payment-service'}
      ${'OCI'}    | ${mockImagePage.nodes}        | ${'Delete image?'}   | ${IMAGE_BODY}   | ${'Delete image'}   | ${'payment-service'}
      ${'MAVEN'}  | ${mockMavenPackagePage.nodes} | ${'Delete package?'} | ${PACKAGE_BODY} | ${'Delete package'} | ${'com.company.payment:core'}
      ${'NPM'}    | ${mockNpmPackagePage.nodes}   | ${'Delete package?'} | ${PACKAGE_BODY} | ${'Delete package'} | ${'@company/payment-core'}
    `(
      'names a $format artifact the way its family is named',
      async ({ format, artifacts, title, body, actionText, name }) => {
        createComponent({ format, artifacts });
        await watchPageQueries(
          format === 'DOCKER' || format === 'OCI'
            ? getRepositoryImagesQuery
            : getRepositoryPackagesQuery,
        );

        findDeleteItem().props('item').action();
        await nextTick();

        expect(findDeleteModal().props()).toMatchObject({ title, body, actionText, name });
      },
    );
  });

  describe('deleting a hosted artifact', () => {
    beforeEach(() => {
      createComponent({ format: 'DOCKER', artifacts: mockImagePage.nodes });
    });

    it('renders the confirmation closed, naming nothing until a row is chosen', () => {
      expect(findDeleteModal().props()).toMatchObject({
        target: null,
        title: 'Delete image?',
        body: 'This action permanently deletes image %{name} and all of its manifests. This action cannot be undone.',
        name: '',
        actionText: 'Delete image',
      });
    });

    it('opens the confirmation on the chosen row and sends nothing', async () => {
      findDeleteItem(1).props('item').action();
      await nextTick();

      expect(findDeleteModal().props('target')).toBe(mockImagePage.nodes[1]);
      expect(findDeleteModal().props('name')).toBe('api-gateway');
      expect(deleteHandler).not.toHaveBeenCalled();
    });

    it('closes again when the confirmation reports it was dismissed', async () => {
      findDeleteItem().props('item').action();
      await nextTick();

      findDeleteModal().vm.$emit('change', null);
      await nextTick();

      expect(findDeleteModal().props('target')).toBeNull();
      expect(deleteHandler).not.toHaveBeenCalled();
    });

    describe('when the confirmation is accepted', () => {
      beforeEach(async () => {
        await watchPageQueries(getRepositoryImagesQuery);
        findDeleteModal().vm.$emit('confirm', mockImagePage.nodes[1]);
        await waitForPromises();
      });

      it('issues the mutation once, addressing the confirmed artifact', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
        expect(deleteHandler).toHaveBeenCalledWith({
          input: { name: mockRepository.name, id: mockImagePage.nodes[1].id },
        });
      });

      it('reports the deletion as scheduled through the toast', () => {
        expect(mockToast.show).toHaveBeenCalledWith('Image successfully scheduled for deletion.');
      });

      it('refetches the repository and its artifact connection once each', () => {
        expect(detailHandler).toHaveBeenCalledTimes(2);
        expect(imagesHandler).toHaveBeenCalledTimes(2);
      });
    });

    it('surfaces a rejected deletion and shows no success toast', async () => {
      deleteHandler.mockResolvedValue(
        mockDeleteArtifactResponse({ errors: ['Artifact not found.'] }),
      );
      await watchPageQueries(getRepositoryImagesQuery);

      findDeleteModal().vm.$emit('confirm', mockImagePage.nodes[0]);
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Artifact not found.' });
      expect(mockToast.show).not.toHaveBeenCalled();
    });
  });

  describe('deleting a hosted package', () => {
    beforeEach(async () => {
      createComponent({ format: 'MAVEN', artifacts: mockMavenPackagePage.nodes });
      await watchPageQueries(getRepositoryPackagesQuery);
    });

    it('names the deletion as a package', async () => {
      findDeleteModal().vm.$emit('confirm', mockMavenPackagePage.nodes[0]);
      await waitForPromises();

      expect(mockToast.show).toHaveBeenCalledWith('Package successfully scheduled for deletion.');
    });
  });
});
