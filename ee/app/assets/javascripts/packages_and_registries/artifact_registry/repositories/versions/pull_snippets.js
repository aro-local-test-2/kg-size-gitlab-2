import { s__ } from '~/locale';
import { REPOSITORY_FORMAT_MAVEN, REPOSITORY_FORMAT_NPM } from '../../constants';
import { artifactDisplayName, isContainerFormat, withoutScheme } from '../../utils';

export const PULL_SECTION_TAG = 'tag';

const i18n = {
  installByTag: s__('ArtifactRegistry|Install by tag'),
  installByVersion: s__('ArtifactRegistry|Install by version'),
  pullByDigest: s__('ArtifactRegistry|Pull by digest'),
  copyInstallCommand: s__('ArtifactRegistry|Copy the install command'),
  copyPullCommand: s__('ArtifactRegistry|Copy the pull command'),
};

/* eslint-disable @gitlab/require-i18n-strings -- Snippet bodies are code, not interface copy. */

// Every value spliced into a snippet is Artifact Registry metadata, and the snippet exists for a
// viewer to paste into a shell, so an unquoted value carrying a metacharacter would run as one.
// Single quotes suppress every expansion a shell performs; an embedded quote has to close the
// literal, escape itself, and reopen it.
const shellQuoted = (value) => `'${String(value).replaceAll("'", "'\\''")}'`;

// No repository URL and no credential: the client reads one from the configuration the
// repository's setup instructions hand over, which is where the design keeps it.
const mavenSections = ({ artifact, version }) => [
  {
    heading: i18n.installByVersion,
    blocks: [
      {
        code: `mvn dependency:get \\
  -DgroupId=${shellQuoted(artifact.groupId)} \\
  -DartifactId=${shellQuoted(artifact.artifactId)} \\
  -Dversion=${shellQuoted(version)}`,
        copyText: i18n.copyInstallCommand,
      },
    ],
  },
];

const npmInstallBlock = (artifact, reference) => ({
  code: `npm install ${shellQuoted(
    `${artifactDisplayName(artifact, REPOSITORY_FORMAT_NPM)}@${reference}`,
  )}`,
  copyText: i18n.copyInstallCommand,
});

const npmSections = ({ artifact, version, tag }) => [
  ...(tag
    ? [
        {
          key: PULL_SECTION_TAG,
          heading: i18n.installByTag,
          blocks: [npmInstallBlock(artifact, tag)],
        },
      ]
    : []),
  {
    heading: i18n.installByVersion,
    blocks: [npmInstallBlock(artifact, version)],
  },
];

const containerSections = ({ artifact, digest, repositoryUrl }) => [
  {
    heading: i18n.pullByDigest,
    blocks: [
      {
        code: `docker pull ${shellQuoted(
          `${withoutScheme(repositoryUrl)}/${artifact.name}@${digest}`,
        )}`,
        copyText: i18n.copyPullCommand,
      },
    ],
  },
];

/* eslint-enable @gitlab/require-i18n-strings */

const PACKAGE_SECTION_BUILDERS = {
  [REPOSITORY_FORMAT_MAVEN]: mavenSections,
  [REPOSITORY_FORMAT_NPM]: npmSections,
};

// This drawer's builder only. The setup instructions build container commands of their own in
// `detail/setup_instructions/snippets.js`; the two surfaces are separate on purpose.
export const pullSnippetSections = ({ format, artifact, version, tag, digest, repositoryUrl }) => {
  if (!artifact) return [];

  if (isContainerFormat(format)) {
    return digest && repositoryUrl ? containerSections({ artifact, digest, repositoryUrl }) : [];
  }

  const build = PACKAGE_SECTION_BUILDERS[format];

  if (!build || !version) return [];

  return build({ artifact, version, tag });
};
