import { pullSnippetSections } from 'ee/packages_and_registries/artifact_registry/repositories/versions/pull_snippets';
import {
  mockManifests,
  mockNpmPackagePage,
  mockRepositoryArtifacts,
  mockVersions,
} from '../../mock_data';

const VERSION = mockVersions[0].version;
const DIGEST = mockManifests[0].digest;
const REPOSITORY_URL = 'https://artifact-registry.example.com/acme/container/my-repository';
const MAVEN_PACKAGE = mockRepositoryArtifacts('MAVEN').package;
const SCOPED_NPM_PACKAGE = mockRepositoryArtifacts('NPM').package;
const [, UNSCOPED_NPM_PACKAGE] = mockNpmPackagePage.nodes;
const DOCKER_IMAGE = mockRepositoryArtifacts('DOCKER').image;

const codeOf = (sections) =>
  sections.flatMap(({ blocks }) => blocks.map(({ code }) => code).filter(Boolean));

describe('pullSnippetSections', () => {
  describe('a Maven version', () => {
    const build = () =>
      pullSnippetSections({ format: 'MAVEN', artifact: MAVEN_PACKAGE, version: VERSION });

    it('installs the coordinates of this artifact at this version', () => {
      expect(codeOf(build())).toEqual([
        `mvn dependency:get \\
  -DgroupId='com.company.payment' \\
  -DartifactId='core' \\
  -Dversion='3.2.1'`,
      ]);
    });

    it('offers the version-pinned command alone, not the tag-keyed one', () => {
      const sections = build();

      expect(sections).toHaveLength(1);
      expect(sections[0].heading).toBe('Install by version');
    });
  });

  describe('an npm version', () => {
    it('installs the scope-qualified name at this version', () => {
      const sections = pullSnippetSections({
        format: 'NPM',
        artifact: SCOPED_NPM_PACKAGE,
        version: VERSION,
      });

      expect(codeOf(sections)).toEqual(["npm install '@company/design-system@3.2.1'"]);
    });

    it('leads with the tag-keyed install when the version carries a dist-tag', () => {
      const sections = pullSnippetSections({
        format: 'NPM',
        artifact: SCOPED_NPM_PACKAGE,
        version: VERSION,
        tag: 'latest',
      });

      expect(sections.map(({ heading }) => heading)).toEqual([
        'Install by tag',
        'Install by version',
      ]);
      expect(codeOf(sections)).toEqual([
        "npm install '@company/design-system@latest'",
        "npm install '@company/design-system@3.2.1'",
      ]);
    });

    it('installs a bare name for a package carrying no scope', () => {
      const sections = pullSnippetSections({
        format: 'NPM',
        artifact: UNSCOPED_NPM_PACKAGE,
        version: VERSION,
      });

      expect(codeOf(sections)).toEqual(["npm install 'design-tokens@3.2.1'"]);
    });
  });

  describe.each(['DOCKER', 'OCI'])('a %s manifest', (format) => {
    const build = () =>
      pullSnippetSections({
        format,
        artifact: DOCKER_IMAGE,
        digest: DIGEST,
        repositoryUrl: REPOSITORY_URL,
      });

    it('pulls the image by digest through the repository address, with its scheme dropped', () => {
      expect(codeOf(build())).toEqual([
        `docker pull 'artifact-registry.example.com/acme/container/my-repository/payment-service@${DIGEST}'`,
      ]);
    });

    it('offers the digest-pinned command alone, not the tag-keyed one', () => {
      const sections = build();

      expect(sections).toHaveLength(1);
      expect(sections[0].heading).toBe('Pull by digest');
      expect(sections[0].blocks[0].copyText).toBe('Copy the pull command');
    });
  });

  // Artifact Registry types a Maven groupId and an npm name as bare strings, so nothing upstream
  // keeps a shell metacharacter out of one, and the snippet exists to be pasted into a shell.
  describe('a coordinate carrying shell metacharacters', () => {
    it('quotes every value it splices into the Maven command', () => {
      const sections = pullSnippetSections({
        format: 'MAVEN',
        artifact: { ...MAVEN_PACKAGE, groupId: 'com.evil; rm -rf ~', artifactId: '$(whoami)' },
        version: '1.0.0 && curl example.test',
      });

      expect(codeOf(sections)).toEqual([
        `mvn dependency:get \\
  -DgroupId='com.evil; rm -rf ~' \\
  -DartifactId='$(whoami)' \\
  -Dversion='1.0.0 && curl example.test'`,
      ]);
    });

    it('quotes the npm coordinate, closing and reopening the literal around a quote', () => {
      const sections = pullSnippetSections({
        format: 'NPM',
        artifact: { ...SCOPED_NPM_PACKAGE, scope: null, name: "it's-fine" },
        version: '1.0.0',
      });

      expect(codeOf(sections)).toEqual([`npm install 'it'\\''s-fine@1.0.0'`]);
    });

    it('quotes the tag-keyed npm coordinate the same way', () => {
      const sections = pullSnippetSections({
        format: 'NPM',
        artifact: SCOPED_NPM_PACKAGE,
        version: '1.0.0',
        tag: 'next; rm -rf ~',
      });

      expect(codeOf(sections)[0]).toBe(`npm install '@company/design-system@next; rm -rf ~'`);
    });

    it('quotes the image reference, so a metacharacter in the image name stays a name', () => {
      const sections = pullSnippetSections({
        format: 'DOCKER',
        artifact: { ...DOCKER_IMAGE, name: 'payment-service; rm -rf ~' },
        digest: DIGEST,
        repositoryUrl: REPOSITORY_URL,
      });

      expect(codeOf(sections)).toEqual([
        `docker pull 'artifact-registry.example.com/acme/container/my-repository/payment-service; rm -rf ~@${DIGEST}'`,
      ]);
    });
  });

  describe('credentials', () => {
    it.each`
      format      | artifact
      ${'MAVEN'}  | ${MAVEN_PACKAGE}
      ${'NPM'}    | ${SCOPED_NPM_PACKAGE}
      ${'DOCKER'} | ${DOCKER_IMAGE}
    `('carries no credential in the $format command', ({ format, artifact }) => {
      const body = codeOf(
        pullSnippetSections({
          format,
          artifact,
          version: VERSION,
          digest: DIGEST,
          repositoryUrl: REPOSITORY_URL,
        }),
      ).join('\n');

      expect(body).not.toMatch(/glpat-|--password|-p\s+\S|Bearer\s|token/i);
    });
  });

  it('ignores a tag on a Maven version, which has no dist-tags', () => {
    const sections = pullSnippetSections({
      format: 'MAVEN',
      artifact: MAVEN_PACKAGE,
      version: VERSION,
      tag: 'latest',
    });

    expect(sections.map(({ heading }) => heading)).toEqual(['Install by version']);
  });

  describe('when the command cannot be composed', () => {
    it.each`
      case                              | format      | artifact         | version    | digest    | repositoryUrl
      ${'an unknown format'}            | ${'CONAN'}  | ${MAVEN_PACKAGE} | ${VERSION} | ${''}     | ${null}
      ${'no artifact'}                  | ${'MAVEN'}  | ${null}          | ${VERSION} | ${''}     | ${null}
      ${'no version'}                   | ${'MAVEN'}  | ${MAVEN_PACKAGE} | ${''}      | ${''}     | ${null}
      ${'no image'}                     | ${'DOCKER'} | ${null}          | ${''}      | ${DIGEST} | ${REPOSITORY_URL}
      ${'no digest'}                    | ${'DOCKER'} | ${DOCKER_IMAGE}  | ${''}      | ${''}     | ${REPOSITORY_URL}
      ${'no repository URL to pull by'} | ${'OCI'}    | ${DOCKER_IMAGE}  | ${''}      | ${DIGEST} | ${null}
    `('yields no sections for $case', ({ format, artifact, version, digest, repositoryUrl }) => {
      expect(pullSnippetSections({ format, artifact, version, digest, repositoryUrl })).toEqual([]);
    });
  });
});
