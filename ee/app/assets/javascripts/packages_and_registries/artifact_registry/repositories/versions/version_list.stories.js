import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { saveStorageValue } from '~/lib/utils/local_storage';
import {
  CLIENT_BASE_URL,
  ORGANIZATION_GID,
  SLUG,
  mockArtifactRepository,
  mockEmptyManifestPage,
  mockEmptyVersionPage,
  mockFirstVersionPage,
  mockManifestPage,
  mockRepository,
  mockRepositoryPermissions,
  mockRepositoryResponse,
  mockSecondVersionPage,
  mockVersionPage,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import {
  VERSION_LIST_COLUMNS_STORAGE_KEY,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS,
} from '../../constants';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from '../../graphql/cache_config';
import { mockArtifacts } from '../../graphql/mock_artifacts';
import getArtifactQuery from '../../graphql/queries/get_artifact.query.graphql';
import getArtifactManifestsQuery from '../../graphql/queries/get_artifact_manifests.query.graphql';
import getArtifactVersionsQuery from '../../graphql/queries/get_artifact_versions.query.graphql';
import { createRouter } from '../../router';
import { isContainerFormat, versionListFamily } from '../../utils';
import VersionList from './version_list.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

// The single-package read returns the detail union, so a package spread on
// `... on ArtifactRegistry*PackageDetails` needs the detail typename; the generator stamps the
// plain one the `packages` list returns. Containers keep their plain image type.
const asDetailPackage = (format, artifact) => ({
  ...artifact,
  __typename:
    format === 'NPM'
      ? TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS
      : TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS,
});

const artifactFields = (format) => {
  const [artifact] = mockArtifacts(mockRepository.name, format);

  return isContainerFormat(format)
    ? { image: artifact }
    : { package: asDetailPackage(format, artifact) };
};

const repositoryHandler = (format) => () =>
  Promise.resolve(
    mockRepositoryResponse({
      ...mockArtifactRepository(format),
      ...artifactFields(format),
      userPermissions: mockRepositoryPermissions(),
    }),
  );

const defaultVersionsPage = () => mockVersionPage;

const defaultManifestsPage = () => mockManifestPage;

const versionsHandler = (format, versionsPage) => (variables) =>
  Promise.resolve(versionsPage(variables)).then((versions) =>
    mockRepositoryResponse({
      ...mockArtifactRepository(format),
      package: {
        ...asDetailPackage(format, mockArtifacts(mockRepository.name, format)[0]),
        versions,
      },
    }),
  );

const manifestsHandler = (format, manifestsPage) => (variables) =>
  Promise.resolve(manifestsPage(variables)).then((manifests) =>
    mockRepositoryResponse({
      ...mockArtifactRepository(format),
      image: { ...mockArtifacts(mockRepository.name, format)[0], manifests },
    }),
  );

// The artifact the generator holds first, whose id the route below names.
const generatedArtifactId = (format) => mockArtifacts(mockRepository.name, format)[0].id;

export default {
  component: VersionList,
  title: 'ee/artifact_registry/repositories/versions/version_list',
};

const Template =
  ({
    format = 'MAVEN',
    handler = repositoryHandler(format),
    artifactId = generatedArtifactId(format),
    versionsPage = defaultVersionsPage,
    manifestsPage = defaultManifestsPage,
    hiddenColumns = [],
    query = {},
  } = {}) =>
  () => {
    saveStorageValue(
      `${VERSION_LIST_COLUMNS_STORAGE_KEY}-${versionListFamily(format)}`,
      hiddenColumns,
    );

    // The page reads the repository name, the artifact id, and the active sort from the route,
    // so the story navigates to the version list route before rendering.
    const router = createRouter(BASE_PATH);
    router.push({ path: `/${mockRepository.name}/${artifactId}`, query });

    return {
      components: { VersionList },
      router,
      apolloProvider: createMockApollo(
        [
          [getArtifactQuery, handler],
          [getArtifactVersionsQuery, versionsHandler(format, versionsPage)],
          [getArtifactManifestsQuery, manifestsHandler(format, manifestsPage)],
        ],
        {},
        // The mock cache is built from whatever cache options it is handed rather than from a
        // merge, so passing the view's own policies alone would drop every global one.
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: {
        breadCrumbState: { artifactName: '', updateArtifactName() {} },
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
      },
      template: '<version-list />',
    };
  };

export const Default = Template();

export const NpmPackage = Template({ format: 'NPM' });

export const DockerImage = Template({ format: 'DOCKER' });

export const OciImage = Template({ format: 'OCI' });

export const Loading = Template({ handler: () => new Promise(() => {}) });

export const ServiceUnavailable = Template({
  handler: () => Promise.reject(new Error('Unavailable')),
});

export const NotFound = Template({
  handler: () => Promise.resolve(mockRepositoryResponse(null)),
});

// The repository holds no artifact under the id, which is what the schema answers with for a
// deep link Artifact Registry cannot resolve.
export const ArtifactNotFound = Template({
  handler: () => Promise.resolve(mockRepositoryResponse(mockArtifactRepository('MAVEN'))),
});

export const WithoutVersions = Template({ versionsPage: () => mockEmptyVersionPage });

export const WithoutManifests = Template({
  format: 'DOCKER',
  manifestsPage: () => mockEmptyManifestPage,
});

export const Paginated = Template({
  versionsPage: ({ after }) => (after ? mockSecondVersionPage : mockFirstVersionPage),
});

export const ColumnsHidden = Template({ hiddenColumns: ['source'] });

export const ContainerColumnsHidden = Template({ format: 'DOCKER', hiddenColumns: ['size'] });

// The header affordance and its `aria-sort` state only render for a sort the route names, so
// the axe run needs a story that names one.
export const SortedByVersion = Template({ query: { sort: 'version_asc' } });

export const ReferrersExcluded = Template({
  format: 'DOCKER',
  manifestsPage: () => ({
    ...mockManifestPage,
    nodes: mockManifestPage.nodes.filter(({ subjectDigest }) => !subjectDigest),
  }),
  query: { include_referrers: 'false' },
});

export const VersionsLoading = Template({ versionsPage: () => new Promise(() => {}) });

export const VersionsUnavailable = Template({
  versionsPage: () => Promise.reject(new Error('Unavailable')),
});
