import { TYPENAME_PROJECT, TYPENAME_USER } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { MILLISECONDS_IN_DAY, getStartOfDay } from '~/lib/utils/datetime/date_calculation_utility';
import { joinPaths } from '~/lib/utils/url_utility';
import {
  REPOSITORY_FORMAT_NPM,
  TYPENAME_ARTIFACT_REGISTRY_IMAGE,
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST,
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST_ANNOTATION,
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST_PLATFORM,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE,
  TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE,
  TYPENAME_ARTIFACT_REGISTRY_VERSION_DETAILS,
} from '../constants';
import { isContainerFormat } from '../utils';

const COMPONENTS = [
  'core',
  'api',
  'gateway',
  'auth',
  'billing',
  'catalog',
  'checkout',
  'client',
  'common',
  'config',
  'crypto',
  'dashboard',
  'events',
  'hooks',
  'icons',
  'ledger',
  'logging',
  'metrics',
  'notifier',
  'parser',
  'runtime',
  'scheduler',
  'storage',
  'telemetry',
  'utils',
];

const MAVEN_GROUP_PREFIX = 'com.example';

const NPM_SCOPE = '@company';

const MIN_ARTIFACTS = 3;

const MAX_ARTIFACTS = COMPONENTS.length;

// Every third npm package is unscoped, so a browser shows both the scoped and the unscoped
// display name.
const UNSCOPED_EVERY = 3;

const MIN_VERSIONS = 2;

const MAX_VERSIONS = 40;

const PATCHES_PER_MINOR = 5;

// A container's versions are its manifests, so an image carries a ladder of its own. Shorter
// than a package's, because a manifest is pushed per build rather than per release.
const MIN_SUBJECT_MANIFESTS = 2;

const MAX_SUBJECT_MANIFESTS = 34;

// The two media types Artifact Registry's internal/format/oci/mediatype.go accepts that a browser
// can tell apart, one of which its isIndexType predicate reads as an index.
const OCI_IMAGE_INDEX = 'application/vnd.oci.image.index.v1+json';

const OCI_IMAGE_MANIFEST = 'application/vnd.oci.image.manifest.v1+json';

// One artifact type per kind the Type column labels, plus one it has no label for and one absent
// entirely: the contract makes `artifact_type` nullable independently of `subject_digest`, so a
// browser renders the labelled cases, the raw fallback, and the bare referrer.
const REFERRER_ARTIFACT_TYPES = [
  'application/vnd.dev.cosign.artifact.sig.v1+json',
  'application/spdx+json',
  'application/vnd.in-toto.provenance+json',
  'application/vnd.example.custom.attestation.v1+json',
  null,
];

// A manifest's size counts the whole tree rooted at it - the config and every layer - which is
// why the floor is a megabyte rather than the few kilobytes the manifest document itself takes.
const MIN_MANIFEST_BYTES = 1048576;

const MAX_MANIFEST_BYTES = 524288000;

const MANIFEST_PLATFORMS = [
  { architecture: 'amd64', os: 'linux', osVariant: null },
  { architecture: 'arm64', os: 'linux', osVariant: 'v8' },
  { architecture: '386', os: 'linux', osVariant: null },
  { architecture: 'amd64', os: 'windows', osVariant: null },
];

const NO_PLATFORM = { architecture: null, os: null, osVariant: null };

const UNPLATFORMED_EVERY = 7;

const MAX_INDEX_CHILDREN = 3;

const TAG_NAMES = ['latest', 'stable', 'trixie', 'rc1', 'v1'];

const MAX_TAGS_PER_INDEX = TAG_NAMES.length;

const UNANNOTATED_EVERY = 5;

const EMPTY_ANNOTATIONS_EVERY = 3;

// A referrer attests to a manifest rather than holding layers of its own, so it is smaller than
// its subject by orders of magnitude.
const MIN_REFERRER_BYTES = 512;

const MAX_REFERRER_BYTES = 32768;

const MIN_VERSION_BYTES = 4096;

const MAX_VERSION_BYTES = 104857600;

const UNSIZED_EVERY = 4;

const ZERO_SIZED_POSITION = 1;

const MAVEN_SNAPSHOT_SUFFIX = '-SNAPSHOT';

const MAVEN_SNAPSHOT_POSITION = 0;

const PRERELEASE = '-rc.1';

const publisher = (id, name) => ({
  __typename: 'UserCore',
  id: convertToGraphQLId(TYPENAME_USER, id),
  name,
});

/* eslint-disable @gitlab/require-i18n-strings -- Mock data, not interface copy */
const CI_PUBLISHER = publisher(1, 'Alex Turner');

const MANUAL_PUBLISHER = publisher(2, 'Maria Santos');
/* eslint-enable @gitlab/require-i18n-strings */

const PUBLISHING_PROJECT_FULL_PATH = 'gitlab-org/payments-svc';

const PUBLISHING_PROJECT = {
  __typename: TYPENAME_PROJECT,
  id: convertToGraphQLId(TYPENAME_PROJECT, 1),
  name: 'payments-svc',
  fullPath: PUBLISHING_PROJECT_FULL_PATH,
  webPath: joinPaths('/', PUBLISHING_PROJECT_FULL_PATH),
};

// Artifact Registry makes the commit, the project, and the publisher nullable independently of one
// another, so the ladder walks every shape the version sidebar has to degrade through rather than
// attributing every version the same way.
const PUBLISH_SHAPES = [
  { fromCommit: true, project: PUBLISHING_PROJECT, createdBy: CI_PUBLISHER },
  { fromCommit: false, project: null, createdBy: MANUAL_PUBLISHER },
  { fromCommit: true, project: PUBLISHING_PROJECT, createdBy: null },
  // A project the viewer cannot see does not resolve, which is what leaves a sha unlinked.
  { fromCommit: true, project: null, createdBy: CI_PUBLISHER },
  { fromCommit: false, project: null, createdBy: null },
];

const PUBLISH_INTERVAL_DAYS = 2;

// How long ago a package's newest release can fall, so two packages' versions are not dated alike.
const PUBLISH_SPREAD_DAYS = 30;

// Pick a replacement pair only if every `hash * MULTIPLIER` stays exactly representable:
// past that, float rounding makes the hash non-deterministic and ids start colliding.
const hashOf = (seed) => {
  const MODULUS = 2147483647;
  const MULTIPLIER = 16807;

  return [...seed].reduce(
    (hash, character) => (hash * MULTIPLIER + character.codePointAt(0)) % MODULUS,
    1,
  );
};

const HEX_DIGITS_PER_HASH = 8;

const UUID_HEX_DIGITS = 32;

const hexFrom = (seed) => hashOf(seed).toString(16).padStart(HEX_DIGITS_PER_HASH, '0');

const hexOfWidth = (seed, digits) =>
  Array.from({ length: digits / HEX_DIGITS_PER_HASH }, (_, chunk) =>
    hexFrom(`${seed}$${chunk}`),
  ).join('');

const SHA_HEX_DIGITS = 40;

// A git sha at its full hex width, since the table shortens it for display and addresses the
// commit with the whole string.
const shaFrom = (seed) => hexOfWidth(seed, SHA_HEX_DIGITS);

const DIGEST_HEX_DIGITS = 64;

const DIGEST_ALGORITHM = 'sha256';

// Artifact Registry addresses a manifest by its digest, so this has to read as one: the full
// hex width of the algorithm it names, since the table shortens it for display and hands the
// whole string to the clipboard.
const digestFrom = (seed) =>
  `${DIGEST_ALGORITHM}:${Array.from(
    { length: DIGEST_HEX_DIGITS / HEX_DIGITS_PER_HASH },
    (_, chunk) => hexFrom(`${seed}@${chunk}`),
  ).join('')}`;

const uuidFrom = (seed) => {
  const digits = Array.from({ length: UUID_HEX_DIGITS / HEX_DIGITS_PER_HASH }, (_, chunk) =>
    hexFrom(`${seed}#${chunk}`),
  ).join('');

  return [
    digits.slice(0, 8),
    digits.slice(8, 12),
    digits.slice(12, 16),
    digits.slice(16, 20),
    digits.slice(20),
  ].join('-');
};

// Artifact Registry addresses an artifact by an opaque UUID, unlike a repository, which it
// addresses by name (api/openapi/v1.yaml, `ArtifactId`).
//
// Derived from the repository name and the position, never from the format: an id that moved
// with the format would address the same artifact differently under each shape, leaving a URL
// one read handed out dead to the next. Including the name keeps one repository's `image(id:)`
// from answering for another's artifact.
const artifactId = (name, index) => uuidFrom(`${name}#${index}`);

// Dated back from midnight rather than from the moment of the call, so two reads a moment apart
// date one ladder identically, and read per ladder rather than captured once, so a ladder follows
// the clock in force when it is generated. Nothing it dates falls after midnight, so every release
// reads as published already.
const publishedAt = (daysAgo) => {
  const midnight = getStartOfDay(new Date(), { utc: true }).getTime();

  return new Date(midnight - daysAgo * MILLISECONDS_IN_DAY).toISOString();
};

// The major follows the package's position, so two packages of one repository do not both read as
// one ladder; the minor and the patch follow the release's, so no two releases of one package read
// as one version.
const versionNumber = (index, position) =>
  `${index + 1}.${Math.floor(position / PATCHES_PER_MINOR)}.${position % PATCHES_PER_MINOR}`;

// A String, which is what the BigInt scalar the schema carries for a size serializes to.
const sizedBetween = (seed, minBytes, maxBytes) =>
  String(minBytes + (hashOf(seed) % (maxBytes - minBytes + 1)));

const versionSize = (seed, position) => {
  if (position === ZERO_SIZED_POSITION) return '0';

  if (hashOf(`${seed}#sized`) % UNSIZED_EVERY === 0) return null;

  return sizedBetween(`${seed}#size`, MIN_VERSION_BYTES, MAX_VERSION_BYTES);
};

// Seeded on the artifact's position rather than on the format, so the ladder under an artifact id
// is the same ladder whichever shape a read renders that artifact as.
const versionLadder = (name, index) => {
  const count =
    MIN_VERSIONS + (hashOf(`${name}#${index}#versions`) % (MAX_VERSIONS - MIN_VERSIONS + 1));
  const newestDaysAgo = hashOf(`${name}#${index}#published`) % PUBLISH_SPREAD_DAYS;

  return Array.from({ length: count }, (_, position) => {
    const seed = `${name}#${index}#version#${position}`;
    const { fromCommit, project, createdBy } = PUBLISH_SHAPES[position % PUBLISH_SHAPES.length];

    return {
      __typename: TYPENAME_ARTIFACT_REGISTRY_VERSION_DETAILS,
      id: uuidFrom(seed),
      version: `${versionNumber(index, position)}${position === count - 1 ? PRERELEASE : ''}`,
      createdAt: publishedAt(newestDaysAgo + (count - 1 - position) * PUBLISH_INTERVAL_DAYS),
      createdBy,
      project,
      gitCommitSha: fromCommit ? shaFrom(seed) : null,
      distTags: [],
      sizeBytes: versionSize(seed, position),
    };
  });
};

const NPM_DIST_TAGS_BY_OFFSET_FROM_NEWEST = [['next'], ['latest']];

const withNpmDistTags = (versions) =>
  versions.map((version, position) => ({
    ...version,
    distTags: NPM_DIST_TAGS_BY_OFFSET_FROM_NEWEST[versions.length - 1 - position] ?? [],
  }));

// The Maven snapshot suffix follows the format, which the format-blind ladder above cannot
// seed. Layered on afterwards, alongside the npm dist-tags.
const withFormatDetail = (versions, format) => {
  if (!format) return versions;

  if (format === REPOSITORY_FORMAT_NPM) return withNpmDistTags(versions);

  return versions.map((version, position) =>
    position === MAVEN_SNAPSHOT_POSITION
      ? { ...version, version: `${version.version}${MAVEN_SNAPSHOT_SUFFIX}` }
      : version,
  );
};

/* eslint-disable @gitlab/require-i18n-strings -- Mock data, not interface copy */
// No `title` or `source`: both name the image, and this builder is reached with its id.
const annotationsFor = (seed) => {
  const roll = hashOf(`${seed}#annotations`);

  if (roll % UNANNOTATED_EVERY === 0) return null;
  if (roll % EMPTY_ANNOTATIONS_EVERY === 0) return [];

  return [
    ['org.opencontainers.image.version', TAG_NAMES[roll % TAG_NAMES.length]],
    ['org.opencontainers.image.revision', hexFrom(`${seed}#revision`).slice(0, 40)],
    ['org.opencontainers.image.description', `Built from ${hexFrom(`${seed}#build`).slice(0, 8)}`],
  ].map(([key, value]) => ({
    __typename: TYPENAME_ARTIFACT_REGISTRY_MANIFEST_ANNOTATION,
    key,
    value,
  }));
};
/* eslint-enable @gitlab/require-i18n-strings */

// After both passes, not inside either: children, parents, and referrer counts read across rows.
const withManifestDetail = (rows, { name, index }) => {
  const indexRow = rows.find(({ mediaType }) => mediaType === OCI_IMAGE_INDEX);

  const children = rows
    .filter((row) => !row.subjectDigest && row !== indexRow)
    .slice(-MAX_INDEX_CHILDREN)
    .map((row, offset) => ({
      digest: row.digest,
      ...MANIFEST_PLATFORMS[offset % MANIFEST_PLATFORMS.length],
    }));

  const childPlatforms = new Map(children.map(({ digest, ...platform }) => [digest, platform]));

  const referrersBySubject = rows.reduce((bySubject, row) => {
    if (!row.subjectDigest) return bySubject;

    bySubject.set(row.subjectDigest, [...(bySubject.get(row.subjectDigest) ?? []), row]);

    return bySubject;
  }, new Map());

  return rows.map((row, position) => {
    const seed = `${name}#${index}#${row.digest}`;
    const isIndex = row === indexRow;

    let platform = childPlatforms.get(row.digest);

    if (!platform) {
      platform =
        isIndex || row.subjectDigest || hashOf(`${seed}#platform`) % UNPLATFORMED_EVERY === 0
          ? NO_PLATFORM
          : MANIFEST_PLATFORMS[position % MANIFEST_PLATFORMS.length];
    }

    // Not `referrers`: Apollo falls back to a same-named property on the parent when no
    // resolver answers a field, handing the connection a bare array.
    const referrerRows = (referrersBySubject.get(row.digest) ?? [])
      .map(({ id, digest, mediaType, artifactType, subjectDigest, createdAt }) => ({
        __typename: TYPENAME_ARTIFACT_REGISTRY_MANIFEST,
        id,
        digest,
        mediaType,
        artifactType,
        subjectDigest,
        createdAt,
      }))
      .sort((left, right) => (left.digest < right.digest ? -1 : 1));

    const tags = isIndex ? TAG_NAMES.slice(0, 1 + (hashOf(seed) % MAX_TAGS_PER_INDEX)).sort() : [];
    const parentDigests = childPlatforms.has(row.digest) ? [indexRow.digest] : [];
    const platformChildren = isIndex
      ? children.map((child) => ({
          __typename: TYPENAME_ARTIFACT_REGISTRY_MANIFEST_PLATFORM,
          ...child,
        }))
      : [];

    return {
      ...row,
      ...platform,
      tags,
      tagsCount: tags.length,
      children: platformChildren,
      childrenCount: platformChildren.length,
      parentDigests,
      parentsCount: parentDigests.length,
      referrerRows,
      referrersCount: referrerRows.length,
      annotations: annotationsFor(seed),
    };
  });
};

// The schema serves the manifests connection, but not a manifest by digest, so this ladder
// answers the detail read alone. Its digests are its own: they do not match the ones the
// connection returns, so the page is reachable by a seeded URL and not from a listed row.
//
// Built in two passes, subjects and then referrers, so every `subjectDigest` names a digest
// another manifest of the same image carries: a referrer pointing at nothing would have the Type
// column render a plausible label against a manifest a browser cannot open. Generated oldest
// first, so the newest-first order the connection imposes is ordering it does.
const manifestLadder = (name, index) => {
  const subjectCount =
    MIN_SUBJECT_MANIFESTS +
    (hashOf(`${name}#${index}#manifests`) % (MAX_SUBJECT_MANIFESTS - MIN_SUBJECT_MANIFESTS + 1));
  const newestDaysAgo = hashOf(`${name}#${index}#pushed`) % PUBLISH_SPREAD_DAYS;
  const total = subjectCount + REFERRER_ARTIFACT_TYPES.length;

  // The referrers fill the newer end, which is the order a push produces: nothing is attested to
  // before it is there to attest to.
  const pushedAt = (position) =>
    publishedAt(newestDaysAgo + (total - 1 - position) * PUBLISH_INTERVAL_DAYS);

  const subjects = Array.from({ length: subjectCount }, (_, position) => {
    const seed = `${name}#${index}#manifest#${position}`;

    return {
      __typename: TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS,
      id: uuidFrom(seed),
      digest: digestFrom(seed),
      // The newest of them is the multi-platform index, which is what a tag resolves to.
      mediaType: position === subjectCount - 1 ? OCI_IMAGE_INDEX : OCI_IMAGE_MANIFEST,
      artifactType: null,
      subjectDigest: null,
      size: sizedBetween(`${seed}#size`, MIN_MANIFEST_BYTES, MAX_MANIFEST_BYTES),
      createdAt: pushedAt(position),
    };
  });

  const referrers = REFERRER_ARTIFACT_TYPES.map((artifactType, offset) => {
    const seed = `${name}#${index}#referrer#${offset}`;

    return {
      __typename: TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS,
      id: uuidFrom(seed),
      digest: digestFrom(seed),
      mediaType: OCI_IMAGE_MANIFEST,
      artifactType,
      subjectDigest: subjects[hashOf(seed) % subjects.length].digest,
      size: sizedBetween(`${seed}#size`, MIN_REFERRER_BYTES, MAX_REFERRER_BYTES),
      createdAt: pushedAt(subjectCount + offset),
    };
  });

  return withManifestDetail([...subjects, ...referrers], { name, index });
};

const ladderPosition = (id) => hashOf(id) % MAX_ARTIFACTS;

export const versionLadderFor = (id, format) =>
  withFormatDetail(versionLadder(id, ladderPosition(id)), format);

export const manifestLadderFor = (id) => manifestLadder(id, ladderPosition(id));

// The repository name leads every readable name below, so a browser can tell which repository
// it is looking at.
const image = (name, index) => ({
  __typename: TYPENAME_ARTIFACT_REGISTRY_IMAGE,
  id: artifactId(name, index),
  name: `${name}/${COMPONENTS[index]}`,
});

const mavenPackage = (name, index) => ({
  __typename: TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE,
  id: artifactId(name, index),
  groupId: `${MAVEN_GROUP_PREFIX}.${name}`,
  artifactId: COMPONENTS[index],
});

const npmPackage = (name, index) => {
  const id = artifactId(name, index);
  const scope = index % UNSCOPED_EVERY === 0 ? null : NPM_SCOPE;
  const bareName = `${name}-${COMPONENTS[index]}`;

  return {
    __typename: TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE,
    id,
    name: scope ? `${scope}/${bareName}` : bareName,
    scope,
  };
};

// The container formats share the image shape because a repository of either holds images,
// which is also why one set of OCI Distribution Spec endpoints serves both.
const artifactBuilder = (format) => {
  if (isContainerFormat(format)) return image;

  if (format === REPOSITORY_FORMAT_NPM) return npmPackage;

  return mavenPackage;
};

// From the name alone: the detail read states this count beside a list resolved for the
// repository's format, so a count that moved with the format would contradict that list.
const artifactCount = (name) =>
  MIN_ARTIFACTS + (hashOf(name) % (MAX_ARTIFACTS - MIN_ARTIFACTS + 1));

// The artifacts a repository holds, generated from its name so every repository renders a
// list. A name generates the identical page on every call, which keeps an id the connection
// handed out resolvable by the single-artifact read that follows it.
export const mockArtifacts = (name, format) => {
  const build = artifactBuilder(format);

  return Array.from({ length: artifactCount(name) }, (_, index) => build(name, index));
};
