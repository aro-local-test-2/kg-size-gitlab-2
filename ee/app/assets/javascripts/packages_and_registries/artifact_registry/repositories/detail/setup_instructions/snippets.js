import { escape } from 'lodash-es';
import { DOCS_URL } from '~/constants';
import { s__ } from '~/locale';
import { withoutScheme } from '../../../utils';
import {
  REPOSITORY_FORMAT_DOCKER,
  REPOSITORY_FORMAT_MAVEN,
  REPOSITORY_FORMAT_NPM,
  REPOSITORY_FORMAT_OCI,
  SETUP_SECTION_INSTALL,
  SETUP_TOOL_GRADLE_GROOVY,
  SETUP_TOOL_GRADLE_KOTLIN,
  SETUP_TOOL_PNPM,
  SETUP_TOOL_PODMAN,
  SETUP_TOOL_SBT,
  SETUP_TOOL_YARN,
} from '../../../constants';

const PLACEHOLDER_GROUP_ID = 'com.company';
const PLACEHOLDER_ARTIFACT_ID = 'app';
const PLACEHOLDER_VERSION = '1.0.0';
const PLACEHOLDER_SCOPE = 'scope';
const PLACEHOLDER_PACKAGE = '@scope/package';
const PLACEHOLDER_IMAGE_NAME = 'image';
const PLACEHOLDER_TAG = 'tag';

const YARN_BERRY_PUBLISH_VIA_NPM_PLUGIN = 'yarn npm publish';

const GLAB_LOGIN_DOCS_URL = `${DOCS_URL}/cli/artifact-registry/login/`;
const AUTHENTICATE_DOCS_URL = `${DOCS_URL}/artifact-registry/authenticate/`;

// ASCII alphanumerics plus the seven characters Maven, npm, semver, and OCI coordinates use. A
// Maven version range also needs '[](),', but a range is a constraint, not a published version.
const SAFE_COORDINATE = /^[A-Za-z0-9._~@/+-]+$/;

// Separate from SAFE_COORDINATE: adding a colon there would widen every coordinate's guard.
const CANONICAL_DIGEST = /^sha256:[a-f0-9]{64}$/;

const i18n = {
  repositorySetup: s__('ArtifactRegistry|Repository setup'),
  registrySetup: s__('ArtifactRegistry|Registry setup'),
  copyDependency: s__('ArtifactRegistry|Copy the dependency declaration'),
  copyInstallCommand: s__('ArtifactRegistry|Copy the install command'),
  copyPublishCommand: s__('ArtifactRegistry|Copy the publish command'),
  copyDistribution: s__('ArtifactRegistry|Copy the distribution management configuration'),
  copyRepositoryConfig: s__('ArtifactRegistry|Copy the repository configuration'),
  copyRegistryConfig: s__('ArtifactRegistry|Copy the registry configuration'),
  copyPullCommand: s__('ArtifactRegistry|Copy the pull command'),
  copyPullByTagCommand: s__('ArtifactRegistry|Copy the pull-by-tag command'),
  copyPullByDigestCommand: s__('ArtifactRegistry|Copy the pull-by-digest command'),
  copyPushCommand: s__('ArtifactRegistry|Copy the push command'),
  copyGlabCommand: s__('ArtifactRegistry|Copy the glab login command'),
  copyRegistryPointer: s__('ArtifactRegistry|Copy the registry line'),
  installCommand: s__('ArtifactRegistry|Install command:'),
  publishCommand: s__('ArtifactRegistry|Publish command:'),
  mavenDependency: s__(
    'ArtifactRegistry|Copy and paste this inside your %{codeStart}pom.xml%{codeEnd} %{codeStart}dependencies%{codeEnd} block:',
  ),
  mavenDistribution: s__('ArtifactRegistry|Add this to your %{codeStart}pom.xml%{codeEnd} file:'),
  mavenRepository: s__(
    "ArtifactRegistry|If you haven't already, add the configuration below to your %{codeStart}pom.xml%{codeEnd} file:",
  ),
  gradleGroovyDependency: s__(
    'ArtifactRegistry|Add the dependency to your %{codeStart}build.gradle%{codeEnd} file:',
  ),
  gradleGroovyRepository: s__(
    'ArtifactRegistry|Add the repository to your %{codeStart}build.gradle%{codeEnd} file, using the values glab wrote to %{codeStart}gradle.properties%{codeEnd}:',
  ),
  gradleKotlinRepository: s__(
    'ArtifactRegistry|Add the repository to your %{codeStart}build.gradle.kts%{codeEnd} file, using the values glab wrote to %{codeStart}gradle.properties%{codeEnd}:',
  ),
  gradleKotlinDependency: s__(
    'ArtifactRegistry|Add the dependency to your %{codeStart}build.gradle.kts%{codeEnd} file:',
  ),
  sbtDependency: s__(
    'ArtifactRegistry|Add the dependency to your %{codeStart}build.sbt%{codeEnd} file:',
  ),
  sbtRepository: s__('ArtifactRegistry|Add this to your %{codeStart}build.sbt%{codeEnd} file:'),
  npmrcRegistry: s__(
    'ArtifactRegistry|Add the registry to your %{codeStart}.npmrc%{codeEnd} file:',
  ),
  yarnrc: s__('ArtifactRegistry|Add this to your %{codeStart}.yarnrc.yml%{codeEnd} file:'),
  pullImage: s__('ArtifactRegistry|Pull an image:'),
  pullByTag: s__('ArtifactRegistry|Pull by tag'),
  pullByDigest: s__('ArtifactRegistry|Pull by digest'),
  pushImage: s__('ArtifactRegistry|Push an image:'),
  glabLogin: s__(
    'ArtifactRegistry|Run the following command with %{linkStart}glab%{linkEnd} 1.115 or later:',
  ),
  yarnAuthentication: s__(
    'ArtifactRegistry|glab cannot configure Yarn yet. See %{linkStart}how to authenticate%{linkEnd}:',
  ),
};

const hostOf = (url) => new URL(url).host;

/* eslint-disable @gitlab/require-i18n-strings -- Snippet bodies are code, not interface copy. */

// The '.' is load-bearing: a slug cannot contain one, so no two repositories share an alias.
const aliasPart = (value) =>
  String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-');

export const glabRegistryAlias = ({ slug, name }) => `ar-${aliasPart(slug)}.${aliasPart(name)}`;

const glabLoginBlock = ({ flag, registry, alias }) => ({
  text: i18n.glabLogin,
  link: GLAB_LOGIN_DOCS_URL,
  code: [
    'glab artifact-registry login',
    `--${flag}`,
    `--registry ${registry}`,
    ...(alias ? [`--registry-alias ${alias}`] : []),
  ].join(' \\\n  '),
  copyText: i18n.copyGlabCommand,
});

const gradleSections = ({
  tool,
  section,
  slug,
  name,
  repositoryUrl,
  groupId = PLACEHOLDER_GROUP_ID,
  artifactId = PLACEHOLDER_ARTIFACT_ID,
  version = PLACEHOLDER_VERSION,
}) => {
  const kotlin = tool === SETUP_TOOL_GRADLE_KOTLIN;
  const coordinates = `${groupId}:${artifactId}:${version}`;
  const alias = glabRegistryAlias({ slug, name });

  return [
    {
      blocks: [
        section === SETUP_SECTION_INSTALL
          ? {
              text: kotlin ? i18n.gradleKotlinDependency : i18n.gradleGroovyDependency,
              code: kotlin ? `implementation("${coordinates}")` : `implementation '${coordinates}'`,
              copyText: i18n.copyDependency,
            }
          : {
              text: i18n.publishCommand,
              code: 'gradle publish',
              copyText: i18n.copyPublishCommand,
            },
      ],
    },
    {
      heading: i18n.repositorySetup,
      blocks: [
        glabLoginBlock({ flag: 'gradle', registry: repositoryUrl, alias }),
        {
          text: kotlin ? i18n.gradleKotlinRepository : i18n.gradleGroovyRepository,
          code: kotlin
            ? `maven {
  url = uri(providers.gradleProperty("${alias}Url").get())
  credentials {
    username = providers.gradleProperty("${alias}Username").get()
    password = providers.gradleProperty("${alias}Password").get()
  }
}`
            : `maven {
  url providers.gradleProperty('${alias}Url').get()
  credentials {
    username = providers.gradleProperty('${alias}Username').get()
    password = providers.gradleProperty('${alias}Password').get()
  }
}`,
          copyText: i18n.copyRepositoryConfig,
        },
      ],
    },
  ];
};

const mavenSections = ({
  tool,
  section,
  slug,
  name,
  repositoryUrl,
  groupId = PLACEHOLDER_GROUP_ID,
  artifactId = PLACEHOLDER_ARTIFACT_ID,
  version = PLACEHOLDER_VERSION,
}) => {
  if (tool === SETUP_TOOL_GRADLE_GROOVY || tool === SETUP_TOOL_GRADLE_KOTLIN) {
    return gradleSections({
      tool,
      section,
      slug,
      name,
      repositoryUrl,
      groupId,
      artifactId,
      version,
    });
  }

  if (tool === SETUP_TOOL_SBT) {
    return [
      {
        blocks: [
          section === SETUP_SECTION_INSTALL
            ? {
                text: i18n.sbtDependency,
                code: `libraryDependencies += "${groupId}" % "${artifactId}" % "${version}"`,
                copyText: i18n.copyDependency,
              }
            : { text: i18n.publishCommand, code: 'sbt publish', copyText: i18n.copyPublishCommand },
        ],
      },
      {
        heading: i18n.repositorySetup,
        blocks: [
          glabLoginBlock({ flag: 'sbt', registry: repositoryUrl }),
          {
            text: i18n.sbtRepository,
            code:
              section === SETUP_SECTION_INSTALL
                ? `resolvers += ("artifact-registry" at "${repositoryUrl}")`
                : `publishTo := Some("artifact-registry" at "${repositoryUrl}")`,
            copyText: i18n.copyRepositoryConfig,
          },
        ],
      },
    ];
  }

  // The reader pastes these blocks into their own pom.xml and settings.xml, so a
  // repository name carrying an XML metacharacter would inject elements into a build
  // file rather than break a page. Artifact Registry restricts the name charset today
  // (REPOSITORY_NAME_PATTERN), which this does not take on trust.
  const xmlAlias = escape(glabRegistryAlias({ slug, name }));
  const xmlUrl = escape(repositoryUrl);

  return [
    {
      blocks:
        section === SETUP_SECTION_INSTALL
          ? [
              {
                text: i18n.mavenDependency,
                // groupId, artifactId, and version already passed SAFE_COORDINATE, so these
                // escapes are unreachable; kept so all five interpolations escape the same way.
                code: `<dependency>
  <groupId>${escape(groupId)}</groupId>
  <artifactId>${escape(artifactId)}</artifactId>
  <version>${escape(version)}</version>
</dependency>`,
                copyText: i18n.copyDependency,
              },
              {
                text: i18n.installCommand,
                code: 'mvn install',
                copyText: i18n.copyInstallCommand,
              },
            ]
          : [
              {
                text: i18n.mavenDistribution,
                code: `<distributionManagement>
  <repository>
    <id>${xmlAlias}</id>
    <url>${xmlUrl}</url>
  </repository>
</distributionManagement>`,
                copyText: i18n.copyDistribution,
              },
              {
                text: i18n.publishCommand,
                code: 'mvn deploy',
                copyText: i18n.copyPublishCommand,
              },
            ],
    },
    {
      heading: i18n.repositorySetup,
      blocks: [
        glabLoginBlock({ flag: 'maven', registry: repositoryUrl, alias: xmlAlias }),
        {
          text: i18n.mavenRepository,
          code: `<repositories>
  <repository>
    <id>${xmlAlias}</id>
    <url>${xmlUrl}</url>
  </repository>
</repositories>`,
          copyText: i18n.copyRepositoryConfig,
        },
      ],
    },
  ];
};

const npmSections = ({
  tool,
  section,
  repositoryUrl,
  packageName = PLACEHOLDER_PACKAGE,
  version,
}) => {
  const client = { [SETUP_TOOL_YARN]: 'yarn', [SETUP_TOOL_PNPM]: 'pnpm' }[tool] ?? 'npm';
  const addCommand = client === 'npm' ? 'install' : 'add';
  // `version` takes no placeholder default: the setup drawer passes none, and pinning one there
  // would change the merged snippet it already renders.
  const installTarget = version ? `${packageName}@${version}` : packageName;
  const publishCommand =
    client === 'yarn' ? YARN_BERRY_PUBLISH_VIA_NPM_PLUGIN : `${client} publish`;

  return [
    {
      blocks: [
        section === SETUP_SECTION_INSTALL
          ? {
              text: i18n.installCommand,
              code: `${client} ${addCommand} ${installTarget}`,
              copyText: i18n.copyInstallCommand,
            }
          : {
              text: i18n.publishCommand,
              code: publishCommand,
              copyText: i18n.copyPublishCommand,
            },
      ],
    },
    {
      heading: i18n.registrySetup,
      blocks:
        tool === SETUP_TOOL_YARN
          ? [
              { text: i18n.yarnAuthentication, link: AUTHENTICATE_DOCS_URL },
              {
                text: i18n.yarnrc,
                code: `npmScopes:
  ${PLACEHOLDER_SCOPE}:
    npmRegistryServer: "${repositoryUrl}"`,
                copyText: i18n.copyRegistryConfig,
              },
            ]
          : [
              glabLoginBlock({ flag: 'npm', registry: repositoryUrl }),
              {
                text: i18n.npmrcRegistry,
                code: `@${PLACEHOLDER_SCOPE}:registry=${repositoryUrl}`,
                copyText: i18n.copyRegistryPointer,
              },
            ],
    },
  ];
};

const containerSections = ({
  tool,
  section,
  format,
  repositoryUrl,
  imageName = PLACEHOLDER_IMAGE_NAME,
  tag,
  digest,
}) => {
  const client = tool === SETUP_TOOL_PODMAN ? 'podman' : 'docker';
  const image = `${withoutScheme(repositoryUrl)}/${imageName}`;

  const registrySetup = {
    heading: i18n.registrySetup,
    blocks: [glabLoginBlock({ flag: 'docker', registry: hostOf(repositoryUrl) })],
  };

  // Install only: a push addresses a tag, never a digest.
  if (digest && section === SETUP_SECTION_INSTALL) {
    // Scoped to this arm on purpose: hoisting it onto `client` would reach the setup drawer,
    // which addresses a tag, and switch every OCI repository there to oras.
    const digestClient = format === REPOSITORY_FORMAT_OCI ? 'oras' : client;

    return [
      {
        blocks: [
          ...(tag
            ? [
                {
                  text: i18n.pullByTag,
                  code: `${digestClient} pull ${image}:${tag}`,
                  copyText: i18n.copyPullByTagCommand,
                },
              ]
            : []),
          {
            text: i18n.pullByDigest,
            code: `${digestClient} pull ${image}@${digest}`,
            copyText: i18n.copyPullByDigestCommand,
          },
        ],
      },
      registrySetup,
    ];
  }

  // Defaulting `tag` in the destructure instead would make an untagged manifest pull `image:tag`.
  const reference = `${image}:${tag ?? PLACEHOLDER_TAG}`;

  return [
    {
      blocks: [
        section === SETUP_SECTION_INSTALL
          ? {
              text: i18n.pullImage,
              code: `${client} pull ${reference}`,
              copyText: i18n.copyPullCommand,
            }
          : {
              text: i18n.pushImage,
              code: `${client} push ${reference}`,
              copyText: i18n.copyPushCommand,
            },
      ],
    },
    registrySetup,
  ];
};

/* eslint-enable @gitlab/require-i18n-strings */

const SECTION_BUILDERS = {
  [REPOSITORY_FORMAT_DOCKER]: containerSections,
  [REPOSITORY_FORMAT_OCI]: containerSections,
  [REPOSITORY_FORMAT_MAVEN]: mavenSections,
  [REPOSITORY_FORMAT_NPM]: npmSections,
};

export const setupSnippetSections = ({
  format,
  tool,
  section,
  slug,
  name,
  repositoryUrl,
  groupId,
  artifactId,
  packageName,
  version,
  imageName,
  tag,
  digest,
}) => {
  const build = SECTION_BUILDERS[format];

  if (!build || !repositoryUrl || !name) return [];

  // Absent, not refused: an untagged manifest arrives as `tag: null`, and refusing it would
  // empty the whole panel. The identity coordinates below are deliberately not treated this way.
  const givenTag = tag || undefined;
  const givenDigest = digest || undefined;

  // Only undefined reaches a builder's placeholder default, and GraphQL sends null for an unset
  // field, so a non-string has to be refused rather than coerced into the charset test.
  const isSafe = (coordinate) =>
    coordinate === undefined ||
    (typeof coordinate === 'string' && SAFE_COORDINATE.test(coordinate));

  const isSafeDigest = (value) =>
    value === undefined || (typeof value === 'string' && CANONICAL_DIGEST.test(value));

  if (![groupId, artifactId, packageName, version, imageName, givenTag].every(isSafe)) return [];
  if (!isSafeDigest(givenDigest)) return [];

  return build({
    tool,
    section,
    format,
    slug,
    name,
    repositoryUrl,
    groupId,
    artifactId,
    packageName,
    version,
    imageName,
    tag: givenTag,
    digest: givenDigest,
  });
};

export const installSnippetBlock = (args) =>
  setupSnippetSections({ ...args, section: SETUP_SECTION_INSTALL })[0]?.blocks?.[0] ?? null;
