import { InMemoryCache } from '@apollo/client/core';
import {
  possibleTypes,
  typePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import getArtifactQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact.query.graphql';
import getArtifactManifestsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_manifests.query.graphql';
import getArtifactVersionsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_versions.query.graphql';
import getVersionFilesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_version_files.query.graphql';
import getRepositoriesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repositories.query.graphql';
import getRepositoryImagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql';
import getRepositoryQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository.query.graphql';
import getRepositoryUpstreamRepositoriesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.query.graphql';
import getUpstreamRepositoryCandidatesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_upstream_repository_candidates.query.graphql';
import { ARTIFACT_SORT_DEFAULT } from 'ee/packages_and_registries/artifact_registry/constants';
import {
  ARTIFACT_ID_FOR,
  FIRST_PAGE_END_CURSOR,
  ORGANIZATION_GID,
  REPOSITORY_ID,
  mockArtifactRepository,
  mockFirstFilePage,
  mockFirstImagePage,
  mockFirstManifestPage,
  mockFirstVersionPage,
  mockPrefilledRepository,
  mockRepositoriesResponse,
  mockRepository,
  mockRepositoryArtifacts,
  mockRepositoryPage,
  mockRepositoryPermissions,
  mockSecondFilePage,
  mockSecondImagePage,
  mockSecondManifestPage,
  mockSecondVersionPage,
  mockUntouchedRepository,
  mockUpstreamRepositories,
  mockUpstreamRepositoryCandidatePages,
  mockUpstreamRepositoryCandidatesResponse,
  mockVersionDetails,
} from '../mock_data';

describe('Artifact registry cache config', () => {
  describe('the artifact connection policies', () => {
    let cache;

    // A container repository, because `images` is the connection a container format reads.
    const { name, format } = mockUntouchedRepository;

    const variablesFor = (after) => ({
      organizationId: ORGANIZATION_GID,
      name,
      first: 20,
      after,
    });

    const dataFor = (images) => ({
      organization: {
        __typename: 'Organization',
        id: ORGANIZATION_GID,
        artifactRegistryRepository: {
          __typename: 'ArtifactRegistryRepositoryDetails',
          id: REPOSITORY_ID,
          name,
          format,
          images,
        },
      },
    });

    const writePage = (images, after) =>
      cache.writeQuery({
        query: getRepositoryImagesQuery,
        variables: variablesFor(after),
        data: dataFor(images),
      });

    const readPage = (after) =>
      cache.readQuery({ query: getRepositoryImagesQuery, variables: variablesFor(after) })
        .organization.artifactRegistryRepository.images;

    beforeEach(() => {
      cache = new InMemoryCache({ possibleTypes, typePolicies });
    });

    beforeEach(() => {
      writePage(mockFirstImagePage);
      writePage(mockSecondImagePage, FIRST_PAGE_END_CURSOR);
    });

    it('holds every cursor under one entry the incoming page replaces', () => {
      expect(readPage().nodes).toEqual(mockSecondImagePage.nodes);
    });

    it('replaces the page info with it, so the pager follows the rows', () => {
      expect(readPage().pageInfo).toEqual(mockSecondImagePage.pageInfo);
    });
  });

  describe('the files connection policy', () => {
    let cache;

    const { name } = mockUntouchedRepository;
    const versionId = mockVersionDetails().id;

    const variablesFor = (after) => ({
      organizationId: ORGANIZATION_GID,
      name,
      artifactId: ARTIFACT_ID_FOR.MAVEN,
      versionId,
      first: 20,
      after,
    });

    const dataFor = (page) => ({
      organization: {
        __typename: 'Organization',
        id: ORGANIZATION_GID,
        artifactRegistryRepository: {
          __typename: 'ArtifactRegistryRepositoryDetails',
          id: REPOSITORY_ID,
          name,
          format: 'MAVEN',
          kind: 'HOSTED',
          version: {
            __typename: 'ArtifactRegistryVersionDetails',
            id: versionId,
            files: page,
          },
        },
      },
    });

    const writePage = (page, after) =>
      cache.writeQuery({
        query: getVersionFilesQuery,
        variables: variablesFor(after),
        data: dataFor(page),
      });

    const readPage = (after) =>
      cache.readQuery({ query: getVersionFilesQuery, variables: variablesFor(after) }).organization
        .artifactRegistryRepository.version.files;

    beforeEach(() => {
      cache = new InMemoryCache({ possibleTypes, typePolicies });

      writePage(mockFirstFilePage);
      writePage(mockSecondFilePage, FIRST_PAGE_END_CURSOR);
    });

    // Compared by id so the assertion does not depend on which fields this document selects.
    it('holds every cursor under one entry the incoming page replaces', () => {
      expect(readPage().nodes.map(({ id }) => id)).toEqual(
        mockSecondFilePage.nodes.map(({ id }) => id),
      );
    });

    it('replaces the page info with it, so the pager follows the rows', () => {
      expect(readPage().pageInfo).toEqual(mockSecondFilePage.pageInfo);
    });
  });

  describe.each([
    {
      connection: 'versions',
      artifactField: 'package',
      artifactTypename: 'ArtifactRegistryMavenPackageDetails',
      document: getArtifactVersionsQuery,
      format: 'MAVEN',
      artifactId: ARTIFACT_ID_FOR.MAVEN,
      firstPage: mockFirstVersionPage,
      secondPage: mockSecondVersionPage,
    },
    {
      connection: 'manifests',
      artifactField: 'image',
      artifactTypename: 'ArtifactRegistryImage',
      document: getArtifactManifestsQuery,
      format: 'DOCKER',
      artifactId: ARTIFACT_ID_FOR.DOCKER,
      firstPage: mockFirstManifestPage,
      secondPage: mockSecondManifestPage,
    },
  ])(
    'the $connection connection policy',
    ({
      connection,
      artifactField,
      artifactTypename,
      document,
      format,
      artifactId,
      firstPage,
      secondPage,
    }) => {
      let cache;

      const { name } = mockUntouchedRepository;

      const variablesFor = (after, sort = ARTIFACT_SORT_DEFAULT) => ({
        organizationId: ORGANIZATION_GID,
        name,
        artifactId,
        sort,
        first: 20,
        after,
      });

      const dataFor = (page) => ({
        organization: {
          __typename: 'Organization',
          id: ORGANIZATION_GID,
          artifactRegistryRepository: {
            __typename: 'ArtifactRegistryRepositoryDetails',
            id: REPOSITORY_ID,
            name,
            format,
            [artifactField]: {
              __typename: artifactTypename,
              id: artifactId,
              [connection]: page,
            },
          },
        },
      });

      const writePage = (page, after, sort) =>
        cache.writeQuery({
          query: document,
          variables: variablesFor(after, sort),
          data: dataFor(page),
        });

      const readPage = (after, sort) =>
        cache.readQuery({ query: document, variables: variablesFor(after, sort) }).organization
          .artifactRegistryRepository[artifactField][connection];

      beforeEach(() => {
        cache = new InMemoryCache({ possibleTypes, typePolicies });

        writePage(firstPage);
        writePage(secondPage, FIRST_PAGE_END_CURSOR);
      });

      it('holds every cursor under one entry the incoming page replaces', () => {
        expect(readPage().nodes).toEqual(secondPage.nodes);
      });

      it('replaces the page info with it, so the pager follows the rows', () => {
        expect(readPage().pageInfo).toEqual(secondPage.pageInfo);
      });

      // The sort is applied server-side, so each ordering is a distinct result rather than a
      // view of one cached list.
      it('holds a differently sorted page under its own entry', () => {
        writePage(firstPage, undefined, 'CREATED_AT_ASC');

        expect(readPage(undefined, 'CREATED_AT_ASC').nodes).toEqual(firstPage.nodes);
        expect(readPage().nodes).toEqual(secondPage.nodes);
      });

      it('reads no page for a sort nothing has been written under', () => {
        expect(
          cache.readQuery({
            query: document,
            variables: variablesFor(undefined, 'CREATED_AT_ASC'),
          }),
        ).toBe(null);
      });
    },
  );

  describe('the repository key', () => {
    let cache;

    beforeEach(() => {
      cache = new InMemoryCache({ possibleTypes, typePolicies });
    });

    it.each([
      ['ArtifactRegistryRepository', 'ArtifactRegistryRepository:{"name":"my-repository"}'],
      [
        'ArtifactRegistryRepositoryDetails',
        'ArtifactRegistryRepositoryDetails:{"name":"my-repository"}',
      ],
    ])('keys %s on its name, ignoring the Artifact Registry id', (__typename, expected) => {
      const key = cache.identify({
        __typename,
        id: '01a0b226-be19-7bd3-b65a-f842cc8194b7',
        name: 'my-repository',
      });

      expect(key).toBe(expected);
    });

    it('keeps a list distinct when the Artifact Registry id comes back null', () => {
      const variables = { organizationId: ORGANIZATION_GID };
      const data = {
        organization: {
          __typename: 'Organization',
          id: ORGANIZATION_GID,
          artifactRegistryRepositories: {
            ...mockRepositoryPage,
            nodes: [
              { ...mockRepository, id: null, name: 'maven-releases' },
              { ...mockRepository, id: null, name: 'npm-internal' },
            ],
          },
        },
      };

      cache.writeQuery({ query: getRepositoriesQuery, variables, data });

      const { nodes } = cache.readQuery({ query: getRepositoriesQuery, variables }).organization
        .artifactRegistryRepositories;

      expect(nodes.map((node) => node.name)).toEqual(['maven-releases', 'npm-internal']);
    });
  });

  describe('the upstream list policies', () => {
    let cache;

    const { name } = mockUntouchedRepository;

    const variables = { organizationId: ORGANIZATION_GID, name };

    const selected = mockUpstreamRepositories.map(
      ({ upstreamRepository: { format, ...summary }, ...association }) => ({
        ...association,
        upstreamRepository: summary,
      }),
    );

    const writeList = (upstreamRepositories) =>
      cache.writeQuery({
        query: getRepositoryUpstreamRepositoriesQuery,
        variables,
        data: {
          organization: {
            __typename: 'Organization',
            id: ORGANIZATION_GID,
            artifactRegistryRepository: {
              __typename: 'ArtifactRegistryRepositoryDetails',
              id: REPOSITORY_ID,
              name,
              kind: 'VIRTUAL',
              upstreamRepositories,
            },
          },
        },
      });

    const readList = () =>
      cache.readQuery({ query: getRepositoryUpstreamRepositoriesQuery, variables }).organization
        .artifactRegistryRepository.upstreamRepositories;

    beforeEach(() => {
      cache = new InMemoryCache({ possibleTypes, typePolicies });
    });

    it('keys the association on its own id, not on the upstream it points at', () => {
      writeList(selected);

      const key = cache.identify(selected[0]);

      expect(key).toBe(`ArtifactRegistryUpstreamRepositoryAssociation:{"id":"${selected[0].id}"}`);
      expect(key).not.toContain(selected[0].upstreamRepository.id);
    });

    it('leaves the summary unnormalized, embedded in its association', () => {
      writeList(selected);

      expect(cache.identify(selected[0].upstreamRepository)).toBeUndefined();
    });

    it('replaces the whole list on a re-read, without Apollo warning that data was lost', () => {
      writeList(selected);
      writeList(selected.slice(0, 1));

      expect(readList()).toEqual(selected.slice(0, 1));
    });
  });

  describe('the manifests connection policy and the referrer argument', () => {
    let cache;

    const { name } = mockUntouchedRepository;
    const artifactId = ARTIFACT_ID_FOR.DOCKER;

    const variablesFor = (includeReferrers) => ({
      organizationId: ORGANIZATION_GID,
      name,
      artifactId,
      sort: ARTIFACT_SORT_DEFAULT,
      includeReferrers,
      first: 20,
    });

    const dataFor = (page) => ({
      organization: {
        __typename: 'Organization',
        id: ORGANIZATION_GID,
        artifactRegistryRepository: {
          __typename: 'ArtifactRegistryRepositoryDetails',
          id: REPOSITORY_ID,
          name,
          format: 'DOCKER',
          image: {
            __typename: 'ArtifactRegistryImage',
            id: artifactId,
            manifests: page,
          },
        },
      },
    });

    const writePage = (page, includeReferrers) =>
      cache.writeQuery({
        query: getArtifactManifestsQuery,
        variables: variablesFor(includeReferrers),
        data: dataFor(page),
      });

    const readPage = (includeReferrers) =>
      cache.readQuery({
        query: getArtifactManifestsQuery,
        variables: variablesFor(includeReferrers),
      })?.organization.artifactRegistryRepository.image.manifests;

    beforeEach(() => {
      cache = new InMemoryCache({ possibleTypes, typePolicies });
    });

    it('holds each referrer inclusion under its own entry', () => {
      writePage(mockFirstManifestPage, true);
      writePage(mockSecondManifestPage, false);

      expect(readPage(true).nodes).toEqual(mockFirstManifestPage.nodes);
      expect(readPage(false).nodes).toEqual(mockSecondManifestPage.nodes);
    });

    it('reads no page for an inclusion nothing has been written under', () => {
      writePage(mockFirstManifestPage, true);

      expect(readPage(false)).toBeUndefined();
    });

    it('leaves the versions policy keyed on the sort alone', () => {
      expect(typePolicies.ArtifactRegistryMavenPackageDetails.fields.versions.keyArgs).toEqual([
        'sort',
      ]);
      expect(typePolicies.ArtifactRegistryImage.fields.manifests.keyArgs).toEqual([
        'sort',
        'includeReferrers',
      ]);
    });
  });

  describe('the organization repositories policy and the arguments it is keyed on', () => {
    let cache;

    const [firstCandidatePage, secondCandidatePage] = mockUpstreamRepositoryCandidatePages;

    const firstListPage = { ...mockRepositoryPage, nodes: [mockRepository] };

    const secondListPage = { ...mockRepositoryPage, nodes: [mockUntouchedRepository] };

    const candidateVariables = (overrides = {}) => ({
      organizationId: ORGANIZATION_GID,
      kinds: ['HOSTED', 'REMOTE'],
      formats: ['MAVEN'],
      first: 20,
      ...overrides,
    });

    const listVariables = (overrides = {}) => ({
      organizationId: ORGANIZATION_GID,
      format: 'MAVEN',
      kind: 'HOSTED',
      sort: 'LAST_UPDATED_AT_DESC',
      first: 20,
      ...overrides,
    });

    const writeCandidates = (page, overrides) =>
      cache.writeQuery({
        query: getUpstreamRepositoryCandidatesQuery,
        variables: candidateVariables(overrides),
        data: mockUpstreamRepositoryCandidatesResponse(page).data,
      });

    const readCandidates = (overrides) =>
      cache.readQuery({
        query: getUpstreamRepositoryCandidatesQuery,
        variables: candidateVariables(overrides),
      })?.organization.artifactRegistryRepositories;

    const writeList = (page, overrides) =>
      cache.writeQuery({
        query: getRepositoriesQuery,
        variables: listVariables(overrides),
        data: mockRepositoriesResponse(page).data,
      });

    const readList = (overrides) =>
      cache.readQuery({
        query: getRepositoriesQuery,
        variables: listVariables(overrides),
      })?.organization.artifactRegistryRepositories;

    const listNames = (overrides) => readList(overrides).nodes.map(({ name }) => name);

    beforeEach(() => {
      cache = new InMemoryCache({ possibleTypes, typePolicies });
    });

    describe.each([
      { argument: 'formats', changed: { formats: ['DOCKER', 'OCI'] } },
      { argument: 'kinds', changed: { kinds: ['HOSTED'] } },
    ])('the $argument argument the picker narrows by', ({ changed }) => {
      beforeEach(() => {
        writeCandidates(firstCandidatePage);
        writeCandidates(secondCandidatePage, changed);
      });

      it('holds each value under an entry of its own', () => {
        expect(readCandidates().nodes).toEqual(firstCandidatePage.nodes);
        expect(readCandidates(changed).nodes).toEqual(secondCandidatePage.nodes);
      });
    });

    describe.each([
      { argument: 'format', changed: { format: 'NPM' } },
      { argument: 'kind', changed: { kind: 'VIRTUAL' } },
      { argument: 'sort', changed: { sort: 'NAME_ASC' } },
    ])('the $argument argument the list narrows by', ({ changed }) => {
      beforeEach(() => {
        writeList(firstListPage);
        writeList(secondListPage, changed);
      });

      it('holds each value under an entry of its own', () => {
        expect(listNames()).toEqual(['my-repository']);
        expect(listNames(changed)).toEqual(['container-images']);
      });
    });

    it('holds every cursor of one filter under the entry the incoming page replaces', () => {
      writeCandidates(firstCandidatePage);
      writeCandidates(secondCandidatePage, { after: firstCandidatePage.pageInfo.endCursor });

      expect(readCandidates().nodes).toEqual(secondCandidatePage.nodes);
    });

    it('reads no page for a filter nothing has been written under', () => {
      writeCandidates(firstCandidatePage);

      expect(readCandidates({ formats: ['NPM'] })).toBeUndefined();
    });

    it('leaves the list and the picker reading the same field under one policy', () => {
      writeCandidates(firstCandidatePage);
      writeList(firstListPage);

      expect(readCandidates().nodes).toEqual(firstCandidatePage.nodes);
      expect(listNames()).toEqual(['my-repository']);
    });
  });

  describe('the repository verdict policy', () => {
    let cache;

    const { name } = mockRepository;

    const variables = { organizationId: ORGANIZATION_GID, name };

    const response = (repository) => ({
      organization: {
        __typename: 'Organization',
        id: ORGANIZATION_GID,
        artifactRegistryRepository: repository,
      },
    });

    const writeArtifactRead = (userPermissions) =>
      cache.writeQuery({
        query: getArtifactQuery,
        variables: { ...variables, artifactId: ARTIFACT_ID_FOR.MAVEN },
        data: response({
          ...mockArtifactRepository(),
          ...mockRepositoryArtifacts('MAVEN'),
          userPermissions,
        }),
      });

    const writePrefillRead = (userPermissions) =>
      cache.writeQuery({
        query: getRepositoryQuery,
        variables,
        data: response({ ...mockPrefilledRepository(), userPermissions }),
      });

    const readArtifactVerdicts = () =>
      cache.readQuery({
        query: getArtifactQuery,
        variables: { ...variables, artifactId: ARTIFACT_ID_FOR.MAVEN },
      }).organization.artifactRegistryRepository.userPermissions;

    beforeEach(() => {
      cache = new InMemoryCache({ possibleTypes, typePolicies });
    });

    it('keeps every verdict readable after a read selecting fewer of them, without Apollo warning that data was lost', () => {
      writeArtifactRead(mockRepositoryPermissions());
      writePrefillRead({
        __typename: 'ArtifactRegistryRepositoryPermissions',
        updateRepository: true,
        deleteRepository: true,
        deleteArtifact: false,
      });

      expect(readArtifactVerdicts()).toEqual(mockRepositoryPermissions({ deleteArtifact: false }));
    });
  });
});
