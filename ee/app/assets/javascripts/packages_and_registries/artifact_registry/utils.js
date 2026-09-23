import { numberToHumanSize } from '~/lib/utils/number_utils';
import { projectCommitPath } from '~/lib/utils/path_helpers/repository';
import { joinPaths } from '~/lib/utils/url_utility';
import { formatNumber, s__, sprintf } from '~/locale';
import {
  FILE_CHECKSUMS,
  FILES_EMPTY_DESCRIPTIONS,
  FILES_EMPTY_TITLES,
  MANIFEST_INDEX_MEDIA_TYPES,
  MANIFEST_KIND_IMAGE,
  MANIFEST_KIND_INDEX,
  MANIFEST_KIND_REFERRER,
  MANIFEST_KIND_SBOM,
  MANIFEST_KIND_SIGNATURE,
  MANIFEST_KIND_SLSA,
  MANIFEST_SBOM_ARTIFACT_TYPES,
  MANIFEST_SIGNATURE_ARTIFACT_TYPES,
  MANIFEST_SLSA_ARTIFACT_TYPES,
  MAVEN_FILE_CLASSIFIERS,
  REPOSITORY_FORMAT_CONTAINER_FAMILY,
  REPOSITORY_FORMAT_MAVEN,
  REPOSITORY_FORMAT_PATH_SEGMENTS,
  SHORT_DIGEST_LENGTH,
  VERSION_LIST_FAMILY_CONTAINERS,
  VERSION_LIST_FAMILY_PACKAGES,
  VERSIONS_TABLE_FIELDS,
} from './constants';

export const isContainerFormat = (format) => REPOSITORY_FORMAT_CONTAINER_FAMILY.includes(format);

export const versionListFamily = (format) =>
  isContainerFormat(format) ? VERSION_LIST_FAMILY_CONTAINERS : VERSION_LIST_FAMILY_PACKAGES;

export const versionsTableFields = (format) =>
  format === REPOSITORY_FORMAT_MAVEN
    ? VERSIONS_TABLE_FIELDS.filter(({ key }) => key !== 'tags')
    : VERSIONS_TABLE_FIELDS;

export const artifactDisplayName = (artifact, format) => {
  if (!artifact) return '';

  if (format === REPOSITORY_FORMAT_MAVEN) return `${artifact.groupId}:${artifact.artifactId}`;

  return artifact.name;
};

export const artifactDeleteLabel = (format) =>
  isContainerFormat(format)
    ? s__('ArtifactRegistry|Delete image')
    : s__('ArtifactRegistry|Delete package');

export const artifactDeleteCopy = (artifact, format) => ({
  ...(isContainerFormat(format)
    ? {
        title: s__('ArtifactRegistry|Delete image?'),
        body: s__(
          'ArtifactRegistry|This action permanently deletes image %{name} and all of its manifests. This action cannot be undone.',
        ),
      }
    : {
        title: s__('ArtifactRegistry|Delete package?'),
        body: s__(
          'ArtifactRegistry|This action permanently deletes package %{name} and all of its versions. This action cannot be undone.',
        ),
      }),
  name: artifactDisplayName(artifact, format),
  actionText: artifactDeleteLabel(format),
});

export const artifactDeletionScheduledMessage = (format) =>
  isContainerFormat(format)
    ? s__('ArtifactRegistry|Image successfully scheduled for deletion.')
    : s__('ArtifactRegistry|Package successfully scheduled for deletion.');

export const artifactActionsToggleText = (artifact, format) =>
  sprintf(s__('ArtifactRegistry|More actions for %{name}'), {
    name: artifactDisplayName(artifact, format),
  });

// An unrecognized extension is returned raw rather than blank: AR stores no file type, so the
// name is the only source there is.
export const fileType = (fileName, format) => {
  const name = fileName ?? '';
  const separator = name.lastIndexOf('.');

  if (separator < 1) return '';

  if (format === REPOSITORY_FORMAT_MAVEN) {
    const classifier = MAVEN_FILE_CLASSIFIERS.find((value) =>
      name.slice(0, separator).endsWith(`-${value}`),
    );

    if (classifier) return classifier;
  }

  return name.slice(separator + 1);
};

export const fileChecksums = (file, format) =>
  (FILE_CHECKSUMS[format] ?? [])
    .filter(({ key }) => Boolean(file?.[key]))
    .map(({ key, label }) => ({ key, label, value: file[key] }));

export const filesEmptyTitle = (format, versionString) =>
  sprintf(FILES_EMPTY_TITLES[format], { version: versionString });

export const filesEmptyDescription = (format) => FILES_EMPTY_DESCRIPTIONS[format];

export const toCount = (count) => Number(count ?? 0);

export const humanSize = (sizeBytes) => numberToHumanSize(toCount(sizeBytes));

export const shortDigest = (digest) => {
  if (!digest) return '';

  const [encoded = ''] = digest.split(':').slice(-1);

  return encoded.slice(0, SHORT_DIGEST_LENGTH);
};

export const formattedCount = (count) => formatNumber(toCount(count));

const MANIFEST_REFERRER_KINDS = [
  { types: MANIFEST_SIGNATURE_ARTIFACT_TYPES, kind: MANIFEST_KIND_SIGNATURE },
  { types: MANIFEST_SBOM_ARTIFACT_TYPES, kind: MANIFEST_KIND_SBOM },
  { types: MANIFEST_SLSA_ARTIFACT_TYPES, kind: MANIFEST_KIND_SLSA },
];

export const manifestType = ({ mediaType, artifactType, subjectDigest } = {}) => {
  if (subjectDigest) {
    const match = MANIFEST_REFERRER_KINDS.find(({ types }) => types.includes(artifactType));

    return {
      kind: match?.kind ?? MANIFEST_KIND_REFERRER,
      subjectDigest: shortDigest(subjectDigest),
      artifactType: match ? null : (artifactType ?? null),
    };
  }

  return {
    kind: MANIFEST_INDEX_MEDIA_TYPES.includes(mediaType)
      ? MANIFEST_KIND_INDEX
      : MANIFEST_KIND_IMAGE,
    subjectDigest: null,
    artifactType: null,
  };
};

export const manifestDeleteBody = (kind) => {
  switch (kind) {
    case MANIFEST_KIND_INDEX:
      return s__(
        'ArtifactRegistry|This action permanently deletes manifest %{name} and any tags pointing to it. Its child manifests are not deleted and will remain in Artifact Registry as untagged, standalone manifests. This action cannot be undone.',
      );
    case MANIFEST_KIND_SIGNATURE:
      return s__(
        'ArtifactRegistry|This action permanently deletes signature %{name} and any tags pointing to it. The image it signs will then verify as unsigned. This action cannot be undone.',
      );
    default:
      return s__(
        'ArtifactRegistry|This action permanently deletes manifest %{name} and any tags pointing to it. This action cannot be undone.',
      );
  }
};

export const platformLabel = ({ architecture, os, osVariant } = {}) => {
  const [system, arch, variant] = [os, architecture, osVariant].map((part) => {
    if (typeof part !== 'string') return null;

    const trimmed = part.trim();

    return trimmed && !trimmed.includes('/') ? trimmed : null;
  });

  const parts = [system, arch].filter(Boolean);

  // A variant qualifies an architecture, so it is dropped without one rather than read as one.
  if (arch && variant) parts.push(variant);

  return parts.join('/');
};

export const commitPath = ({ project, gitCommitSha } = {}) =>
  project && gitCommitSha ? projectCommitPath(project.fullPath, gitCommitSha) : null;

// A filter travels through the route query in lowercase rather than in the GraphQL
// enum spelling, because the URL is user-facing and shareable. Translating at that one
// boundary keeps an already-shared link working across an enum rename, and confines the
// enum spelling to the layer that talks to the schema.
export const toFilterQueryValue = (enumValue) => enumValue?.toLowerCase() ?? null;

// An unrecognized value reads as no filter rather than reaching the query, so a
// hand-edited or stale URL renders the unfiltered list instead of an error. Matching
// against the known values, rather than indexing a lookup object, keeps an inherited
// property name such as `constructor` from reading as a match.
export const toFilterEnumValue = (queryValue, enumValues) =>
  enumValues.find((value) => value.toLowerCase() === queryValue) ?? null;

export const toSortEnumValue = ({ sortBy, sortDesc }, columns) =>
  `${columns[sortBy]}_${sortDesc ? 'DESC' : 'ASC'}`;

// A Map rather than an object, so `constructor` resolves to nothing rather than to an
// inherited property.
const TABLE_SORTS = new WeakMap();

const tableSorts = (columns) => {
  if (!TABLE_SORTS.has(columns)) {
    TABLE_SORTS.set(
      columns,
      new Map(
        Object.entries(columns).flatMap(([sortBy, column]) => [
          [`${column}_ASC`, { sortBy, sortDesc: false }],
          [`${column}_DESC`, { sortBy, sortDesc: true }],
        ]),
      ),
    );
  }

  return TABLE_SORTS.get(columns);
};

export const toTableSort = (enumValue, columns) => {
  const sort = tableSorts(columns).get(enumValue);

  // A copy, so the shared entry cannot be written through by whoever holds the sort.
  return sort ? { ...sort } : null;
};

// The name a route gives itself, defined once for the trail and the document title. A
// route naming a dynamic segment reads that segment's param; one whose segment is an
// opaque id names itself through `meta.nameGenerator`, as the other registry SPAs do, and
// falls back to the param until the page publishes something readable.
export const routeName = ({ meta, params }) =>
  meta.useId ? meta.nameGenerator?.() || params[meta.idParam ?? 'id'] : meta.text;

// Prepending each matched route's name to the base title labels the page and updates the
// browser tab and history entry. Pure, so the shell can re-derive it whenever the route or
// a resolved name changes; a router hook could only run once, on navigation. This is not a
// reliable route-change announcement on its own (screen readers announce title changes
// inconsistently on SPA navigation); focus is moved to the view container on each route
// change (see app.vue) to make the change perceivable.
export const buildDocumentTitle = ({ matched, params }, baseTitle) =>
  matched.reduce((title, { meta }) => {
    // The root route holds the Repositories crumb and is matched on every route, so
    // folding its text in would name the SPA root on every page, over a Rails page
    // title that already names it.
    if (meta.skipTitle) return title;

    // `meta.text` is the crumb, which the trail can abbreviate because the crumbs
    // ahead of it carry the rest; `meta.title` is where a route that reads that way
    // names itself in full.
    const text = meta.title ?? routeName({ meta, params });

    return text ? `${text} · ${title}` : title;
  }, baseTitle);

// A container image reference and a registry host both take an address rather than a
// URL, so the scheme comes off. Any scheme, not just http(s), since the origin is
// configuration and nothing constrains it to those two.
export const withoutScheme = (url) => url.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');

export const buildRegistryClientUrl = ({ clientBaseUrl, handle }) => {
  if (!clientBaseUrl || !handle) return null;

  return joinPaths(clientBaseUrl, handle);
};

// Composed rather than read, because Artifact Registry returns no URL on the repository
// resource and the origin reaches the browser as mount data.
export const buildRepositoryClientUrl = ({ clientBaseUrl, slug, format, name }) => {
  const registryUrl = buildRegistryClientUrl({ clientBaseUrl, handle: slug });
  const formatSegment = REPOSITORY_FORMAT_PATH_SEGMENTS[format];

  if (!registryUrl || !formatSegment || !name) return null;

  return joinPaths(registryUrl, formatSegment, encodeURIComponent(name));
};
