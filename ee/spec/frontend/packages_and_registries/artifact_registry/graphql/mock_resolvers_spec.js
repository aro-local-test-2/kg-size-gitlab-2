import { createMockClient } from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import {
  manifestLadderFor,
  mockArtifacts,
} from 'ee/packages_and_registries/artifact_registry/graphql/mock_artifacts';
import { mockResolvers } from 'ee/packages_and_registries/artifact_registry/graphql/mock_resolvers';
import getArtifactQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact.query.graphql';
import getManifestReferrersQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest_referrers.query.graphql';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import { ORGANIZATION_GID, REPOSITORY_ID, mockRepositoryPermissions } from '../mock_data';

const REPOSITORY_TYPENAME = 'ArtifactRegistryRepositoryDetails';

// Two names Artifact Registry serves, plus the two edges of the name contract: a single
// character, and one using every separator REPOSITORY_NAME_PATTERN admits.
const NAMES = ['oci-repository', 'maven-repository', 'a', 'x_y.z-9'];

const [NAME] = NAMES;

const CONTAINER_FORMATS = ['DOCKER', 'OCI'];

const PACKAGE_FORMATS = ['MAVEN', 'NPM'];

// Both fields are server-owned but still selected `@client`, with no local typedef declaring
// them, so the mock answers them against the schema's own declarations.
const LOCALLY_ANSWERED_SCHEMA_FIELDS = {
  [REPOSITORY_TYPENAME]: ['manifest'],
  ArtifactRegistryManifestDetails: ['referrers'],
};

describe('Artifact registry mock resolvers', () => {
  // The repository parent the schema resolves: its identity and its format, nothing local.
  const serverParent = (name, format) => ({
    __typename: REPOSITORY_TYPENAME,
    id: REPOSITORY_ID,
    name,
    format,
  });

  const readManifest = (repository, { digest, artifactId }) =>
    mockResolvers.ArtifactRegistryRepositoryDetails.manifest(repository, { digest, artifactId });

  beforeEach(() => {
    // The resolvers' delay is scheduled asynchronously, so advancing Jest's timers cannot
    // reach it; collapsing it keeps these assertions about behavior rather than timing.
    jest.spyOn(global, 'setTimeout').mockImplementation((callback) => callback());
  });

  describe('the fields the local layer still answers', () => {
    // A resolver standing over a field the schema resolves would override the server for every
    // read selecting it, so the mock answers only the fields still read `@client`.
    it.each(Object.keys(mockResolvers))(
      'answers only the %s fields still selected @client',
      (typename) => {
        expect(Object.keys(mockResolvers[typename]).sort()).toEqual(
          [...LOCALLY_ANSWERED_SCHEMA_FIELDS[typename]].sort(),
        );
      },
    );
  });

  describe('the single-manifest read', () => {
    const imageOf = (name, format, index = 0) => mockArtifacts(name, format)[index];

    const indexManifestOf = (image) =>
      manifestLadderFor(image.id).find(({ children }) => children.length > 0);

    const referrerOf = (image) =>
      manifestLadderFor(image.id).find(({ subjectDigest }) => subjectDigest);

    it.each(CONTAINER_FORMATS)('resolves a manifest of a %s repository', async (format) => {
      const image = imageOf(NAME, format);
      const manifest = indexManifestOf(image);

      expect(
        await readManifest(serverParent(NAME, format), {
          digest: manifest.digest,
          artifactId: image.id,
        }),
      ).toEqual(manifest);
    });

    // The schema owns `ArtifactRegistryManifest` and serves the connection under it, so the
    // detail has to answer under a name of its own or the two would collide in the cache.
    it('answers under the local detail typename', async () => {
      const image = imageOf(NAME, 'DOCKER');
      const manifest = indexManifestOf(image);

      const { __typename: typename } = await readManifest(serverParent(NAME, 'DOCKER'), {
        digest: manifest.digest,
        artifactId: image.id,
      });

      expect(typename).toBe('ArtifactRegistryManifestDetails');
    });

    it.each(PACKAGE_FORMATS)(
      'resolves null for a %s repository without looking a manifest up at all',
      async (format) => {
        expect(
          await readManifest(serverParent(NAME, format), {
            digest: 'any-digest',
            artifactId: 'any-image-id',
          }),
        ).toBe(null);
        expect(setTimeout).not.toHaveBeenCalled();
      },
    );

    it('resolves a referrer, which the default list does not show', async () => {
      const image = imageOf(NAME, 'DOCKER');
      const referrer = referrerOf(image);

      const resolved = await readManifest(serverParent(NAME, 'DOCKER'), {
        digest: referrer.digest,
        artifactId: image.id,
      });

      expect(resolved.subjectDigest).toBe(referrer.subjectDigest);
    });

    it('resolves null for a digest this image does not hold', async () => {
      const image = imageOf(NAME, 'DOCKER');

      expect(
        await readManifest(serverParent(NAME, 'DOCKER'), {
          digest: `sha256:${'0'.repeat(64)}`,
          artifactId: image.id,
        }),
      ).toBe(null);
    });

    it('resolves null for a digest another image of the same repository holds', async () => {
      const [image, other] = mockArtifacts(NAME, 'DOCKER');
      const foreign = indexManifestOf(other);

      expect(foreign.digest).not.toBe(indexManifestOf(image).digest);
      expect(
        await readManifest(serverParent(NAME, 'DOCKER'), {
          digest: foreign.digest,
          artifactId: image.id,
        }),
      ).toBe(null);
    });

    it('hands back a copy, so a caller cannot write through to the next read', async () => {
      const image = imageOf(NAME, 'DOCKER');
      const manifest = indexManifestOf(image);
      const args = { digest: manifest.digest, artifactId: image.id };

      const resolved = await readManifest(serverParent(NAME, 'DOCKER'), args);
      resolved.digest = 'rewritten';

      // Must re-read through the resolver: a fresh `manifestLadderFor` build is pristine
      // whatever the resolver handed out, so comparing against one cannot fail.
      expect((await readManifest(serverParent(NAME, 'DOCKER'), args)).digest).toBe(manifest.digest);
    });
  });

  describe('the referrers connection', () => {
    const readReferrers = (manifest, args = {}) =>
      mockResolvers.ArtifactRegistryManifestDetails.referrers(manifest, args);

    const manifestsOf = (format) =>
      mockArtifacts(NAME, format).flatMap(({ id }) => manifestLadderFor(id));

    const manifestThatIs = (format, described, predicate) => {
      const found = manifestsOf(format).find(predicate);

      if (!found) throw new Error(`No ${format} manifest in the seeded ladder is ${described}`);

      return found;
    };

    const attestedManifestOf = (format) =>
      manifestThatIs(format, 'attested', ({ referrersCount }) => referrersCount > 0);

    const unattestedManifestOf = (format) =>
      manifestThatIs(format, 'unattested', ({ referrersCount }) => referrersCount === 0);

    const manifestWithReferrers = (count) => ({
      __typename: 'ArtifactRegistryManifestDetails',
      referrerRows: Array.from({ length: count }, (_, offset) => ({
        __typename: 'ArtifactRegistryManifest',
        digest: `sha256:${String(offset).repeat(64).slice(0, 64)}`,
      })),
    });

    it.each(CONTAINER_FORMATS)(
      'seeds the %s ladder with both an attested manifest and an unattested one',
      (format) => {
        expect(attestedManifestOf(format).referrersCount).toBeGreaterThan(0);
        expect(unattestedManifestOf(format).referrersCount).toBe(0);
      },
    );

    it.each(CONTAINER_FORMATS)('resolves the referrers of a %s manifest', (format) => {
      const manifest = attestedManifestOf(format);

      expect(readReferrers(manifest).nodes).toEqual(manifest.referrerRows);
    });

    it('answers under the connection typename the schema owns', () => {
      const { __typename: typename } = readReferrers(attestedManifestOf('DOCKER'));

      expect(typename).toBe('ArtifactRegistryManifestConnection');
    });

    it('answers with rows of the list element type, not the detail type', () => {
      const manifest = attestedManifestOf('DOCKER');

      expect(readReferrers(manifest).nodes.map(({ __typename: typename }) => typename)).toEqual(
        manifest.referrerRows.map(() => 'ArtifactRegistryManifest'),
      );
    });

    it('names this manifest as the subject of every row it returns', () => {
      const manifest = attestedManifestOf('DOCKER');

      readReferrers(manifest).nodes.forEach(({ subjectDigest }) => {
        expect(subjectDigest).toBe(manifest.digest);
      });
    });

    it('agrees with the count the manifest itself carries', () => {
      const manifest = attestedManifestOf('DOCKER');

      expect(readReferrers(manifest).nodes).toHaveLength(manifest.referrersCount);
    });

    describe('paging', () => {
      it('bounds the page by first, reporting that another page follows', () => {
        const manifest = manifestWithReferrers(3);
        const { nodes, pageInfo } = readReferrers(manifest, { first: 2 });

        expect(nodes).toEqual(manifest.referrerRows.slice(0, 2));
        expect(pageInfo.hasNextPage).toBe(true);
      });

      it('reports no further page when first admits every row', () => {
        const { nodes, pageInfo } = readReferrers(manifestWithReferrers(3), { first: 3 });

        expect(nodes).toHaveLength(3);
        expect(pageInfo.hasNextPage).toBe(false);
      });

      it.each([undefined, null])('returns every row when first is %s', (first) => {
        const manifest = manifestWithReferrers(3);

        expect(readReferrers(manifest, { first }).nodes).toEqual(manifest.referrerRows);
      });

      it('reports no preceding page, and no cursors, until the pager declares them', () => {
        expect(readReferrers(manifestWithReferrers(3)).pageInfo).toMatchObject({
          hasPreviousPage: false,
          startCursor: null,
          endCursor: null,
        });
      });
    });

    describe('a manifest nothing attests to', () => {
      it('resolves an empty connection rather than null, which is not a failure', () => {
        expect(readReferrers(unattestedManifestOf('DOCKER')).nodes).toEqual([]);
      });

      it('reports no further page', () => {
        expect(readReferrers(unattestedManifestOf('DOCKER')).pageInfo.hasNextPage).toBe(false);
      });
    });
  });

  // Calling the resolvers directly says nothing about which parent each one is handed, or how
  // its result merges onto the server's, so these examples compose the map with a client and
  // the app's own documents.
  describe('composed with the query documents into an Apollo client', () => {
    const SERVER_FORMAT = 'NPM';

    const serverRepository = (name, overrides = {}) => ({
      __typename: REPOSITORY_TYPENAME,
      id: REPOSITORY_ID,
      name,
      format: SERVER_FORMAT,
      kind: 'HOSTED',
      visibility: 'PRIVATE',
      description: 'Resolved by the schema',
      artifactsCount: '3',
      downloadsCount: '17',
      sizeBytes: '4096',
      createdAt: '2026-06-01T00:00:00Z',
      lastUpdatedAt: '2026-07-02T00:00:00Z',
      createdBy: null,
      updatedBy: null,
      settings: null,
      userPermissions: {
        __typename: 'ArtifactRegistryRepositoryPermissions',
        updateRepository: true,
        deleteRepository: true,
        deleteArtifact: true,
      },
      ...overrides,
    });

    const organizationResponse = (repository) => ({
      data: {
        organization: {
          __typename: 'Organization',
          id: ORGANIZATION_GID,
          artifactRegistryRepository: repository,
        },
      },
    });

    const repositoryHandler = (repository) => jest.fn(() => organizationResponse(repository));

    const createClient = (handlers) =>
      createMockClient(handlers, mockResolvers, {
        possibleTypes,
        typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
      });

    const read = (client, query, variables) =>
      client
        .query({ query, variables: { organizationId: ORGANIZATION_GID, ...variables } })
        .then(({ data }) => data.organization.artifactRegistryRepository);

    describe('the detail read, whose repository the schema resolves', () => {
      const detailRead = (name) =>
        read(
          createClient([[getRepositoryDetailQuery, repositoryHandler(serverRepository(name))]]),
          getRepositoryDetailQuery,
          { name },
        );

      it.each(NAMES)('answers with the schema’s repository whole for %s', async (name) => {
        expect(await detailRead(name)).toEqual(serverRepository(name));
      });
    });

    describe('the referrers read, composed the way the tab issues it', () => {
      const IMAGE = mockArtifacts(NAME, 'DOCKER')[0];

      const attested = () =>
        manifestLadderFor(IMAGE.id).find(({ referrersCount }) => referrersCount > 0);

      const readReferrers = () => {
        const client = createClient([
          [
            getManifestReferrersQuery,
            // `manifest` is real now, so the server mock carries it; only `referrers` is `@client`.
            repositoryHandler(serverRepository(NAME, { format: 'DOCKER', manifest: attested() })),
          ],
        ]);

        return client
          .query({
            query: getManifestReferrersQuery,
            variables: {
              organizationId: ORGANIZATION_GID,
              name: NAME,
              artifactId: IMAGE.id,
              digest: attested().digest,
              first: 20,
            },
          })
          .then(({ data }) => data.organization.artifactRegistryRepository.manifest);
      };

      it('reaches the nested resolver through the parent manifest and pages its rows', async () => {
        const { referrers } = await readReferrers();

        expect(referrers.nodes.map(({ digest }) => digest)).toEqual(
          attested().referrerRows.map(({ digest }) => digest),
        );
      });
    });

    describe('the artifact read and the detail read, against one repository', () => {
      // NAME says OCI while the schema resolves Maven, so an answer drawn from anywhere but the
      // schema reads as the wrong artifact type in the cache.
      const RESOLVED_FORMAT = 'MAVEN';

      const ARTIFACT = mockArtifacts(NAME, RESOLVED_FORMAT)[0];

      const ARTIFACT_PARENT = {
        ...serverParent(NAME, RESOLVED_FORMAT),
        image: null,
        package: { ...ARTIFACT, __typename: 'ArtifactRegistryMavenPackageDetails' },
        userPermissions: mockRepositoryPermissions(),
      };

      const variables = { organizationId: ORGANIZATION_GID, name: NAME };

      // The artifact read runs first, which is the order a viewer opening an artifact URL in a
      // fresh tab produces.
      const readArtifactThenDetail = async () => {
        const client = createClient([
          [
            getRepositoryDetailQuery,
            repositoryHandler(serverRepository(NAME, { format: RESOLVED_FORMAT })),
          ],
          [getArtifactQuery, repositoryHandler(ARTIFACT_PARENT)],
        ]);

        await client.query({
          query: getArtifactQuery,
          variables: { ...variables, artifactId: ARTIFACT.id },
        });
        await client.query({ query: getRepositoryDetailQuery, variables });

        return client;
      };

      it('leaves one artifact entity under an id, of the type the format decides', async () => {
        const client = await readArtifactThenDetail();

        expect(
          Object.keys(client.cache.extract()).filter((key) => key.endsWith(`:${ARTIFACT.id}`)),
        ).toEqual([`ArtifactRegistryMavenPackageDetails:${ARTIFACT.id}`]);
      });

      // The cache field key follows the arguments the document names, so an artifact id passed
      // here as well would give this read a field of its own, holding a format no other read
      // could correct.
      it('writes the repository under the field key the detail read writes it under', async () => {
        const client = await readArtifactThenDetail();
        const organization = client.cache.extract()[`Organization:${ORGANIZATION_GID}`];

        expect(
          Object.keys(organization).filter((key) => key.startsWith('artifactRegistryRepository')),
        ).toEqual([`artifactRegistryRepository({"name":"${NAME}"})`]);
      });
    });
  });
});
