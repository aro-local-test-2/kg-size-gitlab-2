import { omit } from 'lodash-es';
import {
  REPOSITORY_FORMAT_VALUES,
  TYPENAME_ARTIFACT_REGISTRY_IMAGE,
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE,
  TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE,
  TYPENAME_ARTIFACT_REGISTRY_VERSION_DETAILS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import {
  manifestLadderFor,
  mockArtifacts,
  versionLadderFor,
} from 'ee/packages_and_registries/artifact_registry/graphql/mock_artifacts';
import { artifactDisplayName } from 'ee/packages_and_registries/artifact_registry/utils';

// Two names Artifact Registry serves, one that names no format at all, and the two edges of
// the name contract: a single character, and one using every separator
// REPOSITORY_NAME_PATTERN admits.
const NAMES = ['oci-repository', 'maven-repository', 'payment-core', 'a', 'x_y.z-9'];

const [FIRST_NAME, SECOND_NAME] = NAMES;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const MIN_ARTIFACTS = 3;

const MAX_ARTIFACTS = 25;

const CONTAINER_FORMATS = ['DOCKER', 'OCI'];

const PACKAGE_FORMATS = ['MAVEN', 'NPM'];

const ARTIFACT_KEYS = {
  [TYPENAME_ARTIFACT_REGISTRY_IMAGE]: ['__typename', 'id', 'name'],
  [TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE]: ['__typename', 'artifactId', 'groupId', 'id'],
  [TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE]: ['__typename', 'id', 'name', 'scope'],
};

const VERSION_KEYS = [
  '__typename',
  'createdAt',
  'createdBy',
  'distTags',
  'gitCommitSha',
  'id',
  'project',
  'sizeBytes',
  'version',
];

const SHA_PATTERN = /^[0-9a-f]{40}$/;

const MIN_VERSIONS = 2;

const MAX_VERSIONS = 40;

const MAVEN_SNAPSHOT_SUFFIX = '-SNAPSHOT';

const PRERELEASE_SUFFIX = '-rc.1';

const SEMVER_PATTERN = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

// The list element and the detail are one resource in the contract, so a ladder row carries
// both sets even though only the manifest read selects off it today.
const MANIFEST_KEYS = [
  '__typename',
  'annotations',
  'architecture',
  'artifactType',
  'children',
  'childrenCount',
  'createdAt',
  'digest',
  'id',
  'mediaType',
  'os',
  'osVariant',
  'parentDigests',
  'parentsCount',
  // Not a contract field: the seeded rows the referrers resolver pages over.
  'referrerRows',
  'referrersCount',
  'size',
  'subjectDigest',
  'tags',
  'tagsCount',
];

const MIN_SUBJECT_MANIFESTS = 2;

const MAX_SUBJECT_MANIFESTS = 34;

const DIGEST_PATTERN = /^sha256:[0-9a-f]{64}$/;

const OCI_IMAGE_INDEX = 'application/vnd.oci.image.index.v1+json';

describe('Artifact registry mock artifacts', () => {
  const idsOf = (artifacts) => artifacts.map(({ id }) => id);

  const displayNamesOf = (artifacts, format) =>
    artifacts.map((artifact) => artifactDisplayName(artifact, format));

  const typenamesOf = (artifacts) => [...new Set(artifacts.map(({ __typename }) => __typename))];

  const laddersOf = (name, format) =>
    mockArtifacts(name, format).map(({ id }) => versionLadderFor(id, format));

  const versionIdsOf = (name, format) => laddersOf(name, format).flatMap(idsOf);

  const manifestLaddersOf = (artifacts) => artifacts.map(({ id }) => manifestLadderFor(id));

  const subjectsOf = (ladder) => ladder.filter(({ subjectDigest }) => !subjectDigest);

  const referrersOf = (ladder) => ladder.filter(({ subjectDigest }) => subjectDigest);

  const manifestsOf = (artifacts) => manifestLaddersOf(artifacts).flat();

  const newestFirst = (publishedAt) => [...publishedAt].sort((left, right) => right - left);

  const versionStringsOf = (ladder) => ladder.map(({ version }) => version);

  const publishedAtOf = (ladder) => ladder.map(({ createdAt }) => Date.parse(createdAt));

  describe('the page it generates', () => {
    it.each(NAMES)('generates a page for %s, whatever the name', (name) => {
      expect(mockArtifacts(name, 'MAVEN').length).toBeGreaterThanOrEqual(MIN_ARTIFACTS);
      expect(mockArtifacts(name, 'MAVEN').length).toBeLessThanOrEqual(MAX_ARTIFACTS);
    });

    it.each(NAMES)('generates as many artifacts for %s whatever the format', (name) => {
      const counts = REPOSITORY_FORMAT_VALUES.map((format) => mockArtifacts(name, format).length);

      expect(new Set(counts).size).toBe(1);
    });

    it('sizes the page from the name, so two names do not both read as one length', () => {
      const lengths = NAMES.map((name) => mockArtifacts(name, 'MAVEN').length);

      expect(new Set(lengths).size).toBeGreaterThan(1);
    });
  });

  // The single-artifact read resolves an id the connection handed out, so a generator minting
  // a fresh id per call would leave every artifact URL dead the moment the page navigated.
  describe('the artifact ids', () => {
    it.each(REPOSITORY_FORMAT_VALUES)('generates opaque UUIDs for a %s repository', (format) => {
      const ids = idsOf(mockArtifacts(FIRST_NAME, format));

      expect(ids).toHaveLength(new Set(ids).size);
      ids.forEach((id) => expect(id).toMatch(UUID_PATTERN));
    });

    it.each(NAMES)('generates the same ids on a second call for %s', (name) => {
      expect(idsOf(mockArtifacts(name, 'MAVEN'))).toEqual(idsOf(mockArtifacts(name, 'MAVEN')));
    });

    // An id the connection handed out stays the handle on the same artifact whichever shape a
    // read renders it as.
    it('generates ids that do not move with the format', () => {
      const [reference, ...rest] = REPOSITORY_FORMAT_VALUES.map((format) =>
        idsOf(mockArtifacts(FIRST_NAME, format)),
      );

      rest.forEach((ids) => expect(ids).toEqual(reference));
    });

    it('gives no two repositories an id in common', () => {
      const ids = idsOf(mockArtifacts(FIRST_NAME, 'MAVEN'));
      const otherIds = idsOf(mockArtifacts(SECOND_NAME, 'MAVEN'));

      expect(ids.filter((id) => otherIds.includes(id))).toEqual([]);
    });
  });

  describe('the artifact shape, which the format decides', () => {
    it.each(CONTAINER_FORMATS)('generates images for %s', (format) => {
      expect(typenamesOf(mockArtifacts(FIRST_NAME, format))).toEqual([
        TYPENAME_ARTIFACT_REGISTRY_IMAGE,
      ]);
    });

    it('generates Maven packages for MAVEN', () => {
      expect(typenamesOf(mockArtifacts(FIRST_NAME, 'MAVEN'))).toEqual([
        TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE,
      ]);
    });

    it('generates npm packages for NPM', () => {
      expect(typenamesOf(mockArtifacts(FIRST_NAME, 'NPM'))).toEqual([
        TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE,
      ]);
    });

    it.each(REPOSITORY_FORMAT_VALUES)('carries the whole %s shape and nothing else', (format) => {
      mockArtifacts(FIRST_NAME, format).forEach((artifact) => {
        const { __typename: typename } = artifact;

        expect(Object.keys(artifact).sort()).toEqual(ARTIFACT_KEYS[typename]);
      });
    });

    it('scopes some npm packages and leaves others unscoped', () => {
      const scopes = mockArtifacts(FIRST_NAME, 'NPM').map(({ scope }) => scope);

      expect(scopes).toContain(null);
      expect(scopes.filter(Boolean).every((scope) => scope.startsWith('@'))).toBe(true);
    });
  });

  describe('the version ladder every package carries', () => {
    it.each(PACKAGE_FORMATS)('ladders every %s package', (format) => {
      laddersOf(FIRST_NAME, format).forEach((ladder) => {
        expect(ladder.length).toBeGreaterThanOrEqual(MIN_VERSIONS);
        expect(ladder.length).toBeLessThanOrEqual(MAX_VERSIONS);
      });
    });

    it.each(PACKAGE_FORMATS)('sizes a %s ladder per package, not per repository', (format) => {
      const lengths = laddersOf(FIRST_NAME, format).map(({ length }) => length);

      expect(new Set(lengths).size).toBeGreaterThan(1);
    });

    it('gives two packages of one repository different versions', () => {
      const [first, second] = laddersOf(FIRST_NAME, 'MAVEN');

      expect(versionStringsOf(first)).not.toEqual(versionStringsOf(second));
    });

    it.each(PACKAGE_FORMATS)('carries the whole version shape on a %s package', (format) => {
      laddersOf(FIRST_NAME, format)
        .flat()
        .forEach((version) => {
          const { __typename: typename } = version;

          expect(Object.keys(version).sort()).toEqual(VERSION_KEYS);
          expect(typename).toBe(TYPENAME_ARTIFACT_REGISTRY_VERSION_DETAILS);
        });
    });

    describe('the stored size every version carries', () => {
      const sizesOf = (format) =>
        NAMES.flatMap((name) => laddersOf(name, format).flat()).map(({ sizeBytes }) => sizeBytes);

      it.each(PACKAGE_FORMATS)('states a %s size as a string of digits or null', (format) => {
        const stated = sizesOf(format).filter((sizeBytes) => sizeBytes !== null);

        expect(stated).not.toHaveLength(0);
        stated.forEach((sizeBytes) => expect(sizeBytes).toMatch(/^\d+$/));
      });

      it.each(PACKAGE_FORMATS)('leaves some %s versions unsized, for the hidden row', (format) => {
        expect(sizesOf(format)).toContain(null);
      });

      it.each(PACKAGE_FORMATS)('sizes some %s versions at zero, for the zero row', (format) => {
        expect(sizesOf(format)).toContain('0');
      });

      it('sizes most versions above zero, so the two edge cases stay edges', () => {
        const sized = sizesOf('MAVEN').filter((sizeBytes) => Number(sizeBytes) > 0);

        expect(sized.length).toBeGreaterThan(sizesOf('MAVEN').length / 2);
      });
    });

    it('marks the oldest release of a Maven ladder a snapshot, and only that one', () => {
      laddersOf(FIRST_NAME, 'MAVEN').forEach((ladder) => {
        const snapshots = ladder.filter(({ version }) => version.endsWith(MAVEN_SNAPSHOT_SUFFIX));

        expect(snapshots).toHaveLength(1);
        expect(ladder.indexOf(snapshots[0])).toBe(0);
      });
    });

    it('marks no npm version a snapshot, so the suffix stays a Maven projection', () => {
      const npmVersions = NAMES.flatMap((name) => laddersOf(name, 'NPM').flat()).map(
        ({ version }) => version,
      );

      expect(npmVersions).not.toHaveLength(0);
      expect(npmVersions.filter((version) => version.endsWith(MAVEN_SNAPSHOT_SUFFIX))).toEqual([]);
    });

    it.each(PACKAGE_FORMATS)('names every %s version once, as a semantic version', (format) => {
      laddersOf(FIRST_NAME, format).forEach((ladder) => {
        const versions = versionStringsOf(ladder);

        expect(versions).toHaveLength(new Set(versions).size);
        versions.forEach((version) => expect(version).toMatch(SEMVER_PATTERN));
      });
    });

    it('ladders a prerelease somewhere', () => {
      const versions = NAMES.flatMap((name) => laddersOf(name, 'MAVEN').flatMap(versionStringsOf));

      expect(versions.some((version) => version.endsWith(PRERELEASE_SUFFIX))).toBe(true);
    });

    it.each(PACKAGE_FORMATS)('publishes each %s version at a moment of its own', (format) => {
      laddersOf(FIRST_NAME, format).forEach((ladder) => {
        const publishedAt = publishedAtOf(ladder);

        expect(publishedAt).toHaveLength(new Set(publishedAt).size);
        publishedAt.forEach((moment) => {
          expect(moment).not.toBeNaN();
          expect(moment).toBeLessThanOrEqual(Date.now());
        });
      });
    });

    it.each(PACKAGE_FORMATS)(
      'mints an opaque UUID for every %s version, and each one once',
      (format) => {
        const ids = versionIdsOf(FIRST_NAME, format);

        expect(ids).toHaveLength(new Set(ids).size);
        ids.forEach((id) => expect(id).toMatch(UUID_PATTERN));
      },
    );

    // Both connections cursor on the id of the row they page over, so an id shared between an
    // artifact and a version would let one connection's cursor name a row in the other.
    it('gives no version an id an artifact answers under', () => {
      const artifacts = mockArtifacts(FIRST_NAME, 'NPM');
      const versionIds = new Set(versionIdsOf(FIRST_NAME, 'NPM'));

      expect(idsOf(artifacts).filter((id) => versionIds.has(id))).toEqual([]);
    });

    it('gives no two repositories a version id in common', () => {
      const versionIds = new Set(versionIdsOf(SECOND_NAME, 'NPM'));

      expect(versionIdsOf(FIRST_NAME, 'NPM').filter((id) => versionIds.has(id))).toEqual([]);
    });

    // Artifact Registry makes the commit, the project, and the publisher nullable independently, so
    // a ladder attributing every version the same way would leave most of the version sidebar's
    // branches unreachable in a browser.
    it('ladders every attribution shape the version sidebar degrades through', () => {
      const shapes = NAMES.flatMap((name) =>
        laddersOf(name, 'MAVEN')
          .flat()
          .map(({ gitCommitSha, project, createdBy }) =>
            [gitCommitSha, project, createdBy].map(Boolean).join(),
          ),
      );

      expect(new Set(shapes)).toEqual(
        new Set([
          'true,true,true',
          'false,false,true',
          'true,true,false',
          'true,false,true',
          'false,false,false',
        ]),
      );
    });

    it('names a distinct commit for every version published from one', () => {
      const shas = NAMES.flatMap((name) =>
        laddersOf(name, 'MAVEN')
          .flat()
          .map(({ gitCommitSha }) => gitCommitSha)
          .filter(Boolean),
      );

      expect(shas.length).toBeGreaterThan(0);
      expect(shas).toHaveLength(new Set(shas).size);
      shas.forEach((sha) => expect(sha).toMatch(SHA_PATTERN));
    });

    // An artifact keeps its id whichever shape a read renders it as, so the ladder under that id
    // has to keep its version ids, and its strings up to the Maven snapshot suffix.
    it('ladders an artifact the same under either package shape, but for its projections', () => {
      const shared = (ladders) =>
        ladders.map((ladder) =>
          ladder.map((version) => ({
            ...omit(version, ['distTags']),
            version: version.version.replace(MAVEN_SNAPSHOT_SUFFIX, ''),
          })),
        );

      expect(shared(laddersOf(FIRST_NAME, 'MAVEN'))).toEqual(shared(laddersOf(FIRST_NAME, 'NPM')));
    });

    it('carries no dist-tag on a Maven version', () => {
      const versions = laddersOf(FIRST_NAME, 'MAVEN').flat();

      expect(versions.map(({ distTags }) => distTags)).toEqual(versions.map(() => []));
    });

    it('binds latest to the newest npm release and next to the prerelease past it', () => {
      laddersOf(FIRST_NAME, 'NPM').forEach((ladder) => {
        const [prerelease, newest, ...older] = [...ladder].reverse();

        expect(prerelease.distTags).toEqual(['next']);
        expect(newest.distTags).toEqual(['latest']);
        expect(older.map(({ distTags }) => distTags)).toEqual(older.map(() => []));
      });
    });

    it('carries the same keys under either package shape', () => {
      const differing = (format) =>
        laddersOf(FIRST_NAME, format)
          .flat()
          .map((version) => Object.keys(version).sort());

      expect(differing('MAVEN')).toEqual(differing('NPM'));
    });
  });

  describe('the manifest ladder every image carries', () => {
    it.each(CONTAINER_FORMATS)('ladders every %s image', (format) => {
      manifestLaddersOf(mockArtifacts(FIRST_NAME, format)).forEach((ladder) => {
        expect(subjectsOf(ladder).length).toBeGreaterThanOrEqual(MIN_SUBJECT_MANIFESTS);
        expect(subjectsOf(ladder).length).toBeLessThanOrEqual(MAX_SUBJECT_MANIFESTS);
      });
    });

    // The Type column reads its label off these three fields, so a ladder holding only one kind
    // would leave a browser unable to tell whether the column distinguishes anything.
    it('ladders an index, a platform image, and a referrer of each kind on every image', () => {
      manifestLaddersOf(mockArtifacts(FIRST_NAME, 'DOCKER')).forEach((ladder) => {
        const subjects = subjectsOf(ladder);

        expect(subjects.filter(({ mediaType }) => mediaType === OCI_IMAGE_INDEX)).toHaveLength(1);
        expect(
          subjects.filter(({ mediaType }) => mediaType !== OCI_IMAGE_INDEX).length,
        ).toBeGreaterThan(0);
        expect(new Set(referrersOf(ladder).map(({ artifactType }) => artifactType)).size).toBe(
          referrersOf(ladder).length,
        );
      });
    });

    // A referrer whose subject is nowhere in the ladder would have the Type column render a
    // plausible label against a manifest a browser cannot open.
    it('points every referrer at a subject the same image carries', () => {
      NAMES.forEach((name) => {
        manifestLaddersOf(mockArtifacts(name, 'DOCKER')).forEach((ladder) => {
          const digests = ladder.map(({ digest }) => digest);
          const referrers = referrersOf(ladder);

          expect(referrers.length).toBeGreaterThan(0);
          referrers.forEach(({ subjectDigest }) => expect(digests).toContain(subjectDigest));
        });
      });
    });

    // `manifestType` reads a subject digest as the referrer discriminator, so a subject carrying
    // an artifact type would still read as a subject, and a referrer without one still reads as a
    // referrer.
    it('carries an artifact type on the referrers alone, and leaves one referrer without', () => {
      const ladder = manifestLaddersOf(mockArtifacts(FIRST_NAME, 'DOCKER'))[0];
      const artifactTypes = referrersOf(ladder).map(({ artifactType }) => artifactType);

      subjectsOf(ladder).forEach(({ artifactType }) => expect(artifactType).toBe(null));
      expect(artifactTypes.filter((type) => typeof type === 'string').length).toBeGreaterThan(0);
      expect(artifactTypes).toContain(null);
    });

    // A referrer attests to a manifest rather than holding layers, so it reads as the smaller of
    // the two in the Size column.
    it('sizes every referrer under every subject of its image', () => {
      const ladder = manifestLaddersOf(mockArtifacts(FIRST_NAME, 'DOCKER'))[0];
      const smallestSubject = Math.min(...subjectsOf(ladder).map(({ size }) => Number(size)));

      referrersOf(ladder).forEach(({ size }) => expect(Number(size)).toBeLessThan(smallestSubject));
    });

    it.each(CONTAINER_FORMATS)('sizes a %s ladder per image, not per repository', (format) => {
      const lengths = manifestLaddersOf(mockArtifacts(FIRST_NAME, format)).map(
        ({ length }) => length,
      );

      expect(new Set(lengths).size).toBeGreaterThan(1);
    });

    it.each(CONTAINER_FORMATS)('carries the whole manifest shape on a %s image', (format) => {
      manifestsOf(mockArtifacts(FIRST_NAME, format)).forEach((manifest) => {
        const { __typename: typename } = manifest;

        expect(Object.keys(manifest).sort()).toEqual(MANIFEST_KEYS);
        expect(typename).toBe(TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS);
      });
    });

    describe('the detail a manifest read selects off the same row', () => {
      const everyLadder = () =>
        CONTAINER_FORMATS.flatMap((format) =>
          NAMES.flatMap((name) => manifestLaddersOf(mockArtifacts(name, format))),
        );

      const indexOf = (ladder) => ladder.find(({ children }) => children.length > 0);

      it('advertises children on the index alone, and never zero of them', () => {
        everyLadder().forEach((ladder) => {
          const withChildren = ladder.filter(({ children }) => children.length > 0);

          expect(withChildren).toHaveLength(1);
          expect(withChildren[0].mediaType).toBe(OCI_IMAGE_INDEX);
        });
      });

      it('keeps every count in step with the array beside it', () => {
        everyLadder().forEach((ladder) => {
          ladder.forEach(
            ({ tags, tagsCount, children, childrenCount, parentDigests, parentsCount }) => {
              expect(tagsCount).toBe(tags.length);
              expect(childrenCount).toBe(children.length);
              expect(parentsCount).toBe(parentDigests.length);
            },
          );
        });
      });

      it('names only digests the same image carries as the index children', () => {
        everyLadder().forEach((ladder) => {
          const digests = ladder.map(({ digest }) => digest);

          indexOf(ladder).children.forEach(({ digest }) => expect(digests).toContain(digest));
        });
      });

      it('carries on each child the platform its index advertises for it', () => {
        everyLadder().forEach((ladder) => {
          const byDigest = new Map(ladder.map((manifest) => [manifest.digest, manifest]));

          indexOf(ladder).children.forEach(({ digest, architecture, os, osVariant }) => {
            expect(byDigest.get(digest)).toMatchObject({ architecture, os, osVariant });
          });
        });
      });

      it('points every child back at the index that indexes it, and nothing else back at all', () => {
        everyLadder().forEach((ladder) => {
          const index = indexOf(ladder);
          const childDigests = index.children.map(({ digest }) => digest);

          ladder.forEach(({ digest, parentDigests }) => {
            expect(parentDigests).toEqual(childDigests.includes(digest) ? [index.digest] : []);
          });
        });
      });

      it('counts the referrers each manifest is the subject of', () => {
        everyLadder().forEach((ladder) => {
          ladder.forEach(({ digest, referrersCount }) => {
            const naming = ladder.filter(({ subjectDigest }) => subjectDigest === digest);

            expect(referrersCount).toBe(naming.length);
          });
        });
      });

      it('carries the referrer rows the count reports, and no others', () => {
        everyLadder().forEach((ladder) => {
          ladder.forEach(({ digest, referrerRows, referrersCount }) => {
            expect(referrerRows).toHaveLength(referrersCount);
            expect(referrerRows.map((row) => row.subjectDigest)).toEqual(
              referrerRows.map(() => digest),
            );
          });
        });
      });

      it('orders the referrer rows by digest ascending, the order the route imposes', () => {
        everyLadder().forEach((ladder) => {
          ladder.forEach(({ referrerRows }) => {
            const digests = referrerRows.map((row) => row.digest);

            expect(digests).toEqual([...digests].sort());
          });
        });
      });

      it('shapes each referrer row as a list element, not as a detail', () => {
        const rows = everyLadder()
          .flat()
          .flatMap(({ referrerRows }) => referrerRows);

        expect(rows.length).toBeGreaterThan(0);
        rows.forEach(({ __typename: typename, ...row }) => {
          expect(Object.keys(row).sort()).toEqual([
            'artifactType',
            'createdAt',
            'digest',
            'id',
            'mediaType',
            'subjectDigest',
          ]);
          expect(typename).toBe('ArtifactRegistryManifest');
        });
      });

      it('tags the index alone, which is what a client resolves when it pulls by name', () => {
        everyLadder().forEach((ladder) => {
          // Outright, or a ladder that stopped tagging satisfies the comparison below with zero.
          expect(indexOf(ladder).tags.length).toBeGreaterThan(0);

          ladder.forEach(({ tags, children }) => {
            expect(tags.length > 0).toBe(children.length > 0);
          });
        });
      });

      it('serves the tags name ascending, the order Artifact Registry sorts them in', () => {
        everyLadder().forEach((ladder) => {
          ladder.forEach(({ tags }) => {
            expect(tags).toEqual([...tags].sort());
          });
        });
      });

      it('leaves the index and every referrer without a platform triple at all', () => {
        everyLadder().forEach((ladder) => {
          const bare = { architecture: null, os: null, osVariant: null };
          const { architecture, os, osVariant } = indexOf(ladder);

          expect({ architecture, os, osVariant }).toEqual(bare);
          ladder
            .filter(({ subjectDigest }) => subjectDigest)
            .forEach((referrer) => {
              expect({
                architecture: referrer.architecture,
                os: referrer.os,
                osVariant: referrer.osVariant,
              }).toEqual(bare);
            });
        });
      });

      it('reaches a platformed image and an unplatformed one', () => {
        const images = everyLadder().flatMap((ladder) =>
          ladder.filter(({ subjectDigest, children }) => !subjectDigest && children.length === 0),
        );

        expect(images.filter(({ architecture }) => architecture).length).toBeGreaterThan(0);
        expect(images.filter(({ architecture }) => !architecture).length).toBeGreaterThan(0);
      });

      it('never emits a variant with no architecture to qualify', () => {
        everyLadder().forEach((ladder) => {
          ladder.forEach(({ architecture, osVariant, children }) => {
            if (osVariant) expect(architecture).not.toBe(null);

            children.forEach((child) => {
              if (child.osVariant) expect(child.architecture).not.toBe(null);
            });
          });
        });
      });

      it('seeds a null annotations map and an empty one across the repositories', () => {
        const annotations = NAMES.flatMap((name) =>
          manifestsOf(mockArtifacts(name, 'OCI')).map((manifest) => manifest.annotations),
        );

        expect(annotations).toContain(null);
        expect(
          annotations.filter((entry) => Array.isArray(entry) && entry.length === 0).length,
        ).toBeGreaterThan(0);
        expect(
          annotations.filter((entry) => Array.isArray(entry) && entry.length > 0).length,
        ).toBeGreaterThan(0);
      });
    });

    // The table shortens a digest for display and hands the whole string to the clipboard, so a
    // digest that read as anything but one would copy as something a pull command rejects.
    it('digests every manifest once, at the full hex width the algorithm names', () => {
      const digests = NAMES.flatMap((name) => manifestsOf(mockArtifacts(name, 'DOCKER'))).map(
        ({ digest }) => digest,
      );

      expect(digests).toHaveLength(new Set(digests).size);
      digests.forEach((digest) => expect(digest).toMatch(DIGEST_PATTERN));
    });

    it('mints an opaque UUID for every manifest, and each one once', () => {
      const ids = NAMES.flatMap((name) => manifestsOf(mockArtifacts(name, 'DOCKER'))).map(
        ({ id }) => id,
      );

      expect(ids).toHaveLength(new Set(ids).size);
      ids.forEach((id) => expect(id).toMatch(UUID_PATTERN));
    });

    // The manifests connection cursors on the id of the row it pages over, so an id shared with
    // an artifact would let the cursor name a row in the other connection.
    it('gives no manifest an id an image answers under', () => {
      const artifacts = mockArtifacts(FIRST_NAME, 'DOCKER');
      const manifestIds = new Set(manifestsOf(artifacts).map(({ id }) => id));

      expect(idsOf(artifacts).filter((id) => manifestIds.has(id))).toEqual([]);
    });

    // The table renders this through `numberToHumanSize`, which reads a number: the schema
    // serializes the size as a String, so the generator has to hand one over.
    it('sizes every manifest as a positive integer string', () => {
      manifestsOf(mockArtifacts(FIRST_NAME, 'DOCKER')).forEach(({ size }) => {
        expect(typeof size).toBe('string');
        expect(Number(size)).toBeGreaterThan(0);
        expect(Number.isInteger(Number(size))).toBe(true);
      });
    });

    // The connection orders on the parsed timestamp, so two rows pushed at one moment would leave
    // their order down to the generation order.
    it.each(CONTAINER_FORMATS)('pushes each %s manifest at a moment of its own', (format) => {
      manifestLaddersOf(mockArtifacts(FIRST_NAME, format)).forEach((ladder) => {
        const publishedAt = publishedAtOf(ladder);

        expect(publishedAt).toHaveLength(new Set(publishedAt).size);
        publishedAt.forEach((moment) => {
          expect(moment).not.toBeNaN();
          expect(moment).toBeLessThanOrEqual(Date.now());
        });
      });
    });

    it('ladders out of pushed order, so the connection’s newest-first sort does work', () => {
      const reordered = NAMES.flatMap((name) =>
        manifestLaddersOf(mockArtifacts(name, 'DOCKER')),
      ).some((ladder) => {
        const publishedAt = publishedAtOf(ladder);

        return publishedAt.join() !== newestFirst(publishedAt).join();
      });

      expect(reordered).toBe(true);
    });

    // An artifact keeps its id whichever container shape a read renders it as, so the ladder under
    // that id has to keep its manifests too.
    it('ladders an artifact the same under either container format', () => {
      expect(manifestLaddersOf(mockArtifacts(FIRST_NAME, 'DOCKER'))).toEqual(
        manifestLaddersOf(mockArtifacts(FIRST_NAME, 'OCI')),
      );
    });
  });

  describe('the names a page reads under', () => {
    it.each(REPOSITORY_FORMAT_VALUES)('names every %s artifact, and each one once', (format) => {
      const names = displayNamesOf(mockArtifacts(FIRST_NAME, format), format);

      expect(names).toHaveLength(new Set(names).size);
      names.forEach((name) => expect(name).not.toBe(''));
    });

    it.each(REPOSITORY_FORMAT_VALUES)('names two %s repositories apart', (format) => {
      const names = displayNamesOf(mockArtifacts(FIRST_NAME, format), format);
      const otherNames = displayNamesOf(mockArtifacts(SECOND_NAME, format), format);

      expect(names.filter((name) => otherNames.includes(name))).toEqual([]);
    });
  });

  // Every read calls this again, so a page that differed between two calls would leave the id one
  // read handed out unresolvable by the next, and would move the rows under a reload.
  it.each(NAMES)('generates the identical page on a second call for %s', (name) => {
    REPOSITORY_FORMAT_VALUES.forEach((format) => {
      expect(mockArtifacts(name, format)).toEqual(mockArtifacts(name, format));
    });
  });

  // The resolvers hand these objects straight over, so a generator holding onto them would let
  // one read edit what the next one answers.
  it('hands out artifacts a caller cannot write back through', () => {
    const [artifact] = mockArtifacts(FIRST_NAME, 'NPM');
    const { name } = artifact;
    artifact.name = 'Edited by the caller';

    expect(mockArtifacts(FIRST_NAME, 'NPM')[0].name).toBe(name);
  });

  it('hands out versions a caller cannot write back through', () => {
    const [{ id }] = mockArtifacts(FIRST_NAME, 'NPM');
    const ladder = versionLadderFor(id, 'NPM');
    const { version } = ladder[0];
    ladder[0].version = '9.9.9-edited-by-the-caller';

    expect(versionLadderFor(id, 'NPM')[0].version).toBe(version);
  });
});
