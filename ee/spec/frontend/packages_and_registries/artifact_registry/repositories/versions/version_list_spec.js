import { GlAlert, GlKeysetPagination, GlSkeletonLoader } from '@gitlab/ui';
import { isUndefined, omitBy, pick } from 'lodash-es';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import mavenArtifactFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_artifact.query.graphql.json';
import npmArtifactFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_artifact.npm.query.graphql.json';
import imageArtifactFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_artifact.image.query.graphql.json';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import LocalStorageSync from '~/vue_shared/components/local_storage_sync.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import NotFound from 'ee/packages_and_registries/artifact_registry/components/not_found.vue';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import getArtifactQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact.query.graphql';
import getArtifactManifestsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_manifests.query.graphql';
import getArtifactVersionsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_versions.query.graphql';
import FormatLogo from 'ee/packages_and_registries/artifact_registry/repositories/components/format_logo.vue';
import ArtifactActions from 'ee/packages_and_registries/artifact_registry/repositories/versions/artifact_actions.vue';
import VersionList from 'ee/packages_and_registries/artifact_registry/repositories/versions/version_list.vue';
import VersionsSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/versions_section.vue';
import ViewOptions from 'ee/packages_and_registries/artifact_registry/repositories/versions/view_options.vue';
import {
  ARTIFACT_SORT_DEFAULT,
  GRAPHQL_PAGE_SIZE,
  VERSION_LIST_COLUMNS_STORAGE_KEY,
} from 'ee/packages_and_registries/artifact_registry/constants';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import {
  BASE_PATH,
  FIRST_PAGE_END_CURSOR,
  ORGANIZATION_GID,
  SECOND_PAGE_START_CURSOR,
  mockArtifactRepository,
  mockDeniedRepositoryPermissions,
  mockEmptyManifestPage,
  mockEmptyVersionPage,
  mockFirstManifestPage,
  mockFirstVersionPage,
  mockManifestPage,
  mockManifests,
  mockRepositoryPermissions,
  mockRepositoryResponse,
  createBreadCrumbState,
  mockSecondManifestPage,
  mockSecondVersionPage,
  mockVersionPage,
  mockVersions,
  resetBreadCrumbState,
} from '../../mock_data';

Vue.use(VueApollo);

// The format decides which connection the page reads and which table region renders it, so each
// format is paired with the page it reads and the rows that page carries.
const CONNECTIONS = [
  ['MAVEN', mockVersionPage, mockVersions],
  ['NPM', mockVersionPage, mockVersions],
  ['DOCKER', mockManifestPage, mockManifests],
  ['OCI', mockManifestPage, mockManifests],
];

const PAGE_FOR = Object.fromEntries(CONNECTIONS.map(([format, page]) => [format, page]));

const EMPTY_READ_FOR = {
  MAVEN: { page: mockEmptyVersionPage, holds: 'versions' },
  NPM: { page: mockEmptyVersionPage, holds: 'versions' },
  DOCKER: { page: mockEmptyManifestPage, holds: 'manifests' },
  OCI: { page: mockEmptyManifestPage, holds: 'manifests' },
};

const REPOSITORY_NAME = mockArtifactRepository().name;

const ARTIFACT_FIXTURE = {
  MAVEN: mavenArtifactFixture,
  NPM: npmArtifactFixture,
  DOCKER: imageArtifactFixture,
  OCI: imageArtifactFixture,
};

const serverRepository = (format) => ({
  ...ARTIFACT_FIXTURE[format].data.organization.artifactRegistryRepository,
  format,
});

const serverArtifacts = (format) => {
  const { image, package: artifactPackage } = serverRepository(format);

  return { image, package: artifactPackage };
};

const ARTIFACT_ID_FOR = Object.fromEntries(
  Object.keys(ARTIFACT_FIXTURE).map((format) => {
    const { image, package: artifactPackage } = serverArtifacts(format);

    return [format, (image ?? artifactPackage).id];
  }),
);

const CONNECTION_VARIABLES = ['sort', 'first', 'last', 'before', 'after'];

const MANIFEST_CONNECTION_VARIABLES = [
  'sort',
  'includeReferrers',
  'first',
  'last',
  'before',
  'after',
];

const ARTIFACT_DISPLAY_NAMES = {
  MAVEN: 'com.example.tools:payment-core',
  NPM: '@acme/ui-components',
  DOCKER: 'payment-service',
  OCI: 'payment-service',
};

describe('ArtifactRegistryVersionList', () => {
  let wrapper;
  let state;
  let router;
  let versionsHandler;
  let manifestsHandler;

  afterEach(() => {
    resetBreadCrumbState();
  });

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findNotFound = () => wrapper.findComponent(NotFound);
  const findHeading = () => wrapper.findComponent(PageHeading);
  const findLogo = () => wrapper.findComponent(FormatLogo);
  const findName = () => wrapper.findByTestId('artifact-name');
  const findFormatName = () => wrapper.findByTestId('artifact-format-name');
  const findAnnouncement = () => wrapper.findByTestId('versions-announcement');
  const findVersionsSection = () => wrapper.findComponent(VersionsSection);
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findViewOptions = () => wrapper.findComponent(ViewOptions);
  const findStorageSync = () => wrapper.findComponent(LocalStorageSync);
  const findArtifactActions = () => wrapper.findComponent(ArtifactActions);

  const lastPageArguments = (resolver) => omitBy(resolver.mock.calls.at(-1)[1], isUndefined);

  const columnsKey = (family) => `${VERSION_LIST_COLUMNS_STORAGE_KEY}-${family}`;

  const storeColumns = (family, columns) =>
    localStorage.setItem(columnsKey(family), JSON.stringify(columns));

  // Echoes the name it was asked for, which makes the repository a read addresses legible.
  const repositoryHandler = (format, overrides = {}) =>
    jest.fn(({ name }) =>
      mockRepositoryResponse({ ...serverRepository(format), name, ...overrides }),
    );

  const createComponent = async ({
    format = 'MAVEN',
    handler = repositoryHandler(format),
    connectionResolver = jest.fn().mockResolvedValue(PAGE_FOR[format]),
    path = `/${REPOSITORY_NAME}/${ARTIFACT_ID_FOR[format]}`,
    query = {},
  } = {}) => {
    state = createBreadCrumbState();

    versionsHandler = jest.fn(async (variables) => {
      const response = await handler(variables);
      const repository = response?.data?.organization?.artifactRegistryRepository;

      if (!repository?.package) return response;

      const versions = await connectionResolver(undefined, pick(variables, CONNECTION_VARIABLES));

      return mockRepositoryResponse({
        ...repository,
        package: { ...repository.package, versions },
      });
    });
    manifestsHandler = jest.fn(async (variables) => {
      const response = await handler(variables);
      const repository = response?.data?.organization?.artifactRegistryRepository;

      if (!repository?.image) return response;

      const manifests = await connectionResolver(
        undefined,
        pick(variables, MANIFEST_CONNECTION_VARIABLES),
      );

      return mockRepositoryResponse({
        ...repository,
        image: { ...repository.image, manifests },
      });
    });

    router = createRouter(BASE_PATH, state);
    await router.push({ path, query });

    wrapper = shallowMountExtended(VersionList, {
      router,
      apolloProvider: createMockApollo(
        [
          [getArtifactQuery, handler],
          [getArtifactVersionsQuery, versionsHandler],
          [getArtifactManifestsQuery, manifestsHandler],
        ],
        {},
        // The mock cache is built from whatever options it is handed rather than from a merge,
        // so passing the view's own policies alone would drop every global one.
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: { breadCrumbState: state, organizationGid: ORGANIZATION_GID },
    });

    await nextTick();
  };

  const createResolvedComponent = async (options) => {
    await createComponent(options);
    await waitForPromises();
  };

  it('asks the server for the repository the route names', async () => {
    const handler = repositoryHandler('OCI');

    await createResolvedComponent({
      format: 'OCI',
      handler,
      path: `/payment-core/${ARTIFACT_ID_FOR.OCI}`,
    });

    expect(handler).toHaveBeenCalledWith({
      organizationId: ORGANIZATION_GID,
      name: 'payment-core',
      artifactId: ARTIFACT_ID_FOR.OCI,
    });
  });

  // The format is the schema's answer, so the shape the page renders follows the repository
  // rather than anything the route carried.
  it('reads the artifact off the repository the schema resolved', async () => {
    await createResolvedComponent({ format: 'NPM' });

    expect(findVersionsSection().props('artifact')).toMatchObject(serverArtifacts('NPM').package);
  });

  it('reads a container artifact through the manifests document, not the versions one', async () => {
    await createResolvedComponent({ format: 'DOCKER' });

    expect(manifestsHandler).toHaveBeenCalled();
    expect(versionsHandler).not.toHaveBeenCalled();
  });

  it('hands the sort and the cursor to the server as variables of the versions document', async () => {
    await createResolvedComponent({
      query: { sort: 'created_at_asc', after: FIRST_PAGE_END_CURSOR },
    });

    expect(versionsHandler).toHaveBeenLastCalledWith({
      organizationId: ORGANIZATION_GID,
      name: REPOSITORY_NAME,
      artifactId: ARTIFACT_ID_FOR.MAVEN,
      sort: 'CREATED_AT_ASC',
      first: GRAPHQL_PAGE_SIZE,
      after: FIRST_PAGE_END_CURSOR,
    });
  });

  it('hands the sort, the referrer preference, and the cursor to the server as variables of the manifests document', async () => {
    await createResolvedComponent({
      format: 'DOCKER',
      query: { sort: 'created_at_asc', after: FIRST_PAGE_END_CURSOR },
    });

    expect(manifestsHandler).toHaveBeenLastCalledWith({
      organizationId: ORGANIZATION_GID,
      name: REPOSITORY_NAME,
      artifactId: ARTIFACT_ID_FOR.DOCKER,
      sort: 'CREATED_AT_ASC',
      includeReferrers: true,
      first: GRAPHQL_PAGE_SIZE,
      after: FIRST_PAGE_END_CURSOR,
    });
  });

  it('reads a package artifact through the versions document, not the manifests one', async () => {
    await createResolvedComponent({ format: 'MAVEN' });

    expect(versionsHandler).toHaveBeenCalled();
    expect(manifestsHandler).not.toHaveBeenCalled();
  });

  describe('while the query is in flight', () => {
    beforeEach(async () => {
      await createComponent({ handler: jest.fn(() => new Promise(() => {})) });
    });

    it('renders the skeleton rather than the header', () => {
      expect(findSkeleton().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
    });

    it('announces that the artifact details are loading', () => {
      expect(findAnnouncement().text()).toBe('Loading artifact details.');
    });
  });

  describe.each(CONNECTIONS)('for a %s artifact', (format, page, rows) => {
    const createArtifactComponent = (options) => createResolvedComponent({ format, ...options });

    describe('once the artifact has resolved', () => {
      beforeEach(() => createArtifactComponent());

      it('renders the artifact display name', () => {
        expect(findName().text()).toBe(ARTIFACT_DISPLAY_NAMES[format]);
      });

      it('renders the format logo, naming the format for assistive technology', () => {
        expect(findLogo().props('format')).toBe(format);
        expect(findFormatName().exists()).toBe(true);
      });

      it('renders no error, skeleton, or not-found state', () => {
        expect(findAlert().exists()).toBe(false);
        expect(findSkeleton().exists()).toBe(false);
        expect(findNotFound().exists()).toBe(false);
      });

      it('hands the artifact, the format, and the repository to the heading actions', () => {
        expect(findArtifactActions().props()).toMatchObject({
          format,
          name: REPOSITORY_NAME,
          artifact: expect.objectContaining({ id: ARTIFACT_ID_FOR[format] }),
        });
      });

      it('hands the heading actions the repository verdicts the read carried', () => {
        expect(findArtifactActions().props('permissions')).toEqual(
          serverRepository(format).userPermissions,
        );
      });

      it('hands the table region the same verdicts, which its row delete reads', () => {
        expect(findVersionsSection().props('permissions')).toEqual(
          serverRepository(format).userPermissions,
        );
      });

      it('hands the rows, the format, the artifact, and the repository to the table region', () => {
        expect(findVersionsSection().props()).toMatchObject({
          format,
          name: REPOSITORY_NAME,
          rows,
          artifact: expect.objectContaining({ id: ARTIFACT_ID_FOR[format] }),
          loading: false,
          hasError: false,
        });
      });

      it('announces the version list by name, never by the artifact id', () => {
        expect(findAnnouncement().text()).toBe(
          `Version list for ${ARTIFACT_DISPLAY_NAMES[format]} updated.`,
        );
        expect(findAnnouncement().text()).not.toContain(ARTIFACT_ID_FOR[format]);
      });
    });

    it('reads the connection of the artifact the route names', async () => {
      const connectionResolver = jest.fn().mockResolvedValue(page);

      await createArtifactComponent({ connectionResolver });

      expect(connectionResolver).toHaveBeenCalled();
    });

    describe('while the connection is in flight', () => {
      beforeEach(async () => {
        await createArtifactComponent({ connectionResolver: () => new Promise(() => {}) });
      });

      it('renders the header with the table region loading', () => {
        expect(findHeading().exists()).toBe(true);
        expect(findVersionsSection().props('loading')).toBe(true);
      });

      it('announces that the versions are loading', () => {
        expect(findAnnouncement().text()).toBe('Loading versions.');
      });
    });

    describe('when the connection holds nothing', () => {
      const { page: emptyPage, holds } = EMPTY_READ_FOR[format];

      beforeEach(async () => {
        await createArtifactComponent({
          connectionResolver: jest.fn().mockResolvedValue(emptyPage),
        });
      });

      it('hands an empty page to the table region as a resolved read, not a failed one', () => {
        expect(findVersionsSection().props()).toMatchObject({
          format,
          name: REPOSITORY_NAME,
          rows: [],
          loading: false,
          hasError: false,
        });
      });

      it(`announces that no ${holds} were found, by name rather than by artifact id`, () => {
        expect(findAnnouncement().text()).toBe(
          `No ${holds} found for ${ARTIFACT_DISPLAY_NAMES[format]}.`,
        );
        expect(findAnnouncement().text()).not.toContain(ARTIFACT_ID_FOR[format]);
      });
    });

    describe.each`
      scenario                      | connectionResolver
      ${'the read fails'}           | ${() => Promise.reject(new Error('Unavailable'))}
      ${'the service returns null'} | ${() => null}
    `('when $scenario', ({ connectionResolver }) => {
      beforeEach(async () => {
        await createArtifactComponent({ connectionResolver });
      });

      it('reports the failure in the table region, keeping the header rendered', () => {
        expect(findVersionsSection().props('hasError')).toBe(true);
        expect(findHeading().exists()).toBe(true);
      });

      it('announces the failure', () => {
        expect(findAnnouncement().text()).toBe('The Artifact Registry service is unavailable.');
      });
    });
  });

  describe.each`
    format      | firstPage                | secondPage                | extraArguments
    ${'MAVEN'}  | ${mockFirstVersionPage}  | ${mockSecondVersionPage}  | ${{}}
    ${'DOCKER'} | ${mockFirstManifestPage} | ${mockSecondManifestPage} | ${{ includeReferrers: true }}
  `('the $format pager', ({ format, firstPage, secondPage, extraArguments }) => {
    const argumentsFor = (window) => ({
      sort: ARTIFACT_SORT_DEFAULT,
      ...extraArguments,
      ...window,
    });

    const pagedConnectionResolver = () =>
      jest.fn((_, { after }) => (after === FIRST_PAGE_END_CURSOR ? secondPage : firstPage));

    const pagedComponent = (options = {}) =>
      createResolvedComponent({
        format,
        connectionResolver: pagedConnectionResolver(),
        ...options,
      });

    const renderedIds = () =>
      findVersionsSection()
        .props('rows')
        .map(({ id }) => id);

    const idsOf = ({ nodes }) => nodes.map(({ id }) => id);

    const pageTo = async (query) => {
      await router.push({ query });
      await waitForPromises();
    };

    it('drives the pager from the page info the connection returns', async () => {
      await pagedComponent();

      expect(findPagination().props()).toMatchObject({
        hasNextPage: true,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: FIRST_PAGE_END_CURSOR,
      });
    });

    // `GlKeysetPagination` renders its nav only when one of the two flags is set, so a failed
    // read hides the pager rather than needing it disabled.
    it('hands the pager no page either way when the read failed, which hides it', async () => {
      await createResolvedComponent({
        format,
        connectionResolver: () => Promise.reject(new Error('Unavailable')),
      });

      expect(findPagination().props()).toMatchObject({
        hasNextPage: false,
        hasPreviousPage: false,
      });
    });

    // The previous page stays rendered while the next one loads, so both buttons are still live
    // and a second click would push another cursor over the one in flight.
    it('disables the pager while a page is in flight', async () => {
      await pagedComponent();
      expect(findPagination().props('disabled')).toBe(false);

      await router.push({ query: { after: FIRST_PAGE_END_CURSOR } });
      await nextTick();

      expect(findPagination().props('disabled')).toBe(true);

      await waitForPromises();

      expect(findPagination().props('disabled')).toBe(false);
    });

    it('hands the pager no page either way for a single-page connection, which hides it', async () => {
      await createResolvedComponent({ format });

      expect(findPagination().props()).toMatchObject({
        hasNextPage: false,
        hasPreviousPage: false,
      });
    });

    it('writes the end cursor to the route query, so a page is shareable and survives a reload', async () => {
      await pagedComponent();

      findPagination().vm.$emit('next', FIRST_PAGE_END_CURSOR);
      await waitForPromises();

      expect(router.currentRoute.query).toEqual({ after: FIRST_PAGE_END_CURSOR });
    });

    it('clears the cursor pointing the other way, so the page just asked for is the one read', async () => {
      await pagedComponent();
      await pageTo({ after: FIRST_PAGE_END_CURSOR });

      findPagination().vm.$emit('prev', SECOND_PAGE_START_CURSOR);
      await waitForPromises();

      expect(router.currentRoute.query).toEqual({ before: SECOND_PAGE_START_CURSOR });
    });

    it('leaves query parameters it does not own alone', async () => {
      await pagedComponent({ query: { unrelated: 'kept' } });

      findPagination().vm.$emit('next', FIRST_PAGE_END_CURSOR);
      await waitForPromises();

      expect(router.currentRoute.query).toEqual({
        unrelated: 'kept',
        after: FIRST_PAGE_END_CURSOR,
      });
    });

    it.each`
      page          | query                                   | window
      ${'first'}    | ${{}}                                   | ${{ first: GRAPHQL_PAGE_SIZE }}
      ${'next'}     | ${{ after: FIRST_PAGE_END_CURSOR }}     | ${{ first: GRAPHQL_PAGE_SIZE, after: FIRST_PAGE_END_CURSOR }}
      ${'previous'} | ${{ before: SECOND_PAGE_START_CURSOR }} | ${{ last: GRAPHQL_PAGE_SIZE, before: SECOND_PAGE_START_CURSOR }}
    `('asks the connection for the $page page the route query names', async ({ query, window }) => {
      const connectionResolver = pagedConnectionResolver();

      await pagedComponent({ connectionResolver, query });

      expect(lastPageArguments(connectionResolver)).toStrictEqual(argumentsFor(window));
    });

    describe('paging forward', () => {
      beforeEach(async () => {
        await pagedComponent();
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
      });

      it('renders the next page alone, so a page replaces the previous one rather than extending it', () => {
        expect(renderedIds()).toEqual(idsOf(secondPage));
      });

      it('announces the page it arrived at', () => {
        expect(findAnnouncement().text()).toBe(
          `Version list for ${ARTIFACT_DISPLAY_NAMES[format]} updated.`,
        );
      });
    });

    describe('paging back', () => {
      beforeEach(async () => {
        await pagedComponent();
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
        await pageTo({ before: SECOND_PAGE_START_CURSOR });
      });

      it('renders the first page again', () => {
        expect(renderedIds()).toEqual(idsOf(firstPage));
      });
    });

    describe('returning to a cursor already visited', () => {
      beforeEach(async () => {
        await pagedComponent();
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
        await pageTo({ before: SECOND_PAGE_START_CURSOR });
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
      });

      it('renders the second page rather than the entry the cursor already held', () => {
        expect(renderedIds()).toEqual(idsOf(secondPage));
      });
    });

    it('announces again on a page change, so an unchanged message still reaches a reader', async () => {
      await pagedComponent();

      const populated = findAnnouncement().text();

      await router.push({ query: { after: FIRST_PAGE_END_CURSOR } });
      await nextTick();

      expect(findAnnouncement().text()).toBe('Loading versions.');

      await waitForPromises();

      expect(findAnnouncement().text()).toBe(populated);
    });

    describe('sorting', () => {
      const applySort = async (sort) => {
        findVersionsSection().vm.$emit('sort-changed', sort);
        await waitForPromises();
      };

      it('reads the default sort when the route query names none', async () => {
        const connectionResolver = pagedConnectionResolver();

        await pagedComponent({ connectionResolver });

        expect(lastPageArguments(connectionResolver).sort).toBe(ARTIFACT_SORT_DEFAULT);
        expect(findVersionsSection().props('sort')).toEqual({
          sortBy: 'createdAt',
          sortDesc: true,
        });
      });

      it('writes the sort to the route query lowercased, so an order is shareable', async () => {
        await pagedComponent();

        await applySort({ sortBy: 'createdAt', sortDesc: false });

        expect(router.currentRoute.query).toEqual({ sort: 'created_at_asc' });
      });

      it('reads the sort the route query names back out of it', async () => {
        const connectionResolver = pagedConnectionResolver();

        await pagedComponent({ connectionResolver, query: { sort: 'created_at_asc' } });

        expect(lastPageArguments(connectionResolver).sort).toBe('CREATED_AT_ASC');
        expect(findVersionsSection().props('sort')).toEqual({
          sortBy: 'createdAt',
          sortDesc: false,
        });
      });

      // A cursor is an opaque keyset over the ordering it was cut against, so it cannot carry
      // across a reordering.
      it('drops the active cursor, so a sort change resets to the first page', async () => {
        await pagedComponent();
        await pageTo({ after: FIRST_PAGE_END_CURSOR });

        await applySort({ sortBy: 'createdAt', sortDesc: false });

        expect(router.currentRoute.query).toEqual({ sort: 'created_at_asc' });
        expect(renderedIds()).toEqual(idsOf(firstPage));
      });

      it('keeps the active cursor when the header reports the sort the route already names', async () => {
        await pagedComponent({ query: { sort: 'created_at_asc' } });
        await pageTo({ sort: 'created_at_asc', after: FIRST_PAGE_END_CURSOR });

        await applySort({ sortBy: 'createdAt', sortDesc: false });

        expect(router.currentRoute.query).toEqual({
          sort: 'created_at_asc',
          after: FIRST_PAGE_END_CURSOR,
        });
        expect(renderedIds()).toEqual(idsOf(secondPage));
      });

      it('announces the reordered result set', async () => {
        await pagedComponent();

        await router.push({ query: { sort: 'created_at_asc' } });
        await nextTick();

        expect(findAnnouncement().text()).toBe('Loading versions.');

        await waitForPromises();

        expect(findAnnouncement().text()).toContain('updated');
      });

      it('reads a sort the route query names that the format does not offer as the default', async () => {
        const connectionResolver = pagedConnectionResolver();

        await pagedComponent({ connectionResolver, query: { sort: 'downloads_count_asc' } });

        expect(lastPageArguments(connectionResolver).sort).toBe(ARTIFACT_SORT_DEFAULT);
      });
    });
  });

  describe('the referrer-inclusion argument', () => {
    const referrersFor = async ({ format, query }) => {
      const connectionResolver = jest.fn().mockResolvedValue(PAGE_FOR[format]);

      await createResolvedComponent({ format, connectionResolver, query });

      return lastPageArguments(connectionResolver).includeReferrers;
    };

    it.each(['DOCKER', 'OCI'])("sends true on a %s artifact's first load", async (format) => {
      expect(await referrersFor({ format })).toBe(true);
    });

    it.each(['DOCKER', 'OCI'])('sends false for a %s route query naming it off', async (format) => {
      expect(await referrersFor({ format, query: { include_referrers: 'false' } })).toBe(false);
    });

    it.each(['true', 'maybe', ''])('reads the route value %p as on', async (value) => {
      expect(await referrersFor({ format: 'DOCKER', query: { include_referrers: value } })).toBe(
        true,
      );
    });

    it.each(['MAVEN', 'NPM'])('sends nothing at all on a %s artifact', async (format) => {
      expect(await referrersFor({ format, query: { include_referrers: 'false' } })).toBeUndefined();
    });
  });

  describe('toggling the referrer manifests preference', () => {
    const pagedComponent = (options = {}) =>
      createResolvedComponent({
        format: 'DOCKER',
        connectionResolver: jest.fn((_, { after }) =>
          after === FIRST_PAGE_END_CURSOR ? mockSecondManifestPage : mockFirstManifestPage,
        ),
        ...options,
      });

    const renderedIds = () =>
      findVersionsSection()
        .props('rows')
        .map(({ id }) => id);

    const applyPreference = async (includeReferrers) => {
      findViewOptions().vm.$emit('referrers-changed', includeReferrers);
      await waitForPromises();
    };

    it('drops the active cursor, so a change resets to the first page', async () => {
      await pagedComponent();

      await router.push({ query: { after: FIRST_PAGE_END_CURSOR } });
      await waitForPromises();

      await applyPreference(false);

      expect(router.currentRoute.query).toEqual({ include_referrers: 'false' });
      expect(renderedIds()).toEqual(mockFirstManifestPage.nodes.map(({ id }) => id));
    });

    it('leaves no key behind when switched back on', async () => {
      await pagedComponent({ query: { include_referrers: 'false' } });

      await applyPreference(true);

      expect(router.currentRoute.query).toEqual({});
    });

    it('re-reads the connection with the changed argument', async () => {
      const connectionResolver = jest.fn().mockResolvedValue(mockFirstManifestPage);

      await pagedComponent({ connectionResolver });

      await applyPreference(false);

      expect(lastPageArguments(connectionResolver).includeReferrers).toBe(false);
    });

    it('announces the changed result set', async () => {
      await pagedComponent();

      await router.push({ query: { include_referrers: 'false' } });
      await nextTick();

      expect(findAnnouncement().text()).toBe('Loading versions.');

      await waitForPromises();

      expect(findAnnouncement().text()).toContain('updated');
    });

    it('hands the popover the value the route query names', async () => {
      await pagedComponent({ query: { include_referrers: 'false' } });

      expect(findViewOptions().props('includeReferrers')).toBe(false);
    });
  });

  // Only the versions endpoint sorts on the version column, so the container table is offered
  // no such sort and a route query naming one does not reach the read.
  describe('the sort columns each format offers', () => {
    const sortFor = async ({ format, query }) => {
      const connectionResolver = jest.fn().mockResolvedValue(PAGE_FOR[format]);

      await createResolvedComponent({ format, connectionResolver, query });

      return lastPageArguments(connectionResolver).sort;
    };

    it.each(['MAVEN', 'NPM'])('sorts a %s artifact by version', async (format) => {
      expect(await sortFor({ format, query: { sort: 'version_asc' } })).toBe('VERSION_ASC');
    });

    it.each(['DOCKER', 'OCI'])('does not sort a %s artifact by version', async (format) => {
      expect(await sortFor({ format, query: { sort: 'version_asc' } })).toBe(ARTIFACT_SORT_DEFAULT);
    });
  });

  describe('the column selection', () => {
    useLocalStorageSpy();

    it('hides nothing on a first visit', async () => {
      await createResolvedComponent();

      expect(findVersionsSection().props('hiddenColumns')).toEqual([]);
      expect(findViewOptions().props('hiddenColumns')).toEqual([]);
    });

    // A write on arrival would seed a key the user never touched.
    it('writes nothing until the user changes something', async () => {
      await createResolvedComponent();

      expect(localStorage.setItem).not.toHaveBeenCalled();
    });

    it('restores a stored selection and hands it to the table region', async () => {
      storeColumns('packages', ['source']);

      await createResolvedComponent();

      expect(findVersionsSection().props('hiddenColumns')).toEqual(['source']);
    });

    it('reads the selection of the family the format belongs to', async () => {
      storeColumns('containers', ['size']);

      await createResolvedComponent({ format: 'DOCKER' });

      expect(findVersionsSection().props('hiddenColumns')).toEqual(['size']);
    });

    it('holds a change under the key of the active format family', async () => {
      await createResolvedComponent();

      findViewOptions().vm.$emit('input', ['source']);
      await nextTick();

      expect(findStorageSync().props()).toMatchObject({
        storageKey: columnsKey('packages'),
        value: ['source'],
      });
    });

    // The two families offer different columns, so one selection must never be read as the other.
    it.each`
      format      | family
      ${'MAVEN'}  | ${'packages'}
      ${'DOCKER'} | ${'containers'}
    `('keys a $format selection on the $family family', async ({ format, family }) => {
      await createResolvedComponent({ format });

      expect(findStorageSync().props('storageKey')).toBe(columnsKey(family));
    });

    // The route component is reused across artifacts, so the format flips on a live instance --
    // and the two families must not read or write each other's selection.
    it('re-reads the selection when the format changes under it', async () => {
      storeColumns('packages', ['source']);
      storeColumns('containers', ['size']);

      // The repository the route names answers per artifact, so navigating between a package and
      // a container artifact changes `format` on the mounted component rather than remounting it.
      const formatOf = (artifactId) => (artifactId === ARTIFACT_ID_FOR.DOCKER ? 'DOCKER' : 'MAVEN');

      await createResolvedComponent({
        handler: jest.fn(({ name, artifactId }) =>
          mockRepositoryResponse({ ...serverRepository(formatOf(artifactId)), name }),
        ),
      });

      expect(findVersionsSection().props('hiddenColumns')).toEqual(['source']);

      localStorage.setItem.mockClear();

      await wrapper.vm.$router.push(`/${REPOSITORY_NAME}/${ARTIFACT_ID_FOR.DOCKER}`);
      await waitForPromises();

      expect(findVersionsSection().props('hiddenColumns')).toEqual(['size']);
      expect(findStorageSync().props('storageKey')).toBe(columnsKey('containers'));
      expect(localStorage.setItem).not.toHaveBeenCalled();
    });

    // The popover offers no switch for these, so a stored value naming one would otherwise hide a
    // column with no way to bring it back.
    it.each(['version', 'actions', 'size'])(
      'ignores a stored %s column, which a package artifact offers no switch for',
      async (column) => {
        storeColumns('packages', [column, 'source']);

        await createResolvedComponent();

        expect(findVersionsSection().props('hiddenColumns')).toEqual(['source']);
      },
    );
  });

  describe('the artifact name it publishes for the breadcrumb', () => {
    it('publishes the id-free display name once the artifact resolves', async () => {
      await createResolvedComponent({ format: 'NPM' });

      expect(state.artifactName).toBe(ARTIFACT_DISPLAY_NAMES.NPM);
    });

    it('publishes nothing until the artifact resolves', async () => {
      await createComponent({ handler: jest.fn(() => new Promise(() => {})) });

      expect(state.artifactName).toBe('');
    });

    it('leaves the published name in place when the page goes away', async () => {
      await createResolvedComponent();
      wrapper.destroy();

      expect(state.artifactName).toBe(ARTIFACT_DISPLAY_NAMES.MAVEN);
    });

    it('publishes nothing for an artifact that does not resolve', async () => {
      await createResolvedComponent({
        handler: repositoryHandler('MAVEN', { image: null, package: null }),
      });

      expect(state.artifactName).toBe('');
    });
  });

  // A repository Artifact Registry does not hold and an artifact it holds nothing under render
  // one outcome, so the page never confirms that either exists.
  describe('when the repository is gone', () => {
    beforeEach(async () => {
      await createResolvedComponent({
        handler: jest.fn(() => mockRepositoryResponse(null)),
      });
    });

    it('renders the not-found state alone', () => {
      expect(findNotFound().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });

    it('announces the not-found state rather than an artifact with no name', () => {
      expect(findAnnouncement().text()).toBe('Page not found');
    });

    it('reads no connection off it, so neither document leaves the browser', () => {
      expect(versionsHandler).not.toHaveBeenCalled();
      expect(manifestsHandler).not.toHaveBeenCalled();
    });
  });

  describe('when the artifact is gone', () => {
    beforeEach(async () => {
      await createResolvedComponent({
        handler: repositoryHandler('MAVEN', { image: null, package: null }),
      });
    });

    it('renders the not-found state alone', () => {
      expect(findNotFound().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });

    it('announces the not-found state rather than an artifact with no name', () => {
      expect(findAnnouncement().text()).toBe('Page not found');
    });
  });

  describe('when the read fails', () => {
    beforeEach(async () => {
      await createResolvedComponent({
        handler: jest.fn().mockRejectedValue(new Error('Unavailable')),
      });
    });

    it('renders the service-unavailable alert rather than the not-found state', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findNotFound().exists()).toBe(false);
    });

    it('announces the failure', () => {
      expect(findAnnouncement().text()).toBe('The Artifact Registry service is unavailable.');
    });
  });

  describe('when the cache already holds a denying verdict', () => {
    const artifactPath = `/${REPOSITORY_NAME}/${ARTIFACT_ID_FOR.MAVEN}`;

    let handler;
    let answer;

    const repositoryWith = (userPermissions) => ({ ...serverRepository('MAVEN'), userPermissions });

    const versionsFor = (repository) =>
      jest.fn().mockResolvedValue(
        mockRepositoryResponse({
          ...repository,
          package: { ...repository.package, versions: mockVersionPage },
        }),
      );

    const mountAgainst = async (apolloProvider) => {
      state = createBreadCrumbState();
      router = createRouter(BASE_PATH, state);
      await router.push({ path: artifactPath });

      return shallowMountExtended(VersionList, {
        router,
        apolloProvider,
        provide: { breadCrumbState: state, organizationGid: ORGANIZATION_GID },
      });
    };

    beforeEach(async () => {
      handler = jest
        .fn()
        .mockResolvedValueOnce(
          mockRepositoryResponse(repositoryWith(mockDeniedRepositoryPermissions())),
        )
        .mockReturnValueOnce(
          new Promise((resolve) => {
            answer = resolve;
          }),
        );
      const apolloProvider = createMockApollo(
        [
          [getArtifactQuery, handler],
          [getArtifactVersionsQuery, versionsFor(serverRepository('MAVEN'))],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      );

      const first = await mountAgainst(apolloProvider);
      await waitForPromises();
      first.destroy();

      wrapper = await mountAgainst(apolloProvider);
      await nextTick();
    });

    it('re-reads the repository from the network', () => {
      expect(handler).toHaveBeenCalledTimes(2);
    });

    it('renders the cached artifact rather than the skeleton', () => {
      expect(findSkeleton().exists()).toBe(false);
      expect(findName().text()).toBe(ARTIFACT_DISPLAY_NAMES.MAVEN);
    });

    it('hands the heading actions no verdict while the re-read is in flight', () => {
      expect(findArtifactActions().props('permissions')).toBeNull();
    });

    it('hands the table region no verdict while the re-read is in flight', () => {
      expect(findVersionsSection().props('permissions')).toBeNull();
    });

    it('hands them the verdict once the network answer allows', async () => {
      answer(mockRepositoryResponse(repositoryWith(mockRepositoryPermissions())));
      await waitForPromises();

      expect(findArtifactActions().props('permissions')).toEqual(mockRepositoryPermissions());
      expect(findVersionsSection().props('permissions')).toEqual(mockRepositoryPermissions());
    });

    it('hands them a denying verdict when the network answer denies again', async () => {
      answer(mockRepositoryResponse(repositoryWith(mockDeniedRepositoryPermissions())));
      await waitForPromises();

      expect(findArtifactActions().props('permissions')).toEqual(mockDeniedRepositoryPermissions());
    });
  });
});
