import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  CLIENT_BASE_URL,
  ORGANIZATION_GID,
  SLUG,
  mockArtifactRepository,
  mockRepository,
  mockRepositoryResponse,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from '../../../graphql/cache_config';
import { mockArtifacts, versionLadderFor } from '../../../graphql/mock_artifacts';
import getVersionQuery from '../../../graphql/queries/get_version.query.graphql';
import getVersionFilesQuery from '../../../graphql/queries/get_version_files.query.graphql';
import {
  GRAPHQL_PAGE_SIZE,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_VERSION_FILE,
  TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_NPM_VERSION_FILE,
} from '../../../constants';
import { createRouter } from '../../../router';
import VersionDetail from './version_detail.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

const FIRST_PAGE_END_CURSOR = 'end-of-first-page';

const SECOND_PAGE_START_CURSOR = 'start-of-second-page';

const MAVEN_BUILD_SUFFIXES = ['.jar', '.pom', '-sources.jar', '-javadoc.jar'];

const MAVEN_RELEASE_FILE_NAMES = [
  ...MAVEN_BUILD_SUFFIXES.map((suffix) => `core-3.2.1${suffix}`),
  'maven-metadata.xml',
];

const MAVEN_SNAPSHOT_FILE_NAMES = [
  ...Array.from({ length: 6 }, (_, build) =>
    MAVEN_BUILD_SUFFIXES.map(
      (suffix) => `core-3.2.0-2026030${build + 1}.120000-${build + 1}${suffix}`,
    ),
  ).flat(),
  'maven-metadata.xml',
].sort();

const NPM_FILE_NAMES = ['design-system-4.2.0.tgz'];

const fileId = (index) => `01937b2e-0000-7000-8000-${String(index).padStart(12, '0')}`;

const mavenFiles = (fileNames) =>
  fileNames.map((fileName, index) => ({
    __typename: TYPENAME_ARTIFACT_REGISTRY_MAVEN_VERSION_FILE,
    id: fileId(index),
    fileName,
    sizeBytes: String(4096 * (index + 1)),
    createdAt: null,
    md5: index % 3 === 0 ? null : String(index).repeat(32).slice(0, 32),
    sha1: String(index).repeat(40).slice(0, 40),
    sha256: String(index).repeat(64).slice(0, 64),
    sha512: String(index).repeat(128).slice(0, 128),
  }));

const npmFiles = (fileNames) =>
  fileNames.map((fileName, index) => ({
    __typename: TYPENAME_ARTIFACT_REGISTRY_NPM_VERSION_FILE,
    id: fileId(index),
    fileName,
    sizeBytes: String(524288 * (index + 1)),
    createdAt: '2026-06-10T00:00:00Z',
    sha256: String(index).repeat(64).slice(0, 64),
  }));

const filePage = (nodes, pageInfo = {}) => ({
  __typename: 'ArtifactRegistryVersionFileConnection',
  nodes,
  pageInfo: {
    __typename: 'PageInfo',
    hasNextPage: false,
    hasPreviousPage: false,
    startCursor: null,
    endCursor: null,
    ...pageInfo,
  },
});

const MAVEN_RELEASE_PAGE = filePage(mavenFiles(MAVEN_RELEASE_FILE_NAMES));

const NPM_PAGE = filePage(npmFiles(NPM_FILE_NAMES));

const EMPTY_PAGE = filePage([]);

const SNAPSHOT_FILES = mavenFiles(MAVEN_SNAPSHOT_FILE_NAMES);

const pagedSnapshot = ({ after }) =>
  after
    ? filePage(SNAPSHOT_FILES.slice(GRAPHQL_PAGE_SIZE), {
        hasPreviousPage: true,
        startCursor: SECOND_PAGE_START_CURSOR,
      })
    : filePage(SNAPSHOT_FILES.slice(0, GRAPHQL_PAGE_SIZE), {
        hasNextPage: true,
        endCursor: FIRST_PAGE_END_CURSOR,
      });

const DEFAULT_FILES = {
  MAVEN: () => MAVEN_RELEASE_PAGE,
  NPM: () => NPM_PAGE,
};

const DEFAULT_FILES_COUNT = {
  MAVEN: MAVEN_RELEASE_FILE_NAMES.length,
  NPM: NPM_FILE_NAMES.length,
};

const versionStatistics = (filesCount) => ({
  __typename: 'ArtifactRegistryVersionStatistics',
  filesCount: String(filesCount),
});

const generatedArtifact = (format) => mockArtifacts(mockRepository.name, format)[0];

// The single-package read returns the detail union, so the package spread on
// `... on ArtifactRegistry*PackageDetails` needs the detail typename; the generator stamps the
// plain one the `packages` list returns.
const asDetailPackage = (format, artifact) => ({
  ...artifact,
  __typename:
    format === 'NPM'
      ? TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS
      : TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS,
});

const serverVersion = (format) => versionLadderFor(generatedArtifact(format).id, format)[0];

const repositoryHandler =
  (
    format,
    {
      kind = 'HOSTED',
      version = serverVersion(format),
      files = DEFAULT_FILES[format],
      filesCount = DEFAULT_FILES_COUNT[format],
    } = {},
  ) =>
  (variables) => {
    const { artifactId, versionId } = variables;
    const artifact = generatedArtifact(format);
    const held = artifactId === artifact.id;
    const found = held && versionId === version.id;

    return Promise.resolve(
      mockRepositoryResponse(
        mockArtifactRepository(format, {
          kind,
          package: held ? asDetailPackage(format, artifact) : null,
          version: found
            ? {
                ...version,
                files: files(variables),
                statistics: kind === 'HOSTED' ? versionStatistics(filesCount) : null,
              }
            : null,
        }),
      ),
    );
  };

export default {
  component: VersionDetail,
  title: 'ee/artifact_registry/repositories/versions/detail/version_detail',
};

const Template =
  ({
    format = 'MAVEN',
    version = serverVersion(format),
    handler = repositoryHandler(format, { version }),
    artifactId = generatedArtifact(format).id,
    versionId = version.id,
    query = {},
  } = {}) =>
  () => {
    const router = createRouter(BASE_PATH);
    router.push({ path: `/${mockRepository.name}/${artifactId}/versions/${versionId}`, query });

    return {
      components: { VersionDetail },
      router,
      apolloProvider: createMockApollo(
        [
          [getVersionQuery, handler],
          [getVersionFilesQuery, handler],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: {
        breadCrumbState: {
          artifactName: '',
          versionName: '',
          updateArtifactName() {},
          updateVersionName() {},
        },
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
      },
      template: '<version-detail />',
    };
  };

export const Default = Template();

export const NpmVersion = Template({ format: 'NPM' });

export const RemoteRepository = Template({
  handler: repositoryHandler('MAVEN', { kind: 'REMOTE' }),
});

export const MavenFilesTab = Template({ query: { tab: 'files' } });

export const NpmFileTab = Template({ format: 'NPM', query: { tab: 'files' } });

export const MavenFilesTabSecondPage = Template({
  handler: repositoryHandler('MAVEN', {
    files: pagedSnapshot,
    filesCount: SNAPSHOT_FILES.length,
  }),
  query: { tab: 'files', after: FIRST_PAGE_END_CURSOR },
});

export const MavenFilesTabEmpty = Template({
  handler: repositoryHandler('MAVEN', { files: () => EMPTY_PAGE, filesCount: 0 }),
  query: { tab: 'files' },
});

export const NpmFileTabEmpty = Template({
  format: 'NPM',
  handler: repositoryHandler('NPM', { files: () => EMPTY_PAGE, filesCount: 0 }),
  query: { tab: 'files' },
});

export const Loading = Template({ handler: () => new Promise(() => {}) });

export const ServiceUnavailable = Template({
  handler: () => Promise.reject(new Error('Unavailable')),
});

export const NotFound = Template({
  handler: () => Promise.resolve(mockRepositoryResponse(null)),
});

export const ArtifactNotFound = Template({ artifactId: 'unheld-artifact-id' });

export const VersionNotFound = Template({ versionId: 'unheld-version-id' });

export const VersionOfAnotherArtifact = Template({
  versionId: versionLadderFor(mockArtifacts(mockRepository.name, 'MAVEN')[1].id)[0].id,
});
