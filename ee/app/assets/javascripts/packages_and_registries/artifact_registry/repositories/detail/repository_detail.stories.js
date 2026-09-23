import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  CLIENT_BASE_URL,
  FIRST_PAGE_END_CURSOR,
  ORGANIZATION_GID,
  SLUG,
  mockClearRepositoryCacheResponse,
  mockDeleteArtifactResponse,
  mockDetailRepository,
  mockEmptyImagePage,
  mockEmptyPackagePage,
  mockFirstImagePage,
  mockFullUpstreamRepositories,
  mockMixedContainerUpstreamRepositories,
  mockRemoteImagePage,
  mockRemoteMavenPackagePage,
  mockRemoteSettings,
  mockRepository,
  mockRepositoryPermissions,
  mockSecondImagePage,
  mockUpstreamRepositories,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from '../../graphql/cache_config';
import clearRepositoryCacheMutation from '../../graphql/mutations/clear_repository_cache.mutation.graphql';
import deleteArtifactMutation from '../../graphql/mutations/delete_artifact.mutation.graphql';
import getRepositoryDetailQuery from '../../graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from '../../graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from '../../graphql/queries/get_repository_packages.query.graphql';
import getRepositoryUpstreamRepositoriesQuery from '../../graphql/queries/get_repository_upstream_repositories.query.graphql';
import { createRouter } from '../../router';
import RepositoryDetail from './repository_detail.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

// Carries a populated table as well as the settings under test, so each health value is seen
// in the page the section actually sits in rather than beside an empty state.
const remoteRepository = (settings) =>
  mockDetailRepository('MAVEN', {
    kind: 'REMOTE',
    settings,
    packages: mockRemoteMavenPackagePage,
  });

export default {
  component: RepositoryDetail,
  title: 'ee/artifact_registry/repositories/detail/repository_detail',
};

const artifactPages = (row) => ({ images: row?.images ?? null, packages: row?.packages ?? null });

const Template =
  (repositoryResolver, pagesFor = artifactPages, upstreamsFor = () => null) =>
  () => {
    // The page reads the repository name from the route, so the story navigates to
    // the detail route before rendering.
    const router = createRouter(BASE_PATH);
    router.push(`/${mockRepository.name}`);

    // Resolved once per render, so every read below describes one repository.
    const repository = Promise.resolve().then(repositoryResolver);

    // Each consumer chains a promise of its own off this one, so this keeps the unavailable
    // story's shared rejection from surfacing as an unhandled one.
    repository.catch(() => {});

    const asDetails = (row) => ({ ...row, __typename: 'ArtifactRegistryRepositoryDetails' });

    const detailHandler = () =>
      repository.then((row) => ({
        data: {
          organization: {
            __typename: 'Organization',
            id: ORGANIZATION_GID,
            artifactRegistryRepository: row && {
              userPermissions: mockRepositoryPermissions(),
              ...asDetails(row),
            },
          },
        },
      }));

    // The page skips both artifact reads until the detail read has answered, so the row is
    // there to take the format off by the time this runs.
    const artifactRepositoryHandler = (variables) =>
      repository.then((row) => ({
        data: {
          organization: {
            __typename: 'Organization',
            id: ORGANIZATION_GID,
            artifactRegistryRepository: {
              __typename: 'ArtifactRegistryRepositoryDetails',
              id: row.id,
              name: variables.name,
              format: row.format,
              ...pagesFor(row, variables),
            },
          },
        },
      }));

    const upstreamRepositoryHandler = (variables) =>
      repository.then((row) => ({
        data: {
          organization: {
            __typename: 'Organization',
            id: ORGANIZATION_GID,
            artifactRegistryRepository: asDetails({
              id: row.id,
              name: variables.name,
              kind: row.kind,
              upstreamRepositories: upstreamsFor(row),
            }),
          },
        },
      }));

    return {
      components: { RepositoryDetail },
      router,
      apolloProvider: createMockApollo(
        [
          [getRepositoryDetailQuery, detailHandler],
          [getRepositoryImagesQuery, artifactRepositoryHandler],
          [getRepositoryPackagesQuery, artifactRepositoryHandler],
          [getRepositoryUpstreamRepositoriesQuery, upstreamRepositoryHandler],
          [clearRepositoryCacheMutation, () => mockClearRepositoryCacheResponse()],
          [deleteArtifactMutation, () => mockDeleteArtifactResponse()],
        ],
        {},
        // Keying the type on `name` - which the view's own policies do - merges the detail
        // read's and the artifact read's field sets onto one entity rather than letting the
        // second write replace the first. The mock cache is built from whatever options it is
        // handed rather than from a merge, so the global policies are handed to it alongside.
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      // The kebab composes its copy-URL item from the slug and the client base URL, so both
      // have to be provided or the item does not render.
      provide: { organizationGid: ORGANIZATION_GID, slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
      template: '<repository-detail />',
    };
  };

export const Default = Template(() => mockDetailRepository());

export const WithoutDescription = Template(() =>
  mockDetailRepository('MAVEN', { description: null }),
);

export const NpmRepository = Template(() => mockDetailRepository('NPM'));

export const ContainerRepository = Template(() => mockDetailRepository('DOCKER'));

// One story per health value, so the three treatments are comparable side by side.
export const RemoteRepository = Template(() => remoteRepository(mockRemoteSettings));

export const RemoteRepositoryUnhealthy = Template(() =>
  remoteRepository({ ...mockRemoteSettings, lastHealthStatus: 'UNHEALTHY' }),
);

// Where a remote sits until something probes it, so it carries no timestamp.
export const RemoteRepositoryNeverVerified = Template(() =>
  remoteRepository({
    ...mockRemoteSettings,
    lastHealthStatus: 'UNKNOWN',
    lastHealthCheckedAt: null,
  }),
);

export const RemoteRepositoryWithoutSettings = Template(() => remoteRepository(null));

export const RemoteRepositoryWithoutArtifacts = Template(() =>
  mockDetailRepository('MAVEN', {
    kind: 'REMOTE',
    settings: mockRemoteSettings,
    packages: mockEmptyPackagePage,
  }),
);

// The container family reads `images` rather than `packages`, so a remote of that family
// exercises the other connection alongside the section.
export const RemoteContainerRepository = Template(() =>
  mockDetailRepository('DOCKER', {
    kind: 'REMOTE',
    settings: mockRemoteSettings,
    images: mockRemoteImagePage,
  }),
);

export const WithoutAttribution = Template(() =>
  mockDetailRepository('MAVEN', { createdBy: null, updatedBy: null }),
);

export const WithoutLastUpdate = Template(() =>
  mockDetailRepository('MAVEN', {
    downloadsCount: '0',
    sizeBytes: '0',
    artifactsCount: '0',
    lastUpdatedAt: null,
    updatedBy: null,
  }),
);

export const WithoutArtifacts = Template(() =>
  mockDetailRepository('DOCKER', { images: mockEmptyImagePage }),
);

export const ArtifactsNotFound = Template(() => mockDetailRepository('DOCKER', { images: null }));

export const ArtifactsUnavailable = Template(
  () => mockDetailRepository('DOCKER'),
  () => {
    throw new Error('Unavailable');
  },
);

export const Paginated = Template(
  () => mockDetailRepository('DOCKER'),
  (_, { after }) => ({
    images: after === FIRST_PAGE_END_CURSOR ? mockSecondImagePage : mockFirstImagePage,
    packages: null,
  }),
);

const virtualRepository = (format) =>
  mockDetailRepository(format, {
    kind: 'VIRTUAL',
    name: mockRepository.name,
    description: null,
  });

export const VirtualRepository = Template(
  () => virtualRepository('MAVEN'),
  artifactPages,
  () => mockUpstreamRepositories,
);

export const VirtualContainerRepository = Template(
  () => virtualRepository('DOCKER'),
  artifactPages,
  () => mockMixedContainerUpstreamRepositories,
);

export const VirtualRepositoryAtCapacity = Template(
  () => virtualRepository('MAVEN'),
  artifactPages,
  () => mockFullUpstreamRepositories,
);

export const VirtualRepositoryWithoutUpstreams = Template(
  () => virtualRepository('MAVEN'),
  artifactPages,
  () => [],
);

export const VirtualUpstreamsNotReturned = Template(
  () => virtualRepository('MAVEN'),
  artifactPages,
  () => null,
);

export const VirtualUpstreamsUnavailable = Template(
  () => virtualRepository('MAVEN'),
  artifactPages,
  () => {
    throw new Error('Unavailable');
  },
);

export const Loading = Template(() => new Promise(() => {}));

export const ServiceUnavailable = Template(() => Promise.reject(new Error('Unavailable')));

export const NotFound = Template(() => null);
