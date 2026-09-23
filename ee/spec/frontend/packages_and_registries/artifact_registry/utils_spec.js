import {
  REPOSITORY_SORT_COLUMNS,
  VERSION_SORT_COLUMNS,
  VERSIONS_TABLE_FIELDS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import {
  artifactActionsToggleText,
  artifactDeleteCopy,
  artifactDeleteLabel,
  artifactDeletionScheduledMessage,
  artifactDisplayName,
  buildRegistryClientUrl,
  buildRepositoryClientUrl,
  commitPath,
  fileChecksums,
  fileType,
  filesEmptyDescription,
  filesEmptyTitle,
  isContainerFormat,
  toFilterEnumValue,
  buildDocumentTitle,
  manifestDeleteBody,
  manifestType,
  platformLabel,
  routeName,
  shortDigest,
  toFilterQueryValue,
  toSortEnumValue,
  toTableSort,
  versionsTableFields,
} from 'ee/packages_and_registries/artifact_registry/utils';
import { CLIENT_BASE_URL, SLUG } from './mock_data';

describe('isContainerFormat', () => {
  it.each(['DOCKER', 'OCI'])('reads %s as a container format', (format) => {
    expect(isContainerFormat(format)).toBe(true);
  });

  it.each(['MAVEN', 'NPM', undefined])('reads %p as not a container format', (format) => {
    expect(isContainerFormat(format)).toBe(false);
  });
});

describe('versionsTableFields', () => {
  const keysFor = (format) => versionsTableFields(format).map(({ key }) => key);

  it('offers npm every column, the Tags column among them', () => {
    expect(keysFor('NPM')).toEqual([
      'version',
      'tags',
      'sizeBytes',
      'createdAt',
      'source',
      'actions',
    ]);
    expect(versionsTableFields('NPM')).toBe(VERSIONS_TABLE_FIELDS);
  });

  it('drops the Tags column for Maven, which has no tags', () => {
    expect(keysFor('MAVEN')).toEqual(['version', 'sizeBytes', 'createdAt', 'source', 'actions']);
  });
});

describe('artifactDisplayName', () => {
  it('names a Maven package by its coordinates', () => {
    expect(
      artifactDisplayName({ groupId: 'com.company.payment', artifactId: 'core' }, 'MAVEN'),
    ).toBe('com.company.payment:core');
  });

  it('names a scoped npm package by the name alone, which already carries the scope', () => {
    expect(artifactDisplayName({ scope: '@company', name: '@company/design-system' }, 'NPM')).toBe(
      '@company/design-system',
    );
  });

  it('names an unscoped npm package by its name', () => {
    expect(artifactDisplayName({ scope: null, name: 'design-tokens' }, 'NPM')).toBe(
      'design-tokens',
    );
  });

  it.each(['DOCKER', 'OCI'])('names a %s image by its name', (format) => {
    expect(artifactDisplayName({ name: 'payment-service' }, format)).toBe('payment-service');
  });

  it.each([null, undefined])(
    'reads %p as no name, so a pending read renders nothing',
    (artifact) => {
      expect(artifactDisplayName(artifact, 'MAVEN')).toBe('');
    },
  );
});

describe('artifactDeleteCopy', () => {
  const IMAGE_BODY =
    'This action permanently deletes image %{name} and all of its manifests. This action cannot be undone.';
  const PACKAGE_BODY =
    'This action permanently deletes package %{name} and all of its versions. This action cannot be undone.';

  const artifact = { name: 'payments-api', groupId: 'com.example', artifactId: 'demo' };

  it.each`
    format      | title                | body            | name                  | actionText
    ${'DOCKER'} | ${'Delete image?'}   | ${IMAGE_BODY}   | ${'payments-api'}     | ${'Delete image'}
    ${'OCI'}    | ${'Delete image?'}   | ${IMAGE_BODY}   | ${'payments-api'}     | ${'Delete image'}
    ${'MAVEN'}  | ${'Delete package?'} | ${PACKAGE_BODY} | ${'com.example:demo'} | ${'Delete package'}
    ${'NPM'}    | ${'Delete package?'} | ${PACKAGE_BODY} | ${'payments-api'}     | ${'Delete package'}
  `(
    'names a $format deletion the way its family is named',
    ({ format, title, body, name, actionText }) => {
      expect(artifactDeleteCopy(artifact, format)).toEqual({ title, body, name, actionText });
    },
  );

  it('names nothing when no artifact is chosen yet', () => {
    expect(artifactDeleteCopy(null, 'NPM')).toMatchObject({ name: '' });
  });

  it('leaves the name as a placeholder for the caller to fill', () => {
    expect(artifactDeleteCopy(null, 'MAVEN').body).toContain('%{name}');
  });
});

describe('artifactDeleteLabel', () => {
  it.each`
    format      | label
    ${'DOCKER'} | ${'Delete image'}
    ${'OCI'}    | ${'Delete image'}
    ${'MAVEN'}  | ${'Delete package'}
    ${'NPM'}    | ${'Delete package'}
  `('names a $format deletion "$label"', ({ format, label }) => {
    expect(artifactDeleteLabel(format)).toBe(label);
  });
});

describe('artifactDeletionScheduledMessage', () => {
  it.each`
    format      | message
    ${'DOCKER'} | ${'Image successfully scheduled for deletion.'}
    ${'OCI'}    | ${'Image successfully scheduled for deletion.'}
    ${'MAVEN'}  | ${'Package successfully scheduled for deletion.'}
    ${'NPM'}    | ${'Package successfully scheduled for deletion.'}
  `('reports a $format deletion as "$message"', ({ format, message }) => {
    expect(artifactDeletionScheduledMessage(format)).toBe(message);
  });
});

describe('artifactActionsToggleText', () => {
  it('names the artifact by its display name', () => {
    expect(
      artifactActionsToggleText({ groupId: 'com.company.payment', artifactId: 'core' }, 'MAVEN'),
    ).toBe('More actions for com.company.payment:core');
  });
});

describe('fileType', () => {
  it.each`
    fileName                    | type
    ${'core-2.4.1.jar'}         | ${'jar'}
    ${'core-2.4.1.pom'}         | ${'pom'}
    ${'core-2.4.1-sources.jar'} | ${'sources'}
    ${'core-2.4.1-javadoc.jar'} | ${'javadoc'}
  `('reads $fileName as $type', ({ fileName, type }) => {
    expect(fileType(fileName, 'MAVEN')).toBe(type);
  });

  it('reads an npm tarball by its extension', () => {
    expect(fileType('design-system-4.2.0.tgz', 'NPM')).toBe('tgz');
  });

  it('renders an unrecognized extension raw rather than blank', () => {
    expect(fileType('maven-metadata.xml', 'MAVEN')).toBe('xml');
  });

  it('reads a timestamped SNAPSHOT build by its extension', () => {
    expect(fileType('core-2.4.1-20260812.101500-3.jar', 'MAVEN')).toBe('jar');
  });

  it('reads a classified SNAPSHOT build by its classifier', () => {
    expect(fileType('core-2.4.1-20260812.101500-3-sources.jar', 'MAVEN')).toBe('sources');
  });

  it('takes the last extension of a name carrying several', () => {
    expect(fileType('core-2.4.1.jar.asc', 'MAVEN')).toBe('asc');
  });

  it('claims no classifier on a format that has none, so an npm name cannot read as Maven', () => {
    expect(fileType('design-system-4.2.0-sources.tgz', 'NPM')).toBe('tgz');
  });

  it.each(['README', 'LICENSE'])('reads %s as no type, having no extension to read', (fileName) => {
    expect(fileType(fileName, 'MAVEN')).toBe('');
  });

  it('reads a dotfile as no type, because its leading dot names no extension', () => {
    expect(fileType('.npmrc', 'NPM')).toBe('');
  });

  it.each([null, undefined, ''])('reads %p as no type', (fileName) => {
    expect(fileType(fileName, 'MAVEN')).toBe('');
  });
});

describe('fileChecksums', () => {
  const mavenFile = { md5: 'm', sha1: '1', sha256: '256', sha512: '512' };

  it('orders a Maven file weakest checksum first', () => {
    expect(fileChecksums(mavenFile, 'MAVEN')).toEqual([
      { key: 'md5', label: 'MD5', value: 'm' },
      { key: 'sha1', label: 'SHA-1', value: '1' },
      { key: 'sha256', label: 'SHA-256', value: '256' },
      { key: 'sha512', label: 'SHA-512', value: '512' },
    ]);
  });

  it.each`
    case           | file
    ${'a null'}    | ${{ ...mavenFile, md5: null }}
    ${'an empty'}  | ${{ ...mavenFile, md5: '' }}
    ${'an absent'} | ${{ sha1: '1', sha256: '256', sha512: '512' }}
  `('drops $case checksum, rather than carrying a blank', ({ file }) => {
    expect(fileChecksums(file, 'MAVEN').map(({ key }) => key)).toEqual([
      'sha1',
      'sha256',
      'sha512',
    ]);
  });

  it('reads only the checksum the contract serializes for an npm file', () => {
    expect(fileChecksums({ sha256: '256' }, 'NPM')).toEqual([
      { key: 'sha256', label: 'SHA-256', value: '256' },
    ]);
  });

  it.each(['DOCKER', 'OCI', undefined])('reads no checksum for a %s file', (format) => {
    expect(fileChecksums(mavenFile, format)).toEqual([]);
  });

  it('reads no checksum for an absent file', () => {
    expect(fileChecksums(undefined, 'MAVEN')).toEqual([]);
  });
});

describe('filesEmptyTitle', () => {
  it.each`
    format     | title
    ${'MAVEN'} | ${'Version 3.2.1 stores no files'}
    ${'NPM'}   | ${'Version 3.2.1 stores no file'}
  `('names the version in the $format title, in that format’s number', ({ format, title }) => {
    expect(filesEmptyTitle(format, '3.2.1')).toBe(title);
  });

  it('is the one the version detail announcement and the empty state heading both read', () => {
    expect(filesEmptyTitle('MAVEN', '9.9.9')).toBe('Version 9.9.9 stores no files');
  });
});

describe('filesEmptyDescription', () => {
  it.each`
    format     | description
    ${'MAVEN'} | ${'Its files may have been deleted from the registry.'}
    ${'NPM'}   | ${'Its file may have been deleted from the registry.'}
  `('reads in the $format number', ({ format, description }) => {
    expect(filesEmptyDescription(format)).toBe(description);
  });
});

describe('shortDigest', () => {
  const DIGEST = `sha256:${'ab12cd34'.repeat(8)}`;

  it('keeps twelve characters of a canonical digest and drops the algorithm', () => {
    expect(shortDigest(DIGEST)).toBe('ab12cd34ab12');
  });

  it('shortens a digest that arrives without an algorithm prefix', () => {
    expect(shortDigest('ab12cd34'.repeat(8))).toBe('ab12cd34ab12');
  });

  it('drops the algorithm whatever it is, rather than assuming sha256', () => {
    expect(shortDigest(`sha512:${'ff'.repeat(64)}`)).toBe('ffffffffffff');
  });

  it('reads a digest shorter than the cut as itself', () => {
    expect(shortDigest('sha256:abc')).toBe('abc');
  });

  it.each([null, undefined, ''])('renders %p as no digest at all', (digest) => {
    expect(shortDigest(digest)).toBe('');
  });
});

describe('manifestType', () => {
  const SUBJECT = `sha256:${'ab12cd34'.repeat(8)}`;

  describe('a manifest carrying no subject', () => {
    it.each([
      'application/vnd.oci.image.index.v1+json',
      'application/vnd.docker.distribution.manifest.list.v2+json',
    ])('reads %s as an index', (mediaType) => {
      expect(manifestType({ mediaType })).toStrictEqual({
        kind: 'index',
        subjectDigest: null,
        artifactType: null,
      });
    });

    it.each([
      'application/vnd.oci.image.manifest.v1+json',
      'application/vnd.docker.distribution.manifest.v2+json',
    ])('reads %s as a single image', (mediaType) => {
      expect(manifestType({ mediaType }).kind).toBe('image');
    });

    it.each(['application/vnd.example.future+json', undefined, null])(
      'falls back to an image for %p rather than rendering nothing',
      (mediaType) => {
        expect(manifestType({ mediaType }).kind).toBe('image');
      },
    );

    it('ignores an artifactType when no subject makes it a referrer', () => {
      expect(
        manifestType({
          mediaType: 'application/vnd.oci.image.manifest.v1+json',
          artifactType: 'application/spdx+json',
        }),
      ).toStrictEqual({ kind: 'image', subjectDigest: null, artifactType: null });
    });
  });

  describe('a manifest carrying a subject', () => {
    const referrer = (artifactType) =>
      manifestType({
        mediaType: 'application/vnd.oci.image.manifest.v1+json',
        artifactType,
        subjectDigest: SUBJECT,
      });

    it.each([
      'application/vnd.dev.cosign.artifact.sig.v1+json',
      'application/vnd.dev.cosign.simplesigning.v1+json',
    ])('reads the cosign type %s as a signature', (artifactType) => {
      expect(referrer(artifactType)).toStrictEqual({
        kind: 'signature',
        subjectDigest: 'ab12cd34ab12',
        artifactType: null,
      });
    });

    it.each([
      'application/spdx+json',
      'application/vnd.cyclonedx+json',
      'application/vnd.dev.cosign.artifact.sbom.v1+json',
    ])('reads %s as an SBOM', (artifactType) => {
      expect(referrer(artifactType).kind).toBe('sbom');
    });

    it('reads application/vnd.in-toto.provenance+json as SLSA provenance', () => {
      expect(referrer('application/vnd.in-toto.provenance+json').kind).toBe('slsa');
    });

    // The in-toto envelope carries any predicate, so it says nothing about SLSA provenance.
    it('reads the bare in-toto envelope as a referrer, naming its type verbatim', () => {
      expect(referrer('application/vnd.in-toto+json')).toStrictEqual({
        kind: 'referrer',
        subjectDigest: 'ab12cd34ab12',
        artifactType: 'application/vnd.in-toto+json',
      });
    });

    it('hands back an unrecognized type verbatim, since OCI artifact types are an open set', () => {
      expect(referrer('application/vnd.example.custom.v1+json')).toStrictEqual({
        kind: 'referrer',
        subjectDigest: 'ab12cd34ab12',
        artifactType: 'application/vnd.example.custom.v1+json',
      });
    });

    it.each([null, undefined])(
      'stays a referrer with no type to name when the artifactType is %p',
      (artifactType) => {
        expect(referrer(artifactType)).toStrictEqual({
          kind: 'referrer',
          subjectDigest: 'ab12cd34ab12',
          artifactType: null,
        });
      },
    );

    it('does not read an inherited property name as a known type', () => {
      expect(referrer('constructor').kind).toBe('referrer');
    });
  });

  it('reads a missing manifest as an image rather than throwing', () => {
    expect(manifestType().kind).toBe('image');
  });
});

describe('manifestDeleteBody', () => {
  it('warns an index that its children outlive it, since they are what survives untagged', () => {
    expect(manifestDeleteBody('index')).toBe(
      'This action permanently deletes manifest %{name} and any tags pointing to it. Its child manifests are not deleted and will remain in Artifact Registry as untagged, standalone manifests. This action cannot be undone.',
    );
  });

  it('warns a signature that the image it signs is left verifying as unsigned', () => {
    expect(manifestDeleteBody('signature')).toBe(
      'This action permanently deletes signature %{name} and any tags pointing to it. The image it signs will then verify as unsigned. This action cannot be undone.',
    );
  });

  it.each(['image', 'sbom', 'slsa', 'referrer', undefined])(
    'states the plain body for %s',
    (kind) => {
      expect(manifestDeleteBody(kind)).toBe(
        'This action permanently deletes manifest %{name} and any tags pointing to it. This action cannot be undone.',
      );
    },
  );
});

describe('platformLabel', () => {
  it.each`
    architecture | os           | osVariant | label
    ${'amd64'}   | ${'linux'}   | ${null}   | ${'linux/amd64'}
    ${'arm64'}   | ${'linux'}   | ${'v8'}   | ${'linux/arm64/v8'}
    ${'386'}     | ${'linux'}   | ${null}   | ${'linux/386'}
    ${'amd64'}   | ${'windows'} | ${null}   | ${'windows/amd64'}
  `('reads $os $architecture $osVariant as $label', ({ architecture, os, osVariant, label }) => {
    expect(platformLabel({ architecture, os, osVariant })).toBe(label);
  });

  describe('a triple carrying only some of its values', () => {
    it.each`
      case                                | platform                                                         | label
      ${'an architecture'}                | ${{ architecture: 'amd64', os: null }}                           | ${'amd64'}
      ${'an operating system'}            | ${{ architecture: null, os: 'linux' }}                           | ${'linux'}
      ${'an empty string'}                | ${{ architecture: 'amd64', os: 'linux', osVariant: '' }}         | ${'linux/amd64'}
      ${'an empty operating system'}      | ${{ architecture: 'amd64', os: '' }}                             | ${'amd64'}
      ${'an empty architecture'}          | ${{ architecture: '', os: 'linux' }}                             | ${'linux'}
      ${'a whitespace-only architecture'} | ${{ architecture: '  ', os: 'linux' }}                           | ${'linux'}
      ${'a whitespace-only os'}           | ${{ architecture: 'amd64', os: ' ' }}                            | ${'amd64'}
      ${'a padded triple'}                | ${{ architecture: ' arm64 ', os: ' linux ', osVariant: ' v8 ' }} | ${'linux/arm64/v8'}
      ${'a non-string value'}             | ${{ architecture: 386, os: 'linux' }}                            | ${'linux'}
    `('renders $case as $label', ({ platform, label }) => {
      expect(platformLabel(platform)).toBe(label);
    });

    it('drops a variant with no architecture to qualify, rather than reading it as one', () => {
      expect(platformLabel({ architecture: null, os: 'linux', osVariant: 'v8' })).toBe('linux');
    });

    it('keeps a variant when the architecture it qualifies survives without an os', () => {
      expect(platformLabel({ architecture: 'arm64', os: null, osVariant: 'v8' })).toBe('arm64/v8');
    });
  });

  describe('a part carrying the separator', () => {
    it.each`
      case                     | platform                                                     | label
      ${'an architecture'}     | ${{ architecture: 'amd64/v8', os: 'linux' }}                 | ${'linux'}
      ${'an operating system'} | ${{ architecture: 'amd64', os: 'linux/gnu' }}                | ${'amd64'}
      ${'a variant'}           | ${{ architecture: 'arm64', os: 'linux', osVariant: 'v8/x' }} | ${'linux/arm64'}
      ${'a lone slash'}        | ${{ architecture: '/', os: 'linux' }}                        | ${'linux'}
    `('drops $case rather than reading it as two parts', ({ platform, label }) => {
      expect(platformLabel(platform)).toBe(label);
    });

    it('does not let a forged architecture render as a real variant', () => {
      const forged = platformLabel({ architecture: 'amd64/v8', os: 'linux' });
      const real = platformLabel({ architecture: 'amd64', os: 'linux', osVariant: 'v8' });

      expect(forged).not.toBe(real);
    });
  });

  it.each([
    [
      'an index, whose triple is null throughout',
      { architecture: null, os: null, osVariant: null },
    ],
    ['a manifest whose config never parsed', {}],
  ])('renders %s as no platform at all', (_, platform) => {
    expect(platformLabel(platform)).toBe('');
  });

  it('reads a missing platform as no platform rather than throwing', () => {
    expect(platformLabel()).toBe('');
  });
});

describe('commitPath', () => {
  const project = { fullPath: 'gitlab-org/payments-svc' };
  const gitCommitSha = 'f19ac02a8d3b41e57c9f0a4d2b8e6135ac97d40e';

  it('addresses the commit under the project it was published from', () => {
    expect(commitPath({ project, gitCommitSha })).toBe(
      `/gitlab-org/payments-svc/-/commit/${gitCommitSha}`,
    );
  });

  it.each([
    ['the project did not resolve', { project: null, gitCommitSha }],
    ['the version names no commit', { project, gitCommitSha: null }],
    ['the version carries no attribution', {}],
    ['there is no version yet', undefined],
  ])('has no path to offer when %s', (_reason, version) => {
    expect(commitPath(version)).toBeNull();
  });
});

describe('toFilterQueryValue', () => {
  it('lowercases an enum value for the route query', () => {
    expect(toFilterQueryValue('MAVEN')).toBe('maven');
  });

  it.each([null, undefined])('reads %p as no filter', (value) => {
    expect(toFilterQueryValue(value)).toBe(null);
  });
});

describe('toFilterEnumValue', () => {
  const values = ['DOCKER', 'MAVEN', 'NPM', 'OCI'];

  it('resolves a lowercase query value to its enum value', () => {
    expect(toFilterEnumValue('npm', values)).toBe('NPM');
  });

  it.each([null, undefined, '', 'rubygems'])('reads %p as no filter', (value) => {
    expect(toFilterEnumValue(value, values)).toBe(null);
  });

  // Matching against the known values rather than indexing a lookup object is what
  // keeps an inherited property name from reading as a match.
  it.each(['constructor', 'toString', '__proto__'])(
    'reads the inherited property name %p as no filter',
    (value) => {
      expect(toFilterEnumValue(value, values)).toBe(null);
    },
  );

  it('does not match an enum value spelled in its own case', () => {
    expect(toFilterEnumValue('NPM', values)).toBe(null);
  });
});

describe('toSortEnumValue', () => {
  it.each([
    [{ sortBy: 'name', sortDesc: false }, 'NAME_ASC'],
    [{ sortBy: 'name', sortDesc: true }, 'NAME_DESC'],
    [{ sortBy: 'downloadsCount', sortDesc: false }, 'DOWNLOADS_COUNT_ASC'],
    [{ sortBy: 'sizeBytes', sortDesc: true }, 'SIZE_BYTES_DESC'],
    [{ sortBy: 'lastUpdatedAt', sortDesc: true }, 'LAST_UPDATED_AT_DESC'],
  ])('turns the table sort %p into %s', (sort, enumValue) => {
    expect(toSortEnumValue(sort, REPOSITORY_SORT_COLUMNS)).toBe(enumValue);
  });

  it.each([
    [{ sortBy: 'version', sortDesc: false }, 'VERSION_ASC'],
    [{ sortBy: 'createdAt', sortDesc: true }, 'CREATED_AT_DESC'],
  ])('turns the version table sort %p into %s', (sort, enumValue) => {
    expect(toSortEnumValue(sort, VERSION_SORT_COLUMNS)).toBe(enumValue);
  });
});

describe('toTableSort', () => {
  it.each([
    ['NAME_ASC', { sortBy: 'name', sortDesc: false }],
    ['NAME_DESC', { sortBy: 'name', sortDesc: true }],
    ['DOWNLOADS_COUNT_ASC', { sortBy: 'downloadsCount', sortDesc: false }],
    ['SIZE_BYTES_DESC', { sortBy: 'sizeBytes', sortDesc: true }],
    ['LAST_UPDATED_AT_DESC', { sortBy: 'lastUpdatedAt', sortDesc: true }],
  ])('turns the enum value %s into the table sort %p', (enumValue, sort) => {
    expect(toTableSort(enumValue, REPOSITORY_SORT_COLUMNS)).toEqual(sort);
  });

  it.each([
    ['VERSION_ASC', { sortBy: 'version', sortDesc: false }],
    ['CREATED_AT_DESC', { sortBy: 'createdAt', sortDesc: true }],
  ])('turns the enum value %s into the version table sort %p', (enumValue, sort) => {
    expect(toTableSort(enumValue, VERSION_SORT_COLUMNS)).toEqual(sort);
  });

  it('reads a column the given set does not carry as no sort', () => {
    expect(toTableSort('NAME_ASC', VERSION_SORT_COLUMNS)).toBe(null);
  });

  // A sort column the list renders no column for, and one the enum never carried.
  it.each([null, undefined, '', 'ARTIFACTS_COUNT_DESC', 'NAME', 'NAME_SIDEWAYS'])(
    'reads %p as no sort',
    (enumValue) => {
      expect(toTableSort(enumValue, REPOSITORY_SORT_COLUMNS)).toBe(null);
    },
  );

  // A Map rather than an object is what keeps an inherited property name from resolving
  // to something that is not a sort.
  it.each(['constructor', 'toString', '__proto__'])(
    'reads the inherited property name %p as no sort',
    (enumValue) => {
      expect(toTableSort(enumValue, REPOSITORY_SORT_COLUMNS)).toBe(null);
    },
  );

  // The sort is handed on as a prop, so a caller must not write through to the lookup.
  it('returns a copy, so a caller cannot write through to the next call', () => {
    const first = toTableSort('NAME_ASC', REPOSITORY_SORT_COLUMNS);

    first.sortDesc = true;

    expect(toTableSort('NAME_ASC', REPOSITORY_SORT_COLUMNS)).toEqual({
      sortBy: 'name',
      sortDesc: false,
    });
  });
});

describe('routeName', () => {
  it('reads the crumb text for a route with no dynamic segment', () => {
    expect(routeName({ meta: { text: 'Repositories' }, params: {} })).toBe('Repositories');
  });

  it('reads the param a dynamic route names', () => {
    expect(routeName({ meta: { useId: true }, params: { id: 'payment-core' } })).toBe(
      'payment-core',
    );
  });

  it('reads the param named in meta.idParam', () => {
    expect(
      routeName({
        meta: { useId: true, idParam: 'artifactId' },
        params: { id: 'payment-core', artifactId: 'abc' },
      }),
    ).toBe('abc');
  });

  it.each([
    ['the id param', { useId: true }, {}],
    ['the param named in meta.idParam', { useId: true, idParam: 'artifactId' }, { id: 'abc' }],
  ])('resolves no name for a dynamic route missing %s', (_, meta, params) => {
    expect(routeName({ meta, params })).toBeUndefined();
  });

  it('prefers the name the route resolves over its param', () => {
    expect(
      routeName({
        meta: {
          useId: true,
          idParam: 'artifactId',
          nameGenerator: () => 'com.company.payment:core',
        },
        params: { artifactId: 'abc' },
      }),
    ).toBe('com.company.payment:core');
  });

  it('falls back to the param until a name resolves', () => {
    expect(
      routeName({
        meta: { useId: true, idParam: 'artifactId', nameGenerator: () => '' },
        params: { artifactId: 'abc' },
      }),
    ).toBe('abc');
  });
});

describe('buildDocumentTitle', () => {
  const route = (metas, params = {}) => ({ matched: metas.map((meta) => ({ meta })), params });

  it('prepends each matched route name in nesting order', () => {
    expect(buildDocumentTitle(route([{ text: 'Parent' }, { text: 'Child' }]), 'Base')).toBe(
      'Child · Parent · Base',
    );
  });

  it('leaves the base title unchanged when no matched route names itself', () => {
    expect(buildDocumentTitle(route([{}]), 'Base')).toBe('Base');
  });

  it('leaves the base title unchanged when a dynamic route resolves no name', () => {
    expect(buildDocumentTitle(route([{ useId: true }]), 'Base')).toBe('Base');
  });

  it('skips a route that opts out of the title', () => {
    expect(buildDocumentTitle(route([{ text: 'Repositories', skipTitle: true }]), 'Base')).toBe(
      'Base',
    );
  });

  it('prefers meta.title over the crumb text', () => {
    expect(buildDocumentTitle(route([{ text: 'Edit', title: 'Edit repository' }]), 'Base')).toBe(
      'Edit repository · Base',
    );
  });

  it('titles each dynamic route from its own param', () => {
    const title = buildDocumentTitle(
      route([{ useId: true }, { useId: true, idParam: 'artifactId' }], {
        id: 'payment-core',
        artifactId: 'abc',
      }),
      'Base',
    );

    expect(title).toBe('abc · payment-core · Base');
  });

  it('titles a route by the name it resolved, over its param', () => {
    const title = buildDocumentTitle(
      route([{ useId: true, idParam: 'artifactId', nameGenerator: () => 'core' }], {
        artifactId: 'abc',
      }),
      'Base',
    );

    expect(title).toBe('core · Base');
  });
});

describe('buildRegistryClientUrl', () => {
  const buildUrl = (overrides = {}) =>
    buildRegistryClientUrl({ clientBaseUrl: CLIENT_BASE_URL, handle: SLUG, ...overrides });

  it('composes the registry URL from the Artifact Registry origin and the handle', () => {
    expect(buildUrl()).toBe(`${CLIENT_BASE_URL}/${SLUG}`);
  });

  it('joins the base URL cleanly when it carries a trailing slash', () => {
    expect(buildUrl({ clientBaseUrl: `${CLIENT_BASE_URL}/` })).toBe(`${CLIENT_BASE_URL}/${SLUG}`);
  });

  it.each([
    ['the instance configures no Artifact Registry', { clientBaseUrl: null }],
    ['no handle has been claimed yet', { handle: null }],
    ['the handle field is still empty', { handle: '' }],
  ])('resolves no URL when %s', (_, overrides) => {
    expect(buildUrl(overrides)).toBeNull();
  });
});

describe('buildRepositoryClientUrl', () => {
  const buildUrl = (overrides = {}) =>
    buildRepositoryClientUrl({
      clientBaseUrl: CLIENT_BASE_URL,
      slug: SLUG,
      format: 'MAVEN',
      name: 'my-repository',
      ...overrides,
    });

  // The segment names the protocol family, not the repository's own format, which is why
  // Docker and OCI share one: a single set of OCI Distribution Spec endpoints serves both.
  describe.each([
    ['MAVEN', 'maven'],
    ['NPM', 'npm'],
    ['DOCKER', 'container'],
    ['OCI', 'container'],
  ])('for a %s repository', (format, segment) => {
    it(`composes the URL over the ${segment} segment`, () => {
      expect(buildUrl({ format })).toBe(`${CLIENT_BASE_URL}/${SLUG}/${segment}/my-repository`);
    });
  });

  it.each([
    ['a space', 'my repository', 'my%20repository'],
    ['a query delimiter', 'my?repository', 'my%3Frepository'],
    ['a fragment delimiter', 'my#repository', 'my%23repository'],
  ])('percent-encodes %s in the repository name', (_, name, encoded) => {
    expect(buildUrl({ name })).toBe(`${CLIENT_BASE_URL}/${SLUG}/maven/${encoded}`);
  });

  it('joins the base URL cleanly when it carries a trailing slash', () => {
    expect(buildUrl({ clientBaseUrl: `${CLIENT_BASE_URL}/` })).toBe(
      `${CLIENT_BASE_URL}/${SLUG}/maven/my-repository`,
    );
  });

  // Each of these would compose a URL with a hole in it, so the caller gets nothing to
  // offer rather than something that would not resolve.
  it.each([
    ['the instance configures no Artifact Registry', { clientBaseUrl: null }],
    ['the namespace slug is missing', { slug: null }],
    ['the format has no client segment', { format: 'CONDA' }],
    ['the repository has no name', { name: null }],
  ])('resolves no URL when %s', (_, overrides) => {
    expect(buildUrl(overrides)).toBeNull();
  });
});
