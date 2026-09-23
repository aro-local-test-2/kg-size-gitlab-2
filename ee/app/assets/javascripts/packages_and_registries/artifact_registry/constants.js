import dockerLogoUrl from '@gitlab/svgs/dist/illustrations/logos/docker.svg?url';
import mavenLogoUrl from '@gitlab/svgs/dist/illustrations/logos/maven.svg?url';
import npmLogoUrl from '@gitlab/svgs/dist/illustrations/logos/npm.svg?url';
import { DOCS_URL } from '~/constants';
import { __, s__ } from '~/locale';

export const NOT_FOUND_ROUTE_NAME = 'not_found';

export const PAGE_NOT_FOUND_TITLE = __('Page not found');

export const REPOSITORIES_LIST_ROUTE_NAME = 'repositories_list';

export const REPOSITORY_DETAIL_ROUTE_NAME = 'repository_detail';

export const REPOSITORY_NEW_HOSTED_ROUTE_NAME = 'repository_new_hosted';

export const REPOSITORY_NEW_REMOTE_ROUTE_NAME = 'repository_new_remote';

export const REPOSITORY_NEW_VIRTUAL_ROUTE_NAME = 'repository_new_virtual';

export const REPOSITORIES_LIST_TITLE = s__('ArtifactRegistry|Repositories');

export const REPOSITORY_KIND_NEW_TITLES = {
  HOSTED: s__('ArtifactRegistry|New hosted repository'),
  REMOTE: s__('ArtifactRegistry|New remote repository'),
  VIRTUAL: s__('ArtifactRegistry|New virtual repository'),
};

export const REPOSITORY_EDIT_ROUTE_NAME = 'repository_edit';

export const ARTIFACT_VERSIONS_ROUTE_NAME = 'artifact_versions';

export const VERSION_DETAIL_ROUTE_NAME = 'version_detail';

export const MANIFEST_DETAIL_ROUTE_NAME = 'manifest_detail';

export const REPOSITORY_KIND_EDIT_TITLES = {
  HOSTED: s__('ArtifactRegistry|Edit hosted repository'),
  REMOTE: s__('ArtifactRegistry|Edit remote repository'),
  VIRTUAL: s__('ArtifactRegistry|Edit virtual repository'),
};

// The crumb ahead of this one is the repository being edited, so the trail names the
// action alone where the document title has to name the whole page.
export const REPOSITORY_EDIT_CRUMB = __('Edit');

export const REPOSITORY_KIND_DESCRIPTIONS = {
  HOSTED: s__(
    'ArtifactRegistry|A hosted repository directly hosts artifacts. You can publish artifacts to and pull them from a hosted repository.',
  ),
  REMOTE: s__(
    'ArtifactRegistry|A remote repository points to an external registry. Create a remote repository and connect it to multiple virtual repositories.',
  ),
  VIRTUAL: s__(
    'ArtifactRegistry|A virtual repository combines other repositories behind one endpoint. It resolves artifacts from an ordered list of upstream repositories.',
  ),
};

// Not translated, like REGISTRY_HANDLE_PLACEHOLDER above: the example name has to satisfy
// REPOSITORY_NAME_PATTERN, and a translated string is not guaranteed to.
export const REPOSITORY_KIND_NAME_PLACEHOLDERS = {
  HOSTED: 'my-hosted-repository',
  REMOTE: 'my-remote-repository',
  VIRTUAL: 'my-virtual-repository',
};

export const TYPENAME_ARTIFACT_REGISTRY_REPOSITORY = 'ArtifactRegistryRepository';

export const TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS = 'ArtifactRegistryRepositoryDetails';

export const TYPENAME_ARTIFACT_REGISTRY_UPSTREAM_REPOSITORY_ASSOCIATION =
  'ArtifactRegistryUpstreamRepositoryAssociation';

export const TYPENAME_ARTIFACT_REGISTRY_UPSTREAM_REPOSITORY_SUMMARY =
  'ArtifactRegistryUpstreamRepositorySummary';

export const TYPENAME_ARTIFACT_REGISTRY_IMAGE = 'ArtifactRegistryImage';

export const TYPENAME_ARTIFACT_REGISTRY_PACKAGE = 'ArtifactRegistryPackage';

// The union the single-package read returns, over the two detail types below. The list returns
// the plain union above.
export const TYPENAME_ARTIFACT_REGISTRY_PACKAGE_DETAILS = 'ArtifactRegistryPackageDetails';

export const TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE = 'ArtifactRegistryMavenPackage';

export const TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE = 'ArtifactRegistryNpmPackage';

export const TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS =
  'ArtifactRegistryMavenPackageDetails';

export const TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS = 'ArtifactRegistryNpmPackageDetails';

export const TYPENAME_ARTIFACT_REGISTRY_VERSION_DETAILS = 'ArtifactRegistryVersionDetails';

export const TYPENAME_ARTIFACT_REGISTRY_MAVEN_VERSION_FILE = 'ArtifactRegistryMavenVersionFile';

export const TYPENAME_ARTIFACT_REGISTRY_NPM_VERSION_FILE = 'ArtifactRegistryNpmVersionFile';

export const TYPENAME_ARTIFACT_REGISTRY_MANIFEST = 'ArtifactRegistryManifest';

export const TYPENAME_ARTIFACT_REGISTRY_MANIFEST_CONNECTION = 'ArtifactRegistryManifestConnection';

export const TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS = 'ArtifactRegistryManifestDetails';

export const TYPENAME_ARTIFACT_REGISTRY_MANIFEST_PLATFORM = 'ArtifactRegistryManifestPlatform';

export const TYPENAME_ARTIFACT_REGISTRY_MANIFEST_ANNOTATION = 'ArtifactRegistryManifestAnnotation';

export const TYPENAME_ORGANIZATION = 'Organization';

export const REPOSITORY_PERMISSION_READ_REPOSITORY = 'readRepository';

export const REPOSITORY_PERMISSION_UPDATE_REPOSITORY = 'updateRepository';

export const REPOSITORY_PERMISSION_DELETE_REPOSITORY = 'deleteRepository';

export const REPOSITORY_PERMISSION_CREATE_REPOSITORY_UPSTREAM = 'createRepositoryUpstream';

export const REPOSITORY_PERMISSION_UPDATE_REPOSITORY_UPSTREAM = 'updateRepositoryUpstream';

export const REPOSITORY_PERMISSION_DELETE_REPOSITORY_UPSTREAM = 'deleteRepositoryUpstream';

export const REPOSITORY_PERMISSION_READ_ARTIFACT = 'readArtifact';

export const REPOSITORY_PERMISSION_CREATE_ARTIFACT = 'createArtifact';

export const REPOSITORY_PERMISSION_DELETE_ARTIFACT = 'deleteArtifact';

export const NAMESPACE_PERMISSION_READ_REPOSITORY = 'readRepository';

export const NAMESPACE_PERMISSION_CREATE_REPOSITORY = 'createRepository';

export const NAMESPACE_PERMISSION_UPDATE_REPOSITORY = 'updateRepository';

export const NAMESPACE_PERMISSION_DELETE_REPOSITORY = 'deleteRepository';

export const NAMESPACE_PERMISSION_CREATE_REPOSITORY_UPSTREAM = 'createRepositoryUpstream';

export const NAMESPACE_PERMISSION_UPDATE_REPOSITORY_UPSTREAM = 'updateRepositoryUpstream';

export const NAMESPACE_PERMISSION_DELETE_REPOSITORY_UPSTREAM = 'deleteRepositoryUpstream';

export const REPOSITORY_KIND_HOSTED = 'HOSTED';

export const REPOSITORY_KIND_REMOTE = 'REMOTE';

export const REPOSITORY_KIND_VIRTUAL = 'VIRTUAL';

// Private only for the closed beta: Internal and Public are deferred to GA, so the
// write path offers a single value rather than narrowing the shared read enum.
export const REPOSITORY_VISIBILITY_PRIVATE = 'PRIVATE';

// Transcribed from the Artifact Registry repository contract (api/openapi/v1.yaml, as
// implemented in internal/managementapi/create.go): a name is 1 to 255 lowercase
// alphanumeric characters that may be separated by '.', '_', or '-', and must start and
// end with an alphanumeric character. The name is a path segment in the client APIs, so
// the pattern is what keeps it URL-safe. Artifact Registry remains the authority; these
// bounds only spare a round trip for input it would certainly reject.
export const REPOSITORY_NAME_PATTERN = /^[a-z0-9](?:[a-z0-9._-]*[a-z0-9])?$/;

export const REPOSITORY_NAME_MAX_LENGTH = 255;

// Transcribed from the Artifact Registry namespace contract (api/openapi/gitlab-v1.yaml),
// which states the slug rules in prose and carries no pattern to generate from.
export const REGISTRY_HANDLE_CHARSET_PATTERN = /^[a-z0-9-]+$/;

export const REGISTRY_HANDLE_BOUNDARY_PATTERN = /^[a-z0-9](?:.*[a-z0-9])?$/;

export const REGISTRY_HANDLE_MIN_LENGTH = 3;

export const REGISTRY_HANDLE_MAX_LENGTH = 63;

// Not translated: a handle is drawn from a fixed charset, so a translated one would not
// be a legal handle in every locale.
export const REGISTRY_HANDLE_PLACEHOLDER = 'my-registry';

// A status with no entry here arrives with the affordance that produces it, so its
// wording comes from design rather than being derived ahead of it.
export const REGISTRY_STATUS_INDICATIONS = {
  active: s__('ArtifactRegistry|Artifact Registry is enabled'),
  disabled: s__('ArtifactRegistry|Artifact Registry is disabled'),
};

// `status` is a string rather than an enum because Artifact Registry may add values, so an
// unlisted value reads as this rather than as a blank condition.
export const REGISTRY_STATUS_INDICATION_UNKNOWN = s__(
  'ArtifactRegistry|Artifact Registry is not available for this organization',
);

export const REGISTRY_ACTION_DISABLE = 'disable';

export const REGISTRY_ACTION_ENABLE = 'enable';

// A condition Artifact Registry imposed for security or billing reasons is not the
// organization owner's to lift, so a status absent here carries no action at all.
export const REGISTRY_STATUS_ACTIONS = {
  active: REGISTRY_ACTION_DISABLE,
  disabled: REGISTRY_ACTION_ENABLE,
};

export const REPOSITORY_DESCRIPTION_MAX_LENGTH = 1024;

// The MVP formats, mirroring the Artifact Registry repository-resource contract. The
// Docker and OCI split replaces the former single container format. Alphabetical,
// because the create form renders these in declaration order and defaults to the first.
export const REPOSITORY_FORMAT_LABELS = {
  DOCKER: s__('ArtifactRegistry|Docker'),
  MAVEN: s__('ArtifactRegistry|Maven'),
  NPM: s__('ArtifactRegistry|npm'),
  OCI: s__('ArtifactRegistry|OCI'),
};

export const REPOSITORY_FORMAT_OPTIONS = Object.entries(REPOSITORY_FORMAT_LABELS).map(
  ([value, text]) => ({ value, text }),
);

export const REPOSITORY_FORMAT_VALUES = Object.keys(REPOSITORY_FORMAT_LABELS);

export const REPOSITORY_FORMAT_DOCKER = 'DOCKER';

export const REPOSITORY_FORMAT_MAVEN = 'MAVEN';

export const REPOSITORY_FORMAT_NPM = 'NPM';

export const REPOSITORY_FORMAT_OCI = 'OCI';

export const REPOSITORY_FORMAT_CONTAINER_FAMILY = [REPOSITORY_FORMAT_DOCKER, REPOSITORY_FORMAT_OCI];

export const FILES_EMPTY_TITLES = {
  [REPOSITORY_FORMAT_MAVEN]: s__('ArtifactRegistry|Version %{version} stores no files'),
  [REPOSITORY_FORMAT_NPM]: s__('ArtifactRegistry|Version %{version} stores no file'),
};

export const FILES_EMPTY_DESCRIPTIONS = {
  [REPOSITORY_FORMAT_MAVEN]: s__(
    'ArtifactRegistry|Its files may have been deleted from the registry.',
  ),
  [REPOSITORY_FORMAT_NPM]: s__(
    'ArtifactRegistry|Its file may have been deleted from the registry.',
  ),
};

// The unfiltered default carries a sentinel value rather than null, because
// GlCollapsibleListbox reads a null selection as nothing selected and falls back to
// its placeholder. ALL is not an Artifact Registry format, so it shadows no value the
// list endpoint can filter on.
export const REPOSITORY_FORMAT_ALL = 'ALL';

export const REPOSITORY_FORMAT_FILTER_OPTIONS = [
  { value: REPOSITORY_FORMAT_ALL, text: s__('ArtifactRegistry|All formats') },
  ...REPOSITORY_FORMAT_OPTIONS,
];

// A format is absent here until its logo exists, and renders as a letter avatar in the
// meantime. OCI is the one such format: its logo waits on Linux Foundation trademark
// approval, tracked in
// https://gitlab.com/gitlab-com/legal-and-compliance/-/work_items/3607.
export const REPOSITORY_FORMAT_LOGOS = {
  MAVEN: mavenLogoUrl,
  NPM: npmLogoUrl,
  DOCKER: dockerLogoUrl,
};

// The size the list reads the logo at. 16px left the wordmark logos, which fit their
// width rather than their height, too small to read.
export const REPOSITORY_FORMAT_LOGO_SIZE_LIST = 32;

// A page heading carries the largest logo, and is the same size on every route that has
// one.
export const REPOSITORY_FORMAT_LOGO_SIZE_HEADING = 48;

// The listbox lists the formats a line of text at a time, so its logos match that line.
export const REPOSITORY_FORMAT_LOGO_SIZE_LISTBOX = 16;

// The segment a format occupies in a client URL (ADR-009). Not translated: these are
// URL path segments, not labels. Docker and OCI share `container`, because one set of
// OCI Distribution Spec endpoints serves repositories of both formats, so the segment
// names the protocol family rather than the repository's own format.
export const REPOSITORY_FORMAT_PATH_SEGMENTS = {
  DOCKER: 'container',
  MAVEN: 'maven',
  NPM: 'npm',
  OCI: 'container',
};

export const REPOSITORY_FORMAT_HELP_PATHS = {
  DOCKER: `${DOCS_URL}/artifact-registry/formats/docker/`,
  MAVEN: `${DOCS_URL}/artifact-registry/formats/maven/`,
  NPM: `${DOCS_URL}/artifact-registry/formats/npm/`,
  OCI: `${DOCS_URL}/artifact-registry/formats/oci/`,
};

export const VIRTUAL_UPSTREAMS_EMPTY_TITLE = s__(
  'ArtifactRegistry|No repositories added to this virtual repository yet',
);
export const VIRTUAL_UPSTREAMS_EMPTY_DESCRIPTION = s__(
  'ArtifactRegistry|A virtual registry acts as a single access point that routes requests across one or more hosted and remote repositories. %{linkStart}More information%{linkEnd}',
);
export const VIRTUAL_UPSTREAMS_DOCS_URL = `${DOCS_URL}/artifact-registry/repositories/#virtual-repositories`;

export const REPOSITORY_KIND_LABELS = {
  HOSTED: s__('ArtifactRegistry|Hosted'),
  VIRTUAL: s__('ArtifactRegistry|Virtual'),
  REMOTE: s__('ArtifactRegistry|Remote'),
};

export const REPOSITORY_KIND_VALUES = Object.keys(REPOSITORY_KIND_LABELS);

// Closed beta supports private only: both public and internal grant read without a
// role assignment, which breaks closed-by-default, so ADR-021 defers them to GA.
export const REPOSITORY_VISIBILITY_LABELS = {
  PRIVATE: s__('ArtifactRegistry|Private'),
};

export const REPOSITORY_VISIBILITY_ICONS = {
  PRIVATE: 'lock',
};

export const REPOSITORY_VISIBILITY_DESCRIPTIONS = {
  PRIVATE: s__('ArtifactRegistry|Access is limited to members with explicit permissions only.'),
};

export const REPOSITORY_CACHE_VALIDITY_MIN = 0;

export const REPOSITORY_METADATA_CACHE_VALIDITY_MIN = 1;

export const REPOSITORY_CACHE_VALIDITY_MAX = 32767;

export const REPOSITORY_CACHE_VALIDITY_DEFAULT = 24;

export const REPOSITORY_HEALTH_STATUS_HEALTHY = 'HEALTHY';

export const REPOSITORY_HEALTH_STATUS_UNHEALTHY = 'UNHEALTHY';

export const REPOSITORY_HEALTH_STATUS_UNKNOWN = 'UNKNOWN';

export const CONNECTION_TEST_MESSAGES = {
  reachable: s__('ArtifactRegistry|Connection successful.'),
  unreachable: s__('ArtifactRegistry|Failed to connect. Check the URL and credentials.'),
};

export const GRAPHQL_PAGE_SIZE = 20;

// The columns the list endpoint sorts on, keyed by table field. It also sorts on
// artifacts_count, left out because the list renders no such column.
export const REPOSITORY_SORT_COLUMNS = {
  name: 'NAME',
  downloadsCount: 'DOWNLOADS_COUNT',
  sizeBytes: 'SIZE_BYTES',
  lastUpdatedAt: 'LAST_UPDATED_AT',
};

const sortValues = (columns) =>
  Object.values(columns).flatMap((column) => [`${column}_ASC`, `${column}_DESC`]);

export const REPOSITORY_SORT_VALUES = sortValues(REPOSITORY_SORT_COLUMNS);

export const REPOSITORY_SORT_DEFAULT = 'LAST_UPDATED_AT_DESC';

// The columns the two artifact list endpoints sort on, keyed by table field. The manifests
// endpoint sorts on created_at alone, which is all its sort enum offers.
export const VERSION_SORT_COLUMNS = {
  version: 'VERSION',
  createdAt: 'CREATED_AT',
};

export const MANIFEST_SORT_COLUMNS = {
  createdAt: 'CREATED_AT',
};

export const VERSION_SORT_VALUES = sortValues(VERSION_SORT_COLUMNS);

export const MANIFEST_SORT_VALUES = sortValues(MANIFEST_SORT_COLUMNS);

export const ARTIFACT_SORT_DEFAULT = 'CREATED_AT_DESC';

// Scoped to neither user nor namespace, the way the monolith's other sort keys are, so
// two accounts sharing a browser profile share a sort column.
export const REPOSITORIES_SORT_STORAGE_KEY = 'artifact-registry-repositories-sort';

export const REPOSITORIES_OPTIONAL_COLUMNS = [
  'kind',
  'downloadsCount',
  'sizeBytes',
  'lastUpdatedAt',
];

// Every cell centers vertically, because the rows are as tall as their tallest cell
// and the row actions menu is taller than a line of text.
const CELL_CLASS = '!gl-align-middle';

// The header stays visible, per the additional-actions guidance in
// https://design.gitlab.com/components/table#additional-actions, and is aligned with the menu
// it names, which sits at the end of the row. `thAlignRight` rather than a text-alignment
// class: GlTable wraps every header in a flex container, which lays its label out as a flex
// item that `gl-text-right` cannot move.
const ACTIONS_FIELD = {
  key: 'actions',
  label: __('Actions'),
  thAlignRight: true,
  tdClass: `${CELL_CLASS} gl-text-right`,
};

export const REPOSITORIES_TABLE_FIELDS = [
  { key: 'format', label: s__('ArtifactRegistry|Format'), tdClass: CELL_CLASS },
  { key: 'name', label: s__('ArtifactRegistry|Name'), tdClass: CELL_CLASS, sortable: true },
  { key: 'kind', label: s__('ArtifactRegistry|Type'), tdClass: CELL_CLASS },
  {
    key: 'downloadsCount',
    label: s__('ArtifactRegistry|Downloads'),
    tdClass: CELL_CLASS,
    sortable: true,
  },
  { key: 'sizeBytes', label: s__('ArtifactRegistry|Size'), tdClass: CELL_CLASS, sortable: true },
  {
    key: 'lastUpdatedAt',
    label: s__('ArtifactRegistry|Last updated'),
    tdClass: CELL_CLASS,
    sortable: true,
  },
  { ...ACTIONS_FIELD },
];

const IMAGE_NAME_FIELD = {
  key: 'name',
  label: s__('ArtifactRegistry|Image'),
  tdClass: CELL_CLASS,
};

const PACKAGE_NAME_FIELD = {
  key: 'name',
  label: s__('ArtifactRegistry|Package'),
  tdClass: CELL_CLASS,
};

const VERSIONS_FIELD = {
  key: 'versionsCount',
  label: s__('ArtifactRegistry|Versions'),
  tdClass: CELL_CLASS,
};

const LAST_DOWNLOADED_FIELD = {
  key: 'lastDownloadedAt',
  label: s__('ArtifactRegistry|Last downloaded'),
  tdClass: CELL_CLASS,
};

// No Versions column on any remote format: no remote artifact read supplies a count to put in
// one.
export const ARTIFACTS_TABLE_FIELDS = {
  [REPOSITORY_KIND_HOSTED]: {
    DOCKER: [IMAGE_NAME_FIELD, { ...ACTIONS_FIELD }],
    OCI: [IMAGE_NAME_FIELD, { ...ACTIONS_FIELD }],
    MAVEN: [PACKAGE_NAME_FIELD, { ...ACTIONS_FIELD }],
    NPM: [PACKAGE_NAME_FIELD, VERSIONS_FIELD, { ...ACTIONS_FIELD }],
  },
  [REPOSITORY_KIND_REMOTE]: {
    DOCKER: [IMAGE_NAME_FIELD, LAST_DOWNLOADED_FIELD, { ...ACTIONS_FIELD }],
    OCI: [IMAGE_NAME_FIELD, LAST_DOWNLOADED_FIELD, { ...ACTIONS_FIELD }],
    MAVEN: [PACKAGE_NAME_FIELD, LAST_DOWNLOADED_FIELD, { ...ACTIONS_FIELD }],
    NPM: [PACKAGE_NAME_FIELD, LAST_DOWNLOADED_FIELD, { ...ACTIONS_FIELD }],
  },
};

export const VERSIONS_TABLE_FIELDS = [
  { key: 'version', label: s__('ArtifactRegistry|Version'), tdClass: CELL_CLASS, sortable: true },
  { key: 'tags', label: s__('ArtifactRegistry|Tags'), tdClass: CELL_CLASS },
  { key: 'sizeBytes', label: s__('ArtifactRegistry|Size'), tdClass: CELL_CLASS },
  {
    key: 'createdAt',
    label: s__('ArtifactRegistry|Published'),
    tdClass: CELL_CLASS,
    sortable: true,
  },
  { key: 'source', label: s__('ArtifactRegistry|Source'), tdClass: CELL_CLASS },
  { ...ACTIONS_FIELD },
];

export const FILES_TABLE_FIELDS = [
  { key: 'fileName', label: s__('ArtifactRegistry|File'), tdClass: CELL_CLASS },
  { key: 'type', label: s__('ArtifactRegistry|Type'), tdClass: CELL_CLASS },
  { key: 'sizeBytes', label: s__('ArtifactRegistry|Size'), tdClass: CELL_CLASS },
  { key: 'createdAt', label: s__('ArtifactRegistry|Created'), tdClass: CELL_CLASS },
];

export const MANIFESTS_TABLE_FIELDS = [
  { key: 'digest', label: s__('ArtifactRegistry|Digest'), tdClass: CELL_CLASS },
  { key: 'type', label: s__('ArtifactRegistry|Type'), tdClass: CELL_CLASS },
  { key: 'size', label: s__('ArtifactRegistry|Size'), tdClass: CELL_CLASS },
  {
    key: 'createdAt',
    label: s__('ArtifactRegistry|Published'),
    tdClass: CELL_CLASS,
    sortable: true,
  },
  { ...ACTIONS_FIELD },
];

// The widths are load-bearing rather than cosmetic; the table is laid out fixed.
export const REFERRERS_TABLE_FIELDS = [
  {
    key: 'digest',
    label: s__('ArtifactRegistry|Digest'),
    tdClass: CELL_CLASS,
    thClass: 'gl-w-1/5',
  },
  {
    key: 'artifactType',
    label: s__('ArtifactRegistry|Artifact type'),
    tdClass: CELL_CLASS,
    thClass: 'gl-w-3/5',
  },
  {
    key: 'createdAt',
    label: s__('ArtifactRegistry|Published'),
    tdClass: CELL_CLASS,
    thClass: 'gl-w-1/5',
  },
];

export const UPSTREAM_REPOSITORIES_TABLE_FIELDS = [
  {
    key: 'position',
    label: s__('ArtifactRegistry|Order'),
    tdClass: `${CELL_CLASS} gl-text-center`,
    thClass: 'gl-w-1/10',
  },
  {
    key: 'name',
    label: s__('ArtifactRegistry|Repository'),
    tdClass: CELL_CLASS,
    thClass: 'gl-w-3/5',
  },
  {
    key: 'kind',
    label: s__('ArtifactRegistry|Type'),
    tdClass: CELL_CLASS,
    thClass: 'gl-w-1/5',
  },
  { ...ACTIONS_FIELD, thClass: 'gl-w-1/10' },
];

export const UPSTREAM_REPOSITORIES_ORDER_HELP = s__(
  'ArtifactRegistry|Repositories are checked in this order when resolving an artifact. To reorder, edit this repository.',
);

export const UPSTREAM_REPOSITORIES_CAP = 20;

export const UPSTREAM_REPOSITORIES_ORDER_TABLE_FIELDS = [
  {
    key: 'position',
    label: s__('ArtifactRegistry|Order'),
    tdClass: `${CELL_CLASS} gl-text-center`,
    thClass: 'gl-w-px gl-whitespace-nowrap',
  },
  {
    key: 'name',
    label: s__('ArtifactRegistry|Repository'),
    tdClass: CELL_CLASS,
    thClass: 'gl-w-1/2',
  },
  {
    key: 'kind',
    label: s__('ArtifactRegistry|Type'),
    tdClass: CELL_CLASS,
  },
  {
    key: 'sizeBytes',
    label: s__('ArtifactRegistry|Size'),
    tdClass: CELL_CLASS,
  },
  { ...ACTIONS_FIELD },
];

export const VERSION_LIST_FAMILY_PACKAGES = 'packages';

export const VERSION_LIST_FAMILY_CONTAINERS = 'containers';

// The columns the view-options popover offers a switch for, by table field key. Each family's
// row-identity column is absent by omission -- Version for a package, Digest for a container --
// and so is the actions column, which is an affordance rather than data.
export const VERSION_LIST_OPTIONAL_COLUMNS = {
  [VERSION_LIST_FAMILY_PACKAGES]: ['tags', 'sizeBytes', 'createdAt', 'source'],
  [VERSION_LIST_FAMILY_CONTAINERS]: ['type', 'size', 'createdAt'],
};

export const VERSION_LIST_COLUMNS_STORAGE_KEY = 'artifact-registry-version-list-columns';

export const REFERRERS_QUERY_KEY = 'include_referrers';

export const REFERRERS_EXCLUDED_QUERY_VALUE = 'false';

export const SHORT_DIGEST_LENGTH = 12;

// The Maven classifiers that name a file's type better than its extension does: a sources jar
// and a javadoc jar are both `.jar`, and the classifier is the only thing telling them apart.
export const MAVEN_FILE_CLASSIFIERS = ['sources', 'javadoc'];

export const FILE_CHECKSUMS = {
  MAVEN: [
    // eslint-disable-next-line @gitlab/require-i18n-strings -- A checksum algorithm name is not translated.
    { key: 'md5', label: 'MD5' },
    { key: 'sha1', label: 'SHA-1' },
    { key: 'sha256', label: 'SHA-256' },
    { key: 'sha512', label: 'SHA-512' },
  ],
  NPM: [{ key: 'sha256', label: 'SHA-256' }],
};

export const MANIFEST_INDEX_MEDIA_TYPES = [
  'application/vnd.oci.image.index.v1+json',
  'application/vnd.docker.distribution.manifest.list.v2+json',
];

export const MANIFEST_SIGNATURE_ARTIFACT_TYPES = [
  'application/vnd.dev.cosign.artifact.sig.v1+json',
  'application/vnd.dev.cosign.simplesigning.v1+json',
];

export const MANIFEST_SBOM_ARTIFACT_TYPES = [
  'application/spdx+json',
  'application/vnd.cyclonedx+json',
  'application/vnd.dev.cosign.artifact.sbom.v1+json',
];

// `application/vnd.in-toto+json` is the in-toto envelope, which carries any predicate: it says
// nothing about SLSA provenance, so it is not listed here and renders as a raw artifact type.
export const MANIFEST_SLSA_ARTIFACT_TYPES = ['application/vnd.in-toto.provenance+json'];

export const MANIFEST_KIND_INDEX = 'index';

export const MANIFEST_KIND_IMAGE = 'image';

export const MANIFEST_KIND_SIGNATURE = 'signature';

export const MANIFEST_KIND_SBOM = 'sbom';

export const MANIFEST_KIND_SLSA = 'slsa';

export const MANIFEST_KIND_REFERRER = 'referrer';

// The bare noun only: the manifests table wraps these in its own "%{kind} for %{digest}"
// sentence, so a digest baked in here would render twice there.
export const MANIFEST_KIND_LABELS = {
  [MANIFEST_KIND_INDEX]: s__('ArtifactRegistry|Index'),
  [MANIFEST_KIND_IMAGE]: s__('ArtifactRegistry|Image'),
  [MANIFEST_KIND_SIGNATURE]: s__('ArtifactRegistry|Signature'),
  [MANIFEST_KIND_SBOM]: s__('ArtifactRegistry|SBOM attestation'),
  [MANIFEST_KIND_SLSA]: s__('ArtifactRegistry|SLSA attestation'),
  [MANIFEST_KIND_REFERRER]: s__('ArtifactRegistry|Referrer'),
};

export const SETUP_INSTRUCTIONS_TITLE = s__('ArtifactRegistry|Setup instructions');

export const SETUP_SECTION_INSTALL = 'install';

export const SETUP_SECTION_PUBLISH = 'publish';

export const SETUP_TOOL_MAVEN = 'maven';

export const SETUP_TOOL_GRADLE_GROOVY = 'gradle_groovy';

export const SETUP_TOOL_GRADLE_KOTLIN = 'gradle_kotlin';

export const SETUP_TOOL_SBT = 'sbt';

export const SETUP_TOOL_NPM = 'npm';

export const SETUP_TOOL_YARN = 'yarn';

export const SETUP_TOOL_PNPM = 'pnpm';

export const SETUP_TOOL_DOCKER = 'docker';

export const SETUP_TOOL_PODMAN = 'podman';

// One set of OCI Distribution Spec endpoints serves both formats, so the same clients
// reach either. Shared rather than spelled out twice, so a new container tool cannot be
// added to one format and forgotten on the other.
const CONTAINER_SETUP_TOOLS = [
  { value: SETUP_TOOL_DOCKER, text: s__('ArtifactRegistry|Docker CLI') },
  { value: SETUP_TOOL_PODMAN, text: s__('ArtifactRegistry|Podman') },
];

export const SETUP_TOOLS = {
  DOCKER: CONTAINER_SETUP_TOOLS,
  OCI: CONTAINER_SETUP_TOOLS,
  MAVEN: [
    { value: SETUP_TOOL_MAVEN, text: s__('ArtifactRegistry|Maven') },
    { value: SETUP_TOOL_GRADLE_GROOVY, text: s__('ArtifactRegistry|Gradle (Groovy)') },
    { value: SETUP_TOOL_GRADLE_KOTLIN, text: s__('ArtifactRegistry|Gradle (Kotlin)') },
    { value: SETUP_TOOL_SBT, text: s__('ArtifactRegistry|sbt') },
  ],
  NPM: [
    { value: SETUP_TOOL_NPM, text: s__('ArtifactRegistry|npm') },
    { value: SETUP_TOOL_YARN, text: s__('ArtifactRegistry|yarn') },
    { value: SETUP_TOOL_PNPM, text: s__('ArtifactRegistry|pnpm') },
  ],
};
