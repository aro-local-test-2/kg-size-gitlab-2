import { observable, resetObservable } from '~/lib/utils/observable';

export const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

export const SLUG = 'acme';

export const ORGANIZATION_GID = 'gid://gitlab/Organizations::Organization/1';

export const CLIENT_BASE_URL = 'https://artifact-registry.example.com';

// The cache keys ArtifactRegistryRepository on `name` (graphql/cache_config.js), so a
// normalized repository lands here.
export const REPOSITORY_CACHE_ID = 'ArtifactRegistryRepository:{"name":"my-repository"}';

// Deliberately not the route's slug fixture: the settings section reads the slug from the
// registry alone, so a value equal to the route's slug would leave a section rendering the
// wrong one looking right.
export const REGISTRY_HANDLE = 'my-registry';

const REGISTRY_CREATED_AT = '2026-08-06T12:00:00Z';

// Artifact Registry's own UUID for the namespace, not a GitLab global ID.
export const REGISTRY_ID = '01937b2e-0000-7000-8000-00000000000a';

export const REPOSITORY_ID = '01937b2e-0000-7000-8000-000000000401';

const UNTOUCHED_REPOSITORY_ID = '01937b2e-0000-7000-8000-000000000402';

export const mockArtifactRegistry = (overrides = {}) => ({
  __typename: 'ArtifactRegistry',
  id: REGISTRY_ID,
  slug: REGISTRY_HANDLE,
  status: 'active',
  createdAt: REGISTRY_CREATED_AT,
  ...overrides,
});

const REPOSITORY_PERMISSION_FIELDS = [
  'readRepository',
  'updateRepository',
  'deleteRepository',
  'createRepositoryUpstream',
  'updateRepositoryUpstream',
  'deleteRepositoryUpstream',
  'readArtifact',
  'createArtifact',
  'deleteArtifact',
];

const NAMESPACE_PERMISSION_FIELDS = [
  'readRepository',
  'createRepository',
  'updateRepository',
  'deleteRepository',
  'createRepositoryUpstream',
  'updateRepositoryUpstream',
  'deleteRepositoryUpstream',
];

const mockPermissions = ({ typename, fields, verdict, overrides }) => ({
  __typename: typename,
  ...Object.fromEntries(fields.map((field) => [field, verdict])),
  ...overrides,
});

export const mockRepositoryPermissions = (overrides = {}) =>
  mockPermissions({
    typename: 'ArtifactRegistryRepositoryPermissions',
    fields: REPOSITORY_PERMISSION_FIELDS,
    verdict: true,
    overrides,
  });

export const mockDeniedRepositoryPermissions = (overrides = {}) =>
  mockPermissions({
    typename: 'ArtifactRegistryRepositoryPermissions',
    fields: REPOSITORY_PERMISSION_FIELDS,
    verdict: false,
    overrides,
  });

export const mockNamespacePermissions = (overrides = {}) =>
  mockPermissions({
    typename: 'ArtifactRegistryNamespacePermissions',
    fields: NAMESPACE_PERMISSION_FIELDS,
    verdict: true,
    overrides,
  });

export const mockDeniedNamespacePermissions = (overrides = {}) =>
  mockPermissions({
    typename: 'ArtifactRegistryNamespacePermissions',
    fields: NAMESPACE_PERMISSION_FIELDS,
    verdict: false,
    overrides,
  });

// The counters are strings because they reach the browser through GraphQL's BigInt scalar.
export const mockRepository = {
  __typename: 'ArtifactRegistryRepository',
  id: REPOSITORY_ID,
  name: 'my-repository',
  format: 'MAVEN',
  kind: 'HOSTED',
  visibility: 'PRIVATE',
  description: 'A hosted Maven repository',
  downloadsCount: '1234',
  sizeBytes: '2048',
  lastUpdatedAt: '2026-06-01T00:00:00Z',
  userPermissions: mockRepositoryPermissions(),
};

const REMOTE_UPSTREAM_URL = 'https://repo.maven.apache.org/maven2';

export const REMOTE_LAST_HEALTH_CHECKED_AT = '2026-07-12T00:00:00Z';

export const mockRemoteSettings = {
  __typename: 'ArtifactRegistryRemoteSettings',
  url: REMOTE_UPSTREAM_URL,
  cacheValidityHours: 48,
  metadataCacheValidityHours: 12,
  lastHealthStatus: 'HEALTHY',
  lastHealthCheckedAt: REMOTE_LAST_HEALTH_CHECKED_AT,
};

export const mockWritableRemoteSettings = {
  ...mockRemoteSettings,
  cacheValidityHours: 48,
  metadataCacheValidityHours: 12,
};

// A repository nothing was ever published to: zero counters and a null lastUpdatedAt.
export const mockUntouchedRepository = {
  __typename: 'ArtifactRegistryRepositoryDetails',
  id: UNTOUCHED_REPOSITORY_ID,
  name: 'container-images',
  format: 'DOCKER',
  kind: 'VIRTUAL',
  visibility: 'PRIVATE',
  description: null,
  downloadsCount: '0',
  sizeBytes: '0',
  lastUpdatedAt: null,
  userPermissions: mockRepositoryPermissions(),
};

export const mockRepositories = [mockRepository, mockUntouchedRepository];

// Artifact Registry cursors are opaque (ADR-009): nothing may parse these, only hand them back.
export const FIRST_PAGE_END_CURSOR = 'eyJuYW1lIjoibXktcmVwb3NpdG9yeSJ9';

export const SECOND_PAGE_START_CURSOR = 'eyJuYW1lIjoiY29udGFpbmVyLWltYWdlcyJ9';

const mockPageInfo = (overrides = {}) => ({
  __typename: 'PageInfo',
  hasNextPage: false,
  hasPreviousPage: false,
  startCursor: null,
  endCursor: null,
  ...overrides,
});

export const mockRepositoryPage = {
  __typename: 'ArtifactRegistryRepositoryConnection',
  nodes: mockRepositories,
  pageInfo: mockPageInfo(),
  userPermissions: mockNamespacePermissions(),
};

export const mockEmptyRepositoryPage = {
  __typename: 'ArtifactRegistryRepositoryConnection',
  nodes: [],
  pageInfo: mockPageInfo(),
  userPermissions: mockNamespacePermissions(),
};

const ARTIFACT_IDS = {
  'payment-service': '01937b2e-0000-7000-8000-000000000001',
  'api-gateway': '01937b2e-0000-7000-8000-000000000002',
  'auth-service': '01937b2e-0000-7000-8000-000000000003',
  'helm-charts': '01937b2e-0000-7000-8000-000000000004',
  'com.company.payment:core': '01937b2e-0000-7000-8000-000000000005',
  '@company/payment-core': '01937b2e-0000-7000-8000-000000000006',
  'design-tokens': '01937b2e-0000-7000-8000-000000000007',
  '@company/design-system': '01937b2e-0000-7000-8000-000000000008',
};

const mockImage = (name, lastDownloadedAt = null) => ({
  __typename: 'ArtifactRegistryImage',
  id: ARTIFACT_IDS[name],
  name,
  lastDownloadedAt,
});

export const mockImagePage = {
  __typename: 'ArtifactRegistryImageConnection',
  nodes: [mockImage('payment-service'), mockImage('api-gateway')],
  pageInfo: mockPageInfo(),
};

// A pair of single-row pages, so which page is rendered is legible from the row itself.
export const mockFirstImagePage = {
  __typename: 'ArtifactRegistryImageConnection',
  nodes: [mockImage('payment-service')],
  pageInfo: mockPageInfo({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
};

export const mockSecondImagePage = {
  __typename: 'ArtifactRegistryImageConnection',
  nodes: [mockImage('auth-service')],
  pageInfo: mockPageInfo({ hasPreviousPage: true, startCursor: SECOND_PAGE_START_CURSOR }),
};

const mockMavenPackage = (groupId, artifactId, lastDownloadedAt = null) => ({
  __typename: 'ArtifactRegistryMavenPackage',
  id: ARTIFACT_IDS[`${groupId}:${artifactId}`],
  groupId,
  artifactId,
  lastDownloadedAt,
});

const mockNpmPackage = ({ scope = null, name, versionsCount, lastDownloadedAt = null }) => ({
  __typename: 'ArtifactRegistryNpmPackage',
  id: ARTIFACT_IDS[name],
  name,
  scope,
  versionsCount,
  lastDownloadedAt,
});

export const mockMavenPackagePage = {
  __typename: 'ArtifactRegistryPackageConnection',
  nodes: [mockMavenPackage('com.company.payment', 'core')],
  pageInfo: mockPageInfo(),
};

export const mockNpmPackagePage = {
  __typename: 'ArtifactRegistryPackageConnection',
  nodes: [
    mockNpmPackage({ scope: '@company', name: '@company/payment-core', versionsCount: 5 }),
    mockNpmPackage({ name: 'design-tokens', versionsCount: 12 }),
  ],
  pageInfo: mockPageInfo(),
};

// The moment a remote row's Last downloaded column dates. Behind the fake date the table specs
// pin, so it reads as a download that already happened.
export const REMOTE_LAST_DOWNLOADED_AT = '2026-06-10T00:00:00Z';

// Whether a cached artifact carries the timestamp depends on which format's read path bumps
// it, so a page of them pairs a downloaded row with one nothing has pulled yet.
export const mockRemoteImagePage = {
  __typename: 'ArtifactRegistryImageConnection',
  nodes: [mockImage('payment-service', REMOTE_LAST_DOWNLOADED_AT), mockImage('api-gateway')],
  pageInfo: mockPageInfo(),
};

export const mockRemoteMavenPackagePage = {
  __typename: 'ArtifactRegistryPackageConnection',
  nodes: [mockMavenPackage('com.company.payment', 'core', REMOTE_LAST_DOWNLOADED_AT)],
  pageInfo: mockPageInfo(),
};

// The counters stay null here: the remote table has no Versions column to render them in.
export const mockRemoteNpmPackagePage = {
  __typename: 'ArtifactRegistryPackageConnection',
  nodes: [
    mockNpmPackage({
      scope: '@company',
      name: '@company/payment-core',
      versionsCount: null,
      lastDownloadedAt: REMOTE_LAST_DOWNLOADED_AT,
    }),
    mockNpmPackage({ name: 'design-tokens', versionsCount: null }),
  ],
  pageInfo: mockPageInfo(),
};

export const mockEmptyImagePage = {
  __typename: 'ArtifactRegistryImageConnection',
  nodes: [],
  pageInfo: mockPageInfo(),
};

export const mockEmptyPackagePage = {
  __typename: 'ArtifactRegistryPackageConnection',
  nodes: [],
  pageInfo: mockPageInfo(),
};

const mockCiPublisher = {
  __typename: 'UserCore',
  id: 'gid://gitlab/User/1',
  name: 'Alex Turner',
};

const mockCommitlessPublisher = {
  __typename: 'UserCore',
  id: 'gid://gitlab/User/2',
  name: 'Maria Santos',
};

export const mockPublishingProject = {
  __typename: 'Project',
  id: 'gid://gitlab/Project/1',
  name: 'payments-svc',
  fullPath: 'gitlab-org/payments-svc',
  webPath: '/gitlab-org/payments-svc',
};

export const MOCK_COMMIT_SHA = 'f19ac02a8d3b41e57c9f0a4d2b8e6135ac97d40e';

// Distinct per row, so an assertion about one row's sha cannot pass on another row's.
const MOCK_UNATTRIBUTED_COMMIT_SHA = 'ecea89714d0b62ae3f8c15d79b2e604ac8d1735f';

const MOCK_PROJECTLESS_COMMIT_SHA = 'b7d4e9206a3f81cd5e0b7942df1c8a3640e29b57';

const VERSION_IDS = {
  '3.2.1': '01937b2e-0000-7000-8000-000000000101',
  '2.0.0': '01937b2e-0000-7000-8000-000000000102',
  '3.2.0': '01937b2e-0000-7000-8000-000000000103',
  '3.1.0': '01937b2e-0000-7000-8000-000000000104',
  '1.0.0': '01937b2e-0000-7000-8000-000000000105',
};

const mockVersion = (version, createdAt, source = {}) => ({
  __typename: 'ArtifactRegistryVersion',
  id: VERSION_IDS[version],
  version,
  createdAt,
  createdBy: source.createdBy ?? null,
  project: source.project ?? null,
  gitCommitSha: source.gitCommitSha ?? null,
  distTags: source.distTags ?? [],
  sizeBytes: source.sizeBytes ?? null,
});

export const mockVersions = [
  mockVersion('3.2.1', '2026-06-10T00:00:00Z', {
    createdBy: mockCiPublisher,
    project: mockPublishingProject,
    gitCommitSha: MOCK_COMMIT_SHA,
    distTags: ['latest', 'stable'],
    sizeBytes: '16400000',
  }),
  mockVersion('2.0.0', '2026-04-02T00:00:00Z', { createdBy: mockCommitlessPublisher }),
];

// One version per shape the Source column degrades through, in the order the cell's branches
// take: a full attribution, a project with no publisher, a commit whose project did not resolve,
// a publisher with no commit, and a version carrying no attribution at all.
export const mockAttributedVersions = [
  mockVersions[0],
  mockVersion('3.2.0', '2026-05-20T00:00:00Z', {
    project: mockPublishingProject,
    gitCommitSha: MOCK_UNATTRIBUTED_COMMIT_SHA,
  }),
  mockVersion('3.1.0', '2026-05-01T00:00:00Z', {
    createdBy: mockCiPublisher,
    gitCommitSha: MOCK_PROJECTLESS_COMMIT_SHA,
  }),
  mockVersions[1],
  mockVersion('1.0.0', '2026-01-05T00:00:00Z'),
];

export const mockVersionPage = {
  __typename: 'ArtifactRegistryVersionConnection',
  nodes: mockVersions,
  pageInfo: mockPageInfo(),
};

export const mockFirstVersionPage = {
  __typename: 'ArtifactRegistryVersionConnection',
  nodes: [mockVersions[0]],
  pageInfo: mockPageInfo({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
};

export const mockSecondVersionPage = {
  __typename: 'ArtifactRegistryVersionConnection',
  nodes: [mockVersions[1]],
  pageInfo: mockPageInfo({ hasPreviousPage: true, startCursor: SECOND_PAGE_START_CURSOR }),
};

const MOCK_VERSION_SIZE_BYTES = '16400384';

const mockMavenFile = ({ marker, fileName, md5 = 'd41d8cd98f00b204e9800998ecf8427e' }) => ({
  __typename: 'ArtifactRegistryMavenVersionFile',
  id: `01937b2e-0000-7000-8000-0000000003${String(marker).padStart(2, '0')}`,
  fileName,
  sizeBytes: '1048576',
  sha256: 'a'.repeat(64),
  sha1: 'b'.repeat(40),
  sha512: 'c'.repeat(128),
  md5,
  createdAt: null,
});

const mockMavenFiles = [
  { fileName: 'core-3.2.1.jar' },
  { fileName: 'core-3.2.1.pom' },
  { fileName: 'core-3.2.1-sources.jar' },
  { fileName: 'core-3.2.1-javadoc.jar', md5: null },
  { fileName: 'maven-metadata.xml' },
].map((file, index) => mockMavenFile({ ...file, marker: index + 1 }));

export const mockVersionDetails = (overrides = {}) => ({
  __typename: 'ArtifactRegistryVersionDetails',
  id: VERSION_IDS['3.2.1'],
  version: '3.2.1',
  createdAt: '2026-06-10T00:00:00Z',
  sizeBytes: MOCK_VERSION_SIZE_BYTES,
  createdBy: mockCiPublisher,
  project: mockPublishingProject,
  gitCommitSha: MOCK_COMMIT_SHA,
  ...overrides,
});

const mockFilePage = (nodes, pageInfo = {}) => ({
  __typename: 'ArtifactRegistryVersionFileConnection',
  nodes,
  pageInfo: mockPageInfo(pageInfo),
});

export const mockFirstFilePage = mockFilePage(mockMavenFiles.slice(0, 2), {
  hasNextPage: true,
  endCursor: FIRST_PAGE_END_CURSOR,
});

export const mockSecondFilePage = mockFilePage(mockMavenFiles.slice(2), {
  hasPreviousPage: true,
  startCursor: SECOND_PAGE_START_CURSOR,
});

export const MOCK_INDEX_MEDIA_TYPE = 'application/vnd.oci.image.index.v1+json';

export const MOCK_IMAGE_MEDIA_TYPE = 'application/vnd.oci.image.manifest.v1+json';

export const MOCK_RAW_ARTIFACT_TYPE = 'application/vnd.example.custom.v1+json';

const mockManifest = ({ marker, size, createdAt, ...overrides }) => ({
  __typename: 'ArtifactRegistryManifest',
  id: `01937b2e-0000-7000-8000-00000000020${marker}`,
  digest: `sha256:${String(marker).repeat(64)}`,
  mediaType: MOCK_IMAGE_MEDIA_TYPE,
  artifactType: null,
  subjectDigest: null,
  size,
  createdAt,
  ...overrides,
});

const MOCK_SUBJECT_MANIFESTS = [
  mockManifest({
    marker: 1,
    size: '3221225',
    createdAt: '2026-06-10T00:00:00Z',
    mediaType: MOCK_INDEX_MEDIA_TYPE,
  }),
  mockManifest({ marker: 2, size: '2097152', createdAt: '2026-04-02T00:00:00Z' }),
];

const mockReferrer = (marker, artifactType, subject) =>
  mockManifest({
    marker,
    size: '3452',
    createdAt: subject.createdAt,
    artifactType,
    subjectDigest: subject.digest,
  });

// An image Artifact Registry holds carries referrers alongside the manifests they attach to, so
// the one page every manifest read answers with carries both: a subject of each media type, and a
// referrer of each kind the Type column labels plus the two it has no label for.
export const mockManifests = [
  ...MOCK_SUBJECT_MANIFESTS,
  mockReferrer(3, 'application/vnd.dev.cosign.artifact.sig.v1+json', MOCK_SUBJECT_MANIFESTS[0]),
  mockReferrer(4, 'application/spdx+json', MOCK_SUBJECT_MANIFESTS[1]),
  mockReferrer(5, 'application/vnd.in-toto.provenance+json', MOCK_SUBJECT_MANIFESTS[1]),
  mockReferrer(6, MOCK_RAW_ARTIFACT_TYPE, MOCK_SUBJECT_MANIFESTS[1]),
  mockReferrer(7, null, MOCK_SUBJECT_MANIFESTS[1]),
];

// The rows the table labels without falling back to a raw artifact type, which is every row but
// the unrecognized referrer and the one carrying no artifact type at all.
export const mockLabelledManifests = mockManifests.slice(0, -2);

export const mockManifestPage = {
  __typename: 'ArtifactRegistryManifestConnection',
  nodes: mockManifests,
  pageInfo: mockPageInfo(),
};

export const mockFirstManifestPage = {
  __typename: 'ArtifactRegistryManifestConnection',
  nodes: [MOCK_SUBJECT_MANIFESTS[0]],
  pageInfo: mockPageInfo({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
};

export const mockSecondManifestPage = {
  __typename: 'ArtifactRegistryManifestConnection',
  nodes: [MOCK_SUBJECT_MANIFESTS[1]],
  pageInfo: mockPageInfo({ hasPreviousPage: true, startCursor: SECOND_PAGE_START_CURSOR }),
};

export const mockEmptyManifestPage = {
  __typename: 'ArtifactRegistryManifestConnection',
  nodes: [],
  pageInfo: mockPageInfo(),
};

export const mockEmptyVersionPage = {
  __typename: 'ArtifactRegistryVersionConnection',
  nodes: [],
  pageInfo: mockPageInfo(),
};

export const mockUser = {
  __typename: 'UserCore',
  id: 'gid://gitlab/User/1',
  name: 'Alex Turner',
  avatarUrl: '/uploads/-/system/user/avatar/1/avatar.png',
  webPath: '/alex-turner',
};

const ARTIFACT_CONNECTIONS = {
  DOCKER: { images: mockImagePage, packages: null },
  OCI: { images: mockImagePage, packages: null },
  MAVEN: { images: null, packages: mockMavenPackagePage },
  NPM: { images: null, packages: mockNpmPackagePage },
};

const DETAIL_FIELDS = {
  artifactsCount: '3',
  createdAt: '2026-05-12T09:24:00Z',
  createdBy: mockUser,
  updatedBy: mockUser,
};

export const mockDetailRepository = (format = 'MAVEN', overrides = {}) => ({
  ...mockRepository,
  ...DETAIL_FIELDS,
  format,
  ...ARTIFACT_CONNECTIONS[format],
  ...overrides,
});

// The single-package read (`get_version`, `get_artifact`, `get_artifact_versions`) returns the
// detail union, so a package reached through it carries the detail typename. The list pages above
// keep the plain typename their `packages` connection returns.
const asDetailPackage = (artifactPackage, typename) => ({
  ...artifactPackage,
  __typename: typename,
});

const ARTIFACTS = {
  DOCKER: { image: mockImage('payment-service'), package: null },
  OCI: { image: mockImage('helm-charts'), package: null },
  MAVEN: {
    image: null,
    package: asDetailPackage(
      mockMavenPackage('com.company.payment', 'core'),
      'ArtifactRegistryMavenPackageDetails',
    ),
  },
  NPM: {
    image: null,
    package: asDetailPackage(
      mockNpmPackage({ scope: '@company', name: '@company/design-system' }),
      'ArtifactRegistryNpmPackageDetails',
    ),
  },
};

export const ARTIFACT_ID_FOR = {
  DOCKER: ARTIFACT_IDS['payment-service'],
  OCI: ARTIFACT_IDS['helm-charts'],
  MAVEN: ARTIFACT_IDS['com.company.payment:core'],
  NPM: ARTIFACT_IDS['@company/design-system'],
};

export const ARTIFACT_DISPLAY_NAMES = {
  DOCKER: 'payment-service',
  OCI: 'helm-charts',
  MAVEN: 'com.company.payment:core',
  NPM: '@company/design-system',
};

// The repository the artifact read resolves: its identity and the format that decides which of
// the two artifact fields answers.
export const mockArtifactRepository = (format = 'MAVEN', overrides = {}) => ({
  __typename: 'ArtifactRegistryRepositoryDetails',
  id: mockRepository.id,
  name: mockRepository.name,
  format,
  ...overrides,
});

// An image for the container formats and a package for the rest, with null for whichever the
// format does not hold.
export const mockRepositoryArtifacts = (format) => ARTIFACTS[format];

export const MANIFEST_ID = '01937b2e-0000-7000-8000-000000000301';

export const MANIFEST_DIGEST = `sha256:${'a1b2c3d4'.repeat(8)}`;

export const MANIFEST_PARENT_DIGEST = `sha256:${'b2c3d4e5'.repeat(8)}`;

const mockManifestPlatform = ({ marker, ...overrides } = {}) => ({
  __typename: 'ArtifactRegistryManifestPlatform',
  digest: `sha256:${String(marker).repeat(64)}`,
  architecture: 'amd64',
  os: 'linux',
  osVariant: null,
  ...overrides,
});

const mockManifestChildren = [
  mockManifestPlatform({ marker: 1 }),
  mockManifestPlatform({ marker: 2, architecture: 'arm64', osVariant: 'v8' }),
  mockManifestPlatform({ marker: 3, architecture: '386' }),
];

export const mockManifestDetails = ({
  childrenCount = 3,
  tags = ['latest', 'rc1', 'v1'],
  children = mockManifestChildren,
  parentDigests = [],
  size = '3221225',
  createdAt = '2026-06-10T00:00:00Z',
  architecture = null,
  os = null,
  osVariant = null,
  referrersCount = 2,
  ...overrides
} = {}) => ({
  __typename: 'ArtifactRegistryManifestDetails',
  id: MANIFEST_ID,
  digest: MANIFEST_DIGEST,
  mediaType: MOCK_INDEX_MEDIA_TYPE,
  artifactType: null,
  subjectDigest: null,
  childrenCount,
  tags,
  children,
  parentDigests,
  size,
  createdAt,
  architecture,
  os,
  osVariant,
  referrersCount,
  ...overrides,
});

export const mockManifestImageDetails = (overrides = {}) =>
  mockManifestDetails({
    mediaType: MOCK_IMAGE_MEDIA_TYPE,
    childrenCount: 0,
    children: [],
    parentDigests: [MANIFEST_PARENT_DIGEST],
    architecture: 'amd64',
    os: 'linux',
    ...overrides,
  });

export const MOCK_SIGNATURE_ARTIFACT_TYPE = 'application/vnd.dev.cosign.artifact.sig.v1+json';

export const mockManifestReferrer = ({ marker = 'c', ...overrides } = {}) => ({
  __typename: 'ArtifactRegistryManifest',
  id: `01937b2e-0000-7000-8000-0000000004${String(marker).charCodeAt(0)}`,
  digest: `sha256:${String(marker).repeat(64).slice(0, 64)}`,
  mediaType: MOCK_IMAGE_MEDIA_TYPE,
  artifactType: MOCK_SIGNATURE_ARTIFACT_TYPE,
  subjectDigest: MANIFEST_DIGEST,
  createdAt: '2026-06-12T00:00:00Z',
  ...overrides,
});

export const mockManifestReferrers = (nodes = [mockManifestReferrer()], pageInfo = {}) => ({
  __typename: 'ArtifactRegistryManifestConnection',
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

export const mockManifestReferrersRepository = ({
  format = 'DOCKER',
  referrers = mockManifestReferrers(),
  manifest = {
    __typename: 'ArtifactRegistryManifestDetails',
    id: MANIFEST_ID,
    referrers,
  },
  ...overrides
} = {}) => ({
  __typename: 'ArtifactRegistryRepositoryDetails',
  id: mockRepository.id,
  name: mockRepository.name,
  format,
  manifest,
  ...overrides,
});

export const mockManifestRepository = ({
  format = 'DOCKER',
  kind = 'HOSTED',
  manifest = mockManifestDetails(),
  image = mockImage('payment-service'),
  ...overrides
} = {}) => ({
  __typename: 'ArtifactRegistryRepositoryDetails',
  id: mockRepository.id,
  name: mockRepository.name,
  format,
  kind,
  image,
  manifest,
  ...overrides,
});

export const mockArtifactRegistryResponse = (registry = mockArtifactRegistry()) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: ORGANIZATION_GID,
      artifactRegistry: registry,
    },
  },
});

export const mockRepositoriesResponse = (connection) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: ORGANIZATION_GID,
      artifactRegistryRepositories: connection,
    },
  },
});

// The connection caches under a filter-keyed field, so these match the field rather than a
// bare key, which would report it absent whether or not the eviction ran.
export const cachedRepositoriesConnections = (cache) =>
  Object.keys(
    cache.extract()[cache.identify({ __typename: 'Organization', id: ORGANIZATION_GID })] ?? {},
  ).filter((key) => /^artifactRegistryRepositories[:(]/.test(key));

export const hasCachedRepositoriesConnection = (cache) =>
  cachedRepositoriesConnections(cache).length > 0;

export const mockRepositoryResponse = (repository) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: ORGANIZATION_GID,
      artifactRegistryRepository: repository,
    },
  },
});

// The repository the create and update payloads select, which is also the field set the edit
// prefill reads.
export const mockWrittenRepository = (overrides = {}) => ({
  __typename: 'ArtifactRegistryRepository',
  id: mockRepository.id,
  name: mockRepository.name,
  format: mockRepository.format,
  kind: mockRepository.kind,
  visibility: mockRepository.visibility,
  description: mockRepository.description,
  settings: null,
  ...overrides,
});

export const mockPrefilledRepository = (overrides = {}) => ({
  ...mockWrittenRepository(overrides),
  __typename: 'ArtifactRegistryRepositoryDetails',
});

// A GraphQL response keys its data by the alias the document declares, which is why these
// carry `createRepository` rather than the schema's field name.
export const mockCreateRepositoryResponse = ({
  repository = mockWrittenRepository(),
  errors = [],
} = {}) => ({
  data: {
    createRepository: {
      __typename: 'ArtifactRegistryRepositoryCreatePayload',
      repository,
      errors,
    },
  },
});

export const mockUpdateRepositoryResponse = ({
  repository = mockWrittenRepository(),
  errors = [],
} = {}) => ({
  data: {
    updateRepository: {
      __typename: 'ArtifactRegistryRepositoryUpdatePayload',
      repository,
      errors,
    },
  },
});

export const mockDeleteRepositoryResponse = ({ errors = [] } = {}) => ({
  data: {
    deleteRepository: {
      __typename: 'ArtifactRegistryRepositoryDeletePayload',
      errors,
    },
  },
});

export const mockClearRepositoryCacheResponse = ({ errors = [] } = {}) => ({
  data: {
    clearRepositoryCache: {
      __typename: 'ArtifactRegistryRepositoryArtifactsDeletePayload',
      errors,
    },
  },
});

export const mockDeleteArtifactResponse = ({ errors = [] } = {}) => ({
  data: {
    deleteArtifact: {
      __typename: 'ArtifactRegistryArtifactDeletePayload',
      errors,
    },
  },
});

export const mockDeleteVersionResponse = ({ errors = [] } = {}) => ({
  data: {
    deleteVersion: {
      __typename: 'ArtifactRegistryVersionDeletePayload',
      errors,
    },
  },
});

export const mockDeleteManifestResponse = ({ errors = [] } = {}) => ({
  data: {
    deleteManifest: {
      __typename: 'ArtifactRegistryManifestDeletePayload',
      errors,
    },
  },
});

export const mockUpstreamSummary = ({
  id = 'd1000000-0000-4000-8000-000000000001',
  name = 'maven-central-proxy',
  format = 'MAVEN',
  kind = 'REMOTE',
} = {}) => ({
  __typename: 'ArtifactRegistryUpstreamRepositorySummary',
  id,
  name,
  format,
  kind,
});

export const mockUpstreamAssociation = ({ id, position, upstreamId, name, format, kind }) => ({
  __typename: 'ArtifactRegistryUpstreamRepositoryAssociation',
  id,
  position,
  upstreamRepository: mockUpstreamSummary({ id: upstreamId, name, format, kind }),
});

export const mockUpstreamRepositories = [
  mockUpstreamAssociation({
    id: 'a1000000-0000-4000-8000-000000000001',
    upstreamId: 'd1000000-0000-4000-8000-000000000001',
    position: 1,
    name: 'maven-central-proxy',
    format: 'MAVEN',
    kind: 'REMOTE',
  }),
  mockUpstreamAssociation({
    id: 'a1000000-0000-4000-8000-000000000002',
    upstreamId: 'd1000000-0000-4000-8000-000000000002',
    position: 2,
    name: 'payments-releases',
    format: 'MAVEN',
    kind: 'HOSTED',
  }),
  mockUpstreamAssociation({
    id: 'a1000000-0000-4000-8000-000000000003',
    upstreamId: 'd1000000-0000-4000-8000-000000000003',
    position: 3,
    name: 'platform-snapshots',
    format: 'MAVEN',
    kind: 'HOSTED',
  }),
];

export const mockMixedContainerUpstreamRepositories = [
  mockUpstreamAssociation({
    id: 'b1000000-0000-4000-8000-000000000001',
    upstreamId: 'e1000000-0000-4000-8000-000000000001',
    position: 1,
    name: 'docker-hub-proxy',
    format: 'DOCKER',
    kind: 'REMOTE',
  }),
  mockUpstreamAssociation({
    id: 'b1000000-0000-4000-8000-000000000002',
    upstreamId: 'e1000000-0000-4000-8000-000000000002',
    position: 2,
    name: 'base-images',
    format: 'OCI',
    kind: 'HOSTED',
  }),
];

export const mockFullUpstreamRepositories = Array.from({ length: 20 }, (_, index) =>
  mockUpstreamAssociation({
    id: `c1000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
    upstreamId: `f1000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
    position: index + 1,
    name: `source-${String(index + 1).padStart(2, '0')}`,
    format: 'MAVEN',
    kind: index % 2 === 0 ? 'HOSTED' : 'REMOTE',
  }),
);

export const mockUpstreamSources = [
  {
    id: 'd1000000-0000-4000-8000-000000000001',
    name: 'maven-central-proxy',
    kind: 'REMOTE',
    url: 'https://repo.maven.apache.org/maven2',
    sizeBytes: '2048',
  },
  {
    id: 'd1000000-0000-4000-8000-000000000002',
    name: 'payments-releases',
    kind: 'HOSTED',
    url: null,
    sizeBytes: '1048576',
  },
  {
    id: 'd1000000-0000-4000-8000-000000000003',
    name: 'platform-snapshots',
    kind: 'HOSTED',
    url: null,
    sizeBytes: null,
  },
];

const mockCandidate = ({ id, name, format, kind, sizeBytes = null, url = null }) => ({
  __typename: 'ArtifactRegistryRepository',
  id,
  name,
  format,
  kind,
  sizeBytes,
  settings: url ? { __typename: 'ArtifactRegistryRemoteSettings', url } : null,
});

export const mockUpstreamRepositoryCandidatePages = [
  {
    __typename: 'ArtifactRegistryRepositoryConnection',
    nodes: [
      mockCandidate({
        id: 'c1000000-0000-4000-8000-000000000001',
        name: 'platform-libs',
        format: 'MAVEN',
        kind: 'HOSTED',
        sizeBytes: '4096',
      }),
      mockCandidate({
        id: 'c1000000-0000-4000-8000-000000000002',
        name: 'maven-central',
        format: 'MAVEN',
        kind: 'REMOTE',
        url: 'https://repo1.maven.org/maven2',
      }),
      mockCandidate({
        id: 'd1000000-0000-4000-8000-000000000001',
        name: 'maven-central-proxy',
        format: 'MAVEN',
        kind: 'REMOTE',
        url: 'https://repo.maven.apache.org/maven2',
      }),
    ],
    pageInfo: mockPageInfo({ hasNextPage: true, endCursor: 'Y2FuZGlkYXRlcy1wYWdlLTE=' }),
  },
  {
    __typename: 'ArtifactRegistryRepositoryConnection',
    nodes: [
      mockCandidate({
        id: 'c1000000-0000-4000-8000-000000000004',
        name: 'spring-releases',
        format: 'MAVEN',
        kind: 'REMOTE',
        url: 'https://repo.spring.io/release',
      }),
    ],
    pageInfo: mockPageInfo(),
  },
];

export const mockEmptyUpstreamRepositoryCandidatePage = {
  __typename: 'ArtifactRegistryRepositoryConnection',
  nodes: [],
  pageInfo: mockPageInfo(),
};

export const mockUpstreamRepositoryCandidatesResponse = (connection) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: ORGANIZATION_GID,
      artifactRegistryRepositories: connection,
    },
  },
});

const BREADCRUMB_STATE_KEY = 'artifact_registry_breadcrumb';

export const createBreadCrumbState = () =>
  observable(BREADCRUMB_STATE_KEY, {
    artifactName: '',
    versionName: '',
    manifestName: '',
    updateArtifactName(value) {
      this.artifactName = value;
    },
    updateVersionName(value) {
      this.versionName = value;
    },
    updateManifestName(value) {
      this.manifestName = value;
    },
  });

export const resetBreadCrumbState = () => resetObservable(BREADCRUMB_STATE_KEY);
