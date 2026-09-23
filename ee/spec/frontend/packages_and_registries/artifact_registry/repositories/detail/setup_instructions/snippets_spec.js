import {
  REPOSITORY_FORMAT_VALUES,
  SETUP_SECTION_INSTALL,
  SETUP_SECTION_PUBLISH,
  SETUP_TOOLS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import {
  installSnippetBlock,
  setupSnippetSections,
} from 'ee/packages_and_registries/artifact_registry/repositories/detail/setup_instructions/snippets';
import { buildRepositoryClientUrl } from 'ee/packages_and_registries/artifact_registry/utils';
import { CLIENT_BASE_URL, SLUG } from '../../../mock_data';

const NAME = 'my-repository';
const ALIAS = 'ar-acme.my-repository';
const SECTIONS = [SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH];
const DIGEST = `sha256:${'a1b2c3d4'.repeat(8)}`;

const urlFor = (format) =>
  buildRepositoryClientUrl({ clientBaseUrl: CLIENT_BASE_URL, slug: SLUG, format, name: NAME });

const build = ({ format, tool, section }) =>
  setupSnippetSections({
    format,
    tool,
    section,
    slug: SLUG,
    name: NAME,
    repositoryUrl: urlFor(format),
  });

const codeOf = (sections) =>
  sections.flatMap(({ blocks }) => blocks.map(({ code }) => code).filter(Boolean));

// Every format, tool, and section the selector can put on screen.
const everyCombination = REPOSITORY_FORMAT_VALUES.flatMap((format) =>
  SETUP_TOOLS[format].flatMap(({ value: tool }) =>
    SECTIONS.map((section) => [format, tool, section]),
  ),
);

describe('setupSnippetSections', () => {
  describe('what a format, tool, and section produce', () => {
    it.each(everyCombination)(
      'gives a %s repository on %s a %s section with at least one command',
      (format, tool, section) => {
        expect(codeOf(build({ format, tool, section }))).not.toHaveLength(0);
      },
    );

    it.each(everyCombination)(
      'follows the %s / %s / %s content with a setup section a client needs to reach the repository',
      (format, tool, section) => {
        const sections = build({ format, tool, section });

        expect(sections).toHaveLength(2);
        expect(sections[1].heading).toEqual(expect.any(String));
      },
    );

    it('identifies the Maven repository by the same alias the glab command registers', () => {
      const sections = build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_PUBLISH });
      const body = codeOf(sections).join('\n');

      expect(body).toContain(`--registry-alias ${ALIAS}`);
      expect(body.match(/<id>[^<]*<\/id>/g)).toEqual([`<id>${ALIAS}</id>`, `<id>${ALIAS}</id>`]);
    });
  });

  describe('the repository URL every snippet is composed on', () => {
    it.each(everyCombination)(
      'addresses this repository, not a placeholder, for %s on %s (%s)',
      (format, tool, section) => {
        const url = urlFor(format);
        const address = url;
        const withUrl = codeOf(build({ format, tool, section })).filter(
          (code) => code.includes(address) || code.includes(address.replace('https://', '')),
        );

        expect(withUrl).not.toHaveLength(0);
      },
    );

    it('strips the scheme where a container reference cannot carry one', () => {
      const [pull] = codeOf(
        build({ format: 'DOCKER', tool: 'docker', section: SETUP_SECTION_INSTALL }),
      );

      expect(pull).toBe(
        'docker pull artifact-registry.example.com/acme/container/my-repository/image:tag',
      );
    });

    it.each(['docker', 'podman'])(
      'keeps the registry port in the %s sign-in command, which Docker matches on',
      (tool) => {
        const glab = codeOf(
          setupSnippetSections({
            format: 'OCI',
            tool,
            section: SETUP_SECTION_INSTALL,
            slug: SLUG,
            name: NAME,
            repositoryUrl:
              'https://artifact-registry.example.com:8443/acme/container/my-repository',
          }),
        ).find((code) => code.startsWith('glab artifact-registry login'));

        expect(glab).toContain('--registry artifact-registry.example.com:8443');
      },
    );

    it('hands sbt the full registry URL, port included, which glab keys its entry on', () => {
      const url = 'https://artifact-registry.example.com:8443/acme/maven/my-repository';
      const glab = codeOf(
        setupSnippetSections({
          format: 'MAVEN',
          tool: 'sbt',
          section: SETUP_SECTION_INSTALL,
          slug: SLUG,
          name: NAME,
          repositoryUrl: url,
        }),
      ).find((code) => code.startsWith('glab artifact-registry login'));

      expect(glab).toContain(`--registry ${url}`);
    });
  });

  describe('switching the build tool', () => {
    it.each(REPOSITORY_FORMAT_VALUES)(
      'gives a %s repository different commands for each of its tools',
      (format) => {
        const perTool = SETUP_TOOLS[format].map(({ value: tool }) =>
          JSON.stringify(codeOf(build({ format, tool, section: SETUP_SECTION_PUBLISH }))),
        );

        expect(new Set(perTool).size).toBe(perTool.length);
      },
    );

    it('offers Gradle its own DSL rather than repeating the Maven command', () => {
      const groovy = codeOf(
        build({ format: 'MAVEN', tool: 'gradle_groovy', section: SETUP_SECTION_PUBLISH }),
      );
      const kotlin = codeOf(
        build({ format: 'MAVEN', tool: 'gradle_kotlin', section: SETUP_SECTION_PUBLISH }),
      );

      expect(groovy).toContain('gradle publish');
      expect(kotlin).toContain('gradle publish');
      expect(groovy.join()).not.toContain('mvn');
    });

    it.each([SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH])(
      'varies only the DSL between the Gradle tools in %s, never the Gradle install',
      (section) => {
        const forTool = (tool) => codeOf(build({ format: 'MAVEN', tool, section }));

        expect(forTool('gradle_groovy').join()).not.toContain('./gradlew');
        expect(forTool('gradle_kotlin').join()).not.toContain('./gradlew');
      },
    );

    it('publishes yarn through the Berry npm plugin, not the Classic `yarn publish`', () => {
      const [publish, registry] = codeOf(
        build({ format: 'NPM', tool: 'yarn', section: SETUP_SECTION_PUBLISH }),
      );

      expect(publish).toBe('yarn npm publish');
      expect(registry).toContain('npmScopes:');
    });
  });

  describe('credentials', () => {
    it.each(everyCombination)(
      'carries no credential and no token placeholder for %s on %s (%s)',
      (format, tool, section) => {
        const body = codeOf(build({ format, tool, section })).join('\n');

        expect(body).not.toMatch(/glpat-|--password[= ](?!-stdin)|-p\s+\S|Bearer\s/);
        expect(body).not.toContain('ARTIFACT_REGISTRY_TOKEN');
      },
    );

    it.each(everyCombination)(
      'leaves authentication to glab or to the docs for %s on %s (%s)',
      (format, tool, section) => {
        const blocks = build({ format, tool, section }).flatMap(({ blocks: b }) => b);
        const authenticates = blocks.some(
          ({ code, link }) => code?.startsWith('glab artifact-registry login') || Boolean(link),
        );

        expect(authenticates).toBe(true);
      },
    );

    it.each`
      section                  | configuration
      ${SETUP_SECTION_INSTALL} | ${'resolvers += ("artifact-registry" at "https://artifact-registry.example.com/acme/maven/my-repository")'}
      ${SETUP_SECTION_PUBLISH} | ${'publishTo := Some("artifact-registry" at "https://artifact-registry.example.com/acme/maven/my-repository")'}
    `('configures the sbt repository for $section', ({ section, configuration }) => {
      const body = codeOf(build({ format: 'MAVEN', tool: 'sbt', section })).join('\n');

      expect(body).toContain(configuration);
    });

    it.each(['maven', 'gradle_groovy', 'gradle_kotlin'])(
      'does not configure unsupported HTTP header authentication for %s',
      (tool) => {
        const body = codeOf(build({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL })).join(
          '\n',
        );

        expect(body).not.toContain('Private-Token');
        expect(body).not.toContain('HttpHeaderCredentials');
        expect(body).not.toContain('authentication {');
      },
    );
  });

  describe('a repository name carrying XML metacharacters', () => {
    const HOSTILE = 'a</id><url>https://evil.example/</url><id>b';

    const hostileSections = (section) =>
      setupSnippetSections({
        format: 'MAVEN',
        tool: 'maven',
        section,
        slug: SLUG,
        name: HOSTILE,
        repositoryUrl: urlFor('MAVEN'),
      });

    it.each(SECTIONS)('opens no new element anywhere in the %s XML', (section) => {
      const xml = codeOf(hostileSections(section)).filter((code) => code.startsWith('<'));

      expect(xml).not.toHaveLength(0);
      xml.forEach((code) => expect(code).not.toContain('<url>https://evil.example/</url>'));
    });

    const hostileXml = (section) =>
      codeOf(hostileSections(section)).filter((code) => code.startsWith('<'));

    it.each(SECTIONS)('confines the name to the alias charset where %s embeds it', (section) => {
      const withId = hostileXml(section).filter((code) => code.includes('<id>'));

      expect(withId).not.toHaveLength(0);
      withId.forEach((code) =>
        expect(code.match(/<id>([^<]*)<\/id>/)[1]).toMatch(/^[a-z0-9._-]+$/),
      );
    });

    it.each(SECTIONS)('keeps one id element per repository block in %s', (section) => {
      hostileXml(section)
        .filter((code) => code.includes('<id>'))
        .forEach((code) => {
          expect(code.match(/<id>/g)).toHaveLength(1);
        });
    });
  });

  describe('when no artifact coordinates are given', () => {
    it('leaves the Maven dependency on the module placeholders', () => {
      const [dependency] = codeOf(
        build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_INSTALL }),
      );

      expect(dependency).toBe(`<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>1.0.0</version>
</dependency>`);
    });

    it.each(['gradle_groovy', 'gradle_kotlin'])(
      'leaves the %s dependency on the module placeholders',
      (tool) => {
        const [dependency] = codeOf(
          build({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL }),
        );

        expect(dependency).toContain('com.company:app:1.0.0');
      },
    );

    it.each`
      tool      | command
      ${'npm'}  | ${'npm install @scope/package'}
      ${'yarn'} | ${'yarn add @scope/package'}
      ${'pnpm'} | ${'pnpm add @scope/package'}
    `('pins no version onto the $tool install command', ({ tool, command }) => {
      const [install] = codeOf(build({ format: 'NPM', tool, section: SETUP_SECTION_INSTALL }));

      expect(install).toBe(command);
    });
  });

  describe('when a version names its own coordinates', () => {
    const MAVEN_COORDINATES = {
      groupId: 'com.company.payment',
      artifactId: 'core',
      version: '2.4.1',
    };
    const NPM_COORDINATES = { packageName: '@company/design-system', version: '4.2.0' };

    const buildFor = ({ format, tool, coordinates }) =>
      setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        slug: SLUG,
        name: NAME,
        repositoryUrl: urlFor(format),
        ...coordinates,
      });

    it('reads them back in the Maven dependency', () => {
      const [dependency] = codeOf(
        buildFor({ format: 'MAVEN', tool: 'maven', coordinates: MAVEN_COORDINATES }),
      );

      expect(dependency).toBe(`<dependency>
  <groupId>com.company.payment</groupId>
  <artifactId>core</artifactId>
  <version>2.4.1</version>
</dependency>`);
    });

    it.each`
      tool               | declaration
      ${'gradle_groovy'} | ${"implementation 'com.company.payment:core:2.4.1'"}
      ${'gradle_kotlin'} | ${'implementation("com.company.payment:core:2.4.1")'}
    `('reads them back in the $tool declaration', ({ tool, declaration }) => {
      const [dependency] = codeOf(
        buildFor({ format: 'MAVEN', tool, coordinates: MAVEN_COORDINATES }),
      );

      expect(dependency).toBe(declaration);
    });

    it.each`
      tool      | command
      ${'npm'}  | ${'npm install @company/design-system@4.2.0'}
      ${'yarn'} | ${'yarn add @company/design-system@4.2.0'}
      ${'pnpm'} | ${'pnpm add @company/design-system@4.2.0'}
    `('pins the version onto the $tool install command', ({ tool, command }) => {
      const [install] = codeOf(buildFor({ format: 'NPM', tool, coordinates: NPM_COORDINATES }));

      expect(install).toBe(command);
    });

    it('names the package without a version when the version is absent', () => {
      const [install] = codeOf(
        buildFor({
          format: 'NPM',
          tool: 'npm',
          coordinates: { packageName: '@company/design-system' },
        }),
      );

      expect(install).toBe('npm install @company/design-system');
    });

    it('leaves the publish section alone, which names the repository rather than an artifact', () => {
      const withCoordinates = setupSnippetSections({
        format: 'MAVEN',
        tool: 'maven',
        section: SETUP_SECTION_PUBLISH,
        slug: SLUG,
        name: NAME,
        repositoryUrl: urlFor('MAVEN'),
        ...MAVEN_COORDINATES,
      });

      expect(withCoordinates).toStrictEqual(
        build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_PUBLISH }),
      );
    });
  });

  describe('when a manifest names its own image and reference', () => {
    const IMAGE = { imageName: 'payment-service', tag: 'trixie', digest: DIGEST };

    const buildContainer = ({ format = 'DOCKER', tool = 'docker', ...rest } = {}) =>
      setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        slug: SLUG,
        name: NAME,
        repositoryUrl: urlFor(format),
        ...rest,
      });

    const host = (format) => urlFor(format).replace(/^https?:\/\//, '');

    it.each`
      format      | client
      ${'DOCKER'} | ${'docker'}
      ${'OCI'}    | ${'oras'}
    `('pulls by tag and then by digest on $format, with $client', ({ format, client }) => {
      expect(codeOf(buildContainer({ format, ...IMAGE }))).toEqual([
        `${client} pull ${host(format)}/payment-service:trixie`,
        `${client} pull ${host(format)}/payment-service@${DIGEST}`,
        expect.stringContaining('glab artifact-registry login'),
      ]);
    });

    it.each(['docker', 'podman'])(
      'pulls an OCI artifact with oras whatever %s is selected',
      (tool) => {
        expect(codeOf(buildContainer({ format: 'OCI', tool, ...IMAGE }))).toEqual([
          `oras pull ${host('OCI')}/payment-service:trixie`,
          `oras pull ${host('OCI')}/payment-service@${DIGEST}`,
          expect.stringContaining('glab artifact-registry login'),
        ]);
      },
    );

    describe.each([SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH])(
      'the digestless OCI command in the %s section',
      (section) => {
        it.each(['docker', 'podman'])(
          'stays on the selected %s, which the drawer picks',
          (tool) => {
            expect(
              codeOf(
                buildContainer({ format: 'OCI', imageName: 'payment-service', section, tool }),
              ),
            ).toEqual([
              expect.stringMatching(new RegExp(`^${tool} (pull|push) `)),
              expect.stringContaining('glab artifact-registry login'),
            ]);
          },
        );
      },
    );

    it('drops the by-tag command for an untagged manifest rather than pulling the placeholder', () => {
      const [pull] = buildContainer({ imageName: 'payment-service', digest: DIGEST });

      expect(pull.blocks).toHaveLength(1);
      expect(pull.blocks[0].code).toBe(`docker pull ${host('DOCKER')}/payment-service@${DIGEST}`);
    });

    it('labels the pair so a reader can tell the two references apart', () => {
      const [pull] = buildContainer(IMAGE);

      expect(pull.blocks.map(({ text }) => text)).toEqual(['Pull by tag', 'Pull by digest']);
    });

    it('names each copy button for the reference it copies, not just the pair', () => {
      const [pull] = buildContainer(IMAGE);

      expect(pull.blocks.map(({ copyText }) => copyText)).toEqual([
        'Copy the pull-by-tag command',
        'Copy the pull-by-digest command',
      ]);
    });

    it('carries the selected client through to both Docker commands', () => {
      expect(codeOf(buildContainer({ tool: 'podman', ...IMAGE }))).toEqual([
        `podman pull ${host('DOCKER')}/payment-service:trixie`,
        `podman pull ${host('DOCKER')}/payment-service@${DIGEST}`,
        expect.stringContaining('glab artifact-registry login'),
      ]);
    });

    it('keeps the single placeholder command when an image is named without a digest', () => {
      const [pull] = codeOf(buildContainer({ imageName: 'payment-service' }));

      expect(pull).toBe(`docker pull ${host('DOCKER')}/payment-service:tag`);
    });

    it('pushes by tag on the publish section, never by digest', () => {
      const [push] = codeOf(buildContainer({ ...IMAGE, section: SETUP_SECTION_PUBLISH }));

      expect(push).toBe(`docker push ${host('DOCKER')}/payment-service:trixie`);
    });

    describe.each([null, undefined, ''])('with a tag given as %p', (tag) => {
      it('drops the by-tag command and keeps the rest of the panel, glab command included', () => {
        expect(
          codeOf(buildContainer({ imageName: 'payment-service', tag, digest: DIGEST })),
        ).toEqual([
          `docker pull ${host('DOCKER')}/payment-service@${DIGEST}`,
          expect.stringContaining('glab artifact-registry login'),
        ]);
      });
    });

    describe.each([null, undefined, ''])('with a digest given as %p', (digest) => {
      it('falls back to the single by-tag command rather than emptying the panel', () => {
        expect(
          codeOf(buildContainer({ imageName: 'payment-service', tag: 'trixie', digest })),
        ).toEqual([
          `docker pull ${host('DOCKER')}/payment-service:trixie`,
          expect.stringContaining('glab artifact-registry login'),
        ]);
      });
    });
  });

  describe('a manifest reference no registry could serve', () => {
    const buildContainer = (rest) =>
      setupSnippetSections({
        format: 'DOCKER',
        tool: 'docker',
        section: SETUP_SECTION_INSTALL,
        name: NAME,
        repositoryUrl: urlFor('DOCKER'),
        ...rest,
      });

    it.each`
      case                   | digest
      ${'uppercase hex'}     | ${`sha256:${'A1B2C3D4'.repeat(8)}`}
      ${'another algorithm'} | ${`sha512:${'a1b2c3d4'.repeat(8)}`}
      ${'a truncated hex'}   | ${'sha256:a1b2c3d4'}
      ${'no algorithm'}      | ${'a1b2c3d4'.repeat(8)}
      ${'a shell payload'}   | ${`sha256:${'a1b2c3d4'.repeat(8)}; rm -rf /`}
      ${'a non-string'}      | ${42}
    `('yields no sections for $case', ({ digest }) => {
      expect(buildContainer({ imageName: 'payment-service', digest })).toEqual([]);
    });

    it.each(['imageName', 'tag'])('yields no sections for a hostile %s', (field) => {
      expect(buildContainer({ [field]: 'a; rm -rf /', digest: DIGEST })).toEqual([]);
    });
  });

  describe('a coordinate no artifact could carry', () => {
    const HOSTILE = {
      xml: 'a</groupId><evil>x</evil><groupId>b',
      groovyQuote: "1.0'; System.exit(0); '",
      kotlinQuote: '1.0"); System.exit(0); ("',
      kotlinTemplate: '1.0-$buildDir',
      backslash: 'a\\b',
      shell: 'pkg; rm -rf /',
      space: 'com.company app',
    };

    const buildWith = (coordinates, { format = 'MAVEN', tool = 'maven' } = {}) =>
      setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        name: NAME,
        repositoryUrl: urlFor(format),
        ...coordinates,
      });

    it.each(Object.entries(HOSTILE))('yields no sections for a groupId carrying %s', (_, value) => {
      expect(buildWith({ groupId: value })).toEqual([]);
    });

    it.each(['artifactId', 'version'])('yields no sections for a hostile %s', (field) => {
      expect(buildWith({ [field]: HOSTILE.xml })).toEqual([]);
    });

    it('yields no sections for a hostile npm package name', () => {
      expect(buildWith({ packageName: HOSTILE.shell }, { format: 'NPM', tool: 'npm' })).toEqual([]);
    });

    it.each(['maven', 'gradle_groovy', 'gradle_kotlin'])(
      'refuses it on %s, so no tool renders it',
      (tool) => {
        expect(buildWith({ version: HOSTILE.groovyQuote }, { tool })).toEqual([]);
      },
    );

    it('refuses an empty coordinate rather than composing a hole into the snippet', () => {
      expect(buildWith({ artifactId: '' })).toEqual([]);
    });

    it.each([
      ['null, which GraphQL sends for an unset field', null],
      ['a number', 2.4],
      ['a boolean', false],
    ])('refuses a version that is %s rather than falling back to the placeholder', (_, value) => {
      expect(buildWith({ version: value })).toEqual([]);
    });

    it('refuses a null npm package name', () => {
      expect(buildWith({ packageName: null }, { format: 'NPM', tool: 'npm' })).toEqual([]);
    });
  });

  describe('a coordinate a real artifact can hold', () => {
    const buildWith = (coordinates, { format = 'MAVEN', tool = 'maven' } = {}) =>
      codeOf(
        setupSnippetSections({
          format,
          tool,
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: urlFor(format),
          ...coordinates,
        }),
      );

    it.each([
      [
        'a dotted group',
        { groupId: 'com.company.payment' },
        `<dependency>
  <groupId>com.company.payment</groupId>
  <artifactId>app</artifactId>
  <version>1.0.0</version>
</dependency>`,
      ],
      [
        'a hyphenated artifact',
        { artifactId: 'core-api' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>core-api</artifactId>
  <version>1.0.0</version>
</dependency>`,
      ],
      [
        'an underscored artifact',
        { artifactId: 'core_api' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>core_api</artifactId>
  <version>1.0.0</version>
</dependency>`,
      ],
      [
        'a prerelease version',
        { version: '2.4.1-rc.1' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>2.4.1-rc.1</version>
</dependency>`,
      ],
      [
        'a build-metadata version',
        { version: '2.4.1+build.7' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>2.4.1+build.7</version>
</dependency>`,
      ],
      [
        'a SNAPSHOT version',
        { version: '2.4.1-SNAPSHOT' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>2.4.1-SNAPSHOT</version>
</dependency>`,
      ],
    ])('composes the Maven dependency for %s', (_, coordinates, dependency) => {
      const [actual] = buildWith(coordinates);

      expect(actual).toBe(dependency);
    });

    it('composes the npm install command for a scoped package', () => {
      const [install] = buildWith(
        { packageName: '@company/design-system', version: '4.2.0' },
        { format: 'NPM', tool: 'npm' },
      );

      expect(install).toBe('npm install @company/design-system@4.2.0');
    });
  });

  describe('when the guidance cannot be composed', () => {
    it('yields no sections without a repository URL, rather than guidance with a hole in it', () => {
      expect(
        setupSnippetSections({
          format: 'MAVEN',
          tool: 'maven',
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: null,
        }),
      ).toEqual([]);
    });

    it('yields no sections without a repository name', () => {
      expect(
        setupSnippetSections({
          format: 'MAVEN',
          tool: 'maven',
          section: SETUP_SECTION_INSTALL,
          name: '',
          repositoryUrl: urlFor('MAVEN'),
        }),
      ).toEqual([]);
    });

    it('yields no sections for a format it carries no guidance for', () => {
      expect(
        setupSnippetSections({
          format: 'CONAN',
          tool: 'conan',
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: urlFor('MAVEN'),
        }),
      ).toEqual([]);
    });

    it.each`
      format      | tool        | field
      ${'MAVEN'}  | ${'maven'}  | ${'groupId'}
      ${'MAVEN'}  | ${'maven'}  | ${'artifactId'}
      ${'MAVEN'}  | ${'maven'}  | ${'version'}
      ${'NPM'}    | ${'npm'}    | ${'packageName'}
      ${'DOCKER'} | ${'docker'} | ${'imageName'}
    `('yields no sections for a null $field on $format', ({ format, tool, field }) => {
      expect(
        setupSnippetSections({
          format,
          tool,
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: urlFor(format),
          [field]: null,
        }),
      ).toEqual([]);
    });
  });
});

describe('installSnippetBlock', () => {
  const MAVEN_COORDINATES = {
    groupId: 'com.company.payment',
    artifactId: 'core',
    version: '2.4.1',
  };

  const NPM_COORDINATES = { packageName: '@company/design-system', version: '4.2.0' };

  const blockFor = ({ format, tool, ...coordinates }) =>
    installSnippetBlock({
      format,
      tool,
      name: NAME,
      repositoryUrl: urlFor(format),
      ...coordinates,
    });

  const INSTALL_TOOLS = ['MAVEN', 'NPM'].flatMap((format) =>
    SETUP_TOOLS[format].map(({ value: tool }) => [format, tool]),
  );

  it.each(INSTALL_TOOLS)(
    'gives a %s repository on %s the first block of its install section',
    (format, tool) => {
      const [section] = setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        name: NAME,
        repositoryUrl: urlFor(format),
      });

      expect(blockFor({ format, tool })).toStrictEqual(section.blocks[0]);
    },
  );

  it('gives the Maven dependency declaration, not the command that follows it', () => {
    expect(blockFor({ format: 'MAVEN', tool: 'maven', ...MAVEN_COORDINATES }).code)
      .toBe(`<dependency>
  <groupId>com.company.payment</groupId>
  <artifactId>core</artifactId>
  <version>2.4.1</version>
</dependency>`);
  });

  it('gives the npm install command, not the publish command that follows it', () => {
    expect(blockFor({ format: 'NPM', tool: 'npm', ...NPM_COORDINATES }).code).toBe(
      'npm install @company/design-system@4.2.0',
    );
  });

  it('gives a digest-addressed container its by-tag command, the first of the pair', () => {
    const host = urlFor('DOCKER').replace(/^https?:\/\//, '');
    const block = blockFor({
      format: 'DOCKER',
      tool: 'docker',
      imageName: 'payment-service',
      tag: 'trixie',
      digest: DIGEST,
    });

    expect(block.code).toBe(`docker pull ${host}/payment-service:trixie`);
    expect(block.copyText).toBe('Copy the pull-by-tag command');
  });

  it('gives an untagged container its by-digest command, the only one of the pair', () => {
    const host = urlFor('DOCKER').replace(/^https?:\/\//, '');
    const block = blockFor({
      format: 'DOCKER',
      tool: 'docker',
      imageName: 'payment-service',
      tag: null,
      digest: DIGEST,
    });

    expect(block.code).toBe(`docker pull ${host}/payment-service@${DIGEST}`);
    expect(block.copyText).toBe('Copy the pull-by-digest command');
  });

  it.each`
    format     | tool       | coordinates          | copyText
    ${'MAVEN'} | ${'maven'} | ${MAVEN_COORDINATES} | ${'Copy the dependency declaration'}
    ${'NPM'}   | ${'npm'}   | ${NPM_COORDINATES}   | ${'Copy the install command'}
  `(
    'names what the $format copy button copies, which the icon-only button needs',
    ({ format, tool, coordinates, copyText }) => {
      expect(blockFor({ format, tool, ...coordinates }).copyText).toBe(copyText);
    },
  );

  it.each`
    refusal                          | args
    ${'no repository URL'}           | ${{ repositoryUrl: null }}
    ${'no repository name'}          | ${{ name: '' }}
    ${'a format it cannot build'}    | ${{ format: 'CONAN' }}
    ${'a coordinate it cannot hold'} | ${{ groupId: 'a</groupId><evil>x</evil><groupId>b' }}
  `('gives no block for $refusal, rather than one with a hole in it', ({ args }) => {
    expect(
      installSnippetBlock({
        format: 'MAVEN',
        tool: 'maven',
        name: NAME,
        repositoryUrl: urlFor('MAVEN'),
        ...args,
      }),
    ).toBe(null);
  });
});

describe('the glab artifact-registry login command', () => {
  const glabOf = (args) =>
    codeOf(build(args)).find((code) => code.startsWith('glab artifact-registry login'));

  it('authenticates Maven under the same alias the repository block declares', () => {
    expect(glabOf({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_INSTALL })).toBe(
      `glab artifact-registry login \\
  --maven \\
  --registry ${urlFor('MAVEN')} \\
  --registry-alias ${ALIAS}`,
    );
  });

  it.each(['gradle_groovy', 'gradle_kotlin'])('registers %s under the same alias', (tool) => {
    expect(glabOf({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL })).toBe(
      `glab artifact-registry login \\
  --gradle \\
  --registry ${urlFor('MAVEN')} \\
  --registry-alias ${ALIAS}`,
    );
  });

  it.each([
    ['MAVEN', 'sbt', 'sbt'],
    ['NPM', 'npm', 'npm'],
    ['NPM', 'pnpm', 'npm'],
  ])(
    'logs %s in on %s with no alias, because glab keys its entry on the registry',
    (format, tool, flag) => {
      expect(glabOf({ format, tool, section: SETUP_SECTION_INSTALL })).toBe(
        `glab artifact-registry login \\
  --${flag} \\
  --registry ${urlFor(format)}`,
      );
    },
  );

  it.each([
    ['DOCKER', 'docker'],
    ['DOCKER', 'podman'],
    ['OCI', 'docker'],
    ['OCI', 'podman'],
  ])('hands %s on %s the --docker flag and a bare registry host', (format, tool) => {
    expect(glabOf({ format, tool, section: SETUP_SECTION_INSTALL })).toBe(
      `glab artifact-registry login \\
  --docker \\
  --registry artifact-registry.example.com`,
    );
  });

  it('passes no duration, leaving glab to apply its own default', () => {
    everyCombination.forEach(([format, tool, section]) => {
      expect(glabOf({ format, tool, section }) ?? '').not.toContain('--duration');
    });
  });

  it('offers no command for NPM on yarn, which glab has no writer for', () => {
    expect(glabOf({ format: 'NPM', tool: 'yarn', section: SETUP_SECTION_INSTALL })).toBeUndefined();
  });

  it.each([
    ['MAVEN', 'maven'],
    ['MAVEN', 'gradle_groovy'],
    ['MAVEN', 'gradle_kotlin'],
    ['MAVEN', 'sbt'],
    ['NPM', 'npm'],
    ['NPM', 'pnpm'],
    ['DOCKER', 'docker'],
    ['DOCKER', 'podman'],
    ['OCI', 'docker'],
    ['OCI', 'podman'],
  ])('leads the setup section for %s on %s', (format, tool) => {
    const [, setup] = build({ format, tool, section: SETUP_SECTION_INSTALL });

    expect(setup.blocks[0].code).toContain('glab artifact-registry login');
  });

  it('links the reader to the command reference', () => {
    const [, setup] = build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_INSTALL });

    expect(setup.blocks[0].link).toBe('https://docs.gitlab.com/cli/artifact-registry/login/');
  });

  it('sends yarn to the authentication docs instead of a hand-written token', () => {
    const [, setup] = build({ format: 'NPM', tool: 'yarn', section: SETUP_SECTION_INSTALL });

    expect(setup.blocks[0].link).toBe('https://docs.gitlab.com/artifact-registry/authenticate/');
    expect(setup.blocks[0].code).toBeUndefined();
    expect(codeOf([setup]).join('\n')).not.toContain('npmAuthToken');
  });
});

describe('the registry alias', () => {
  const aliasFor = ({ slug = SLUG, name }) =>
    setupSnippetSections({
      format: 'MAVEN',
      tool: 'gradle_groovy',
      section: SETUP_SECTION_INSTALL,
      slug,
      name,
      repositoryUrl: buildRepositoryClientUrl({
        clientBaseUrl: CLIENT_BASE_URL,
        slug,
        format: 'MAVEN',
        name,
      }),
    })
      .flatMap(({ blocks }) => blocks.map(({ code }) => code))
      .join('\n')
      .match(/--registry-alias (\S+)/)?.[1];

  it.each([
    ['maven-releases', 'ar-acme.maven-releases'],
    ['maven.releases', 'ar-acme.maven.releases'],
    ['maven_releases', 'ar-acme.maven_releases'],
    ['1password-lib', 'ar-acme.1password-lib'],
    ['a', 'ar-acme.a'],
  ])('derives %s into %s', (name, expected) => {
    expect(aliasFor({ name })).toBe(expected);
  });

  it.each(['maven-releases', 'maven.releases', 'maven_releases', '1password-lib'])(
    'keeps %s inside the charset glab accepts for an alias',
    (name) => {
      expect(aliasFor({ name })).toMatch(/^[a-zA-Z0-9._-]+$/);
    },
  );

  it('gives every distinct handle and name pair its own alias, so neither overwrites the other in the files glab writes', () => {
    const pairs = [
      ['acme', 'maven-releases'],
      ['acme', 'maven.releases'],
      ['acme', 'maven_releases'],
      ['acme', 'payments'],
      ['other-org', 'payments'],
      ['acme-pay', 'ments'],
      ['acme', 'pay-ments'],
    ];
    const aliases = pairs.map(([slug, name]) => aliasFor({ slug, name }));

    expect(new Set(aliases).size).toBe(pairs.length);
  });

  it.each([
    ['gradle_groovy', "providers.gradleProperty('ar-acme.my-repositoryUrl').get()"],
    ['gradle_kotlin', 'providers.gradleProperty("ar-acme.my-repositoryUrl").get()'],
  ])('reads the %s repository from the property glab wrote under that alias', (tool, expected) => {
    const [, setup] = build({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL });

    expect(setup.blocks[1].code).toContain(expected);
  });

  it('confines a name outside the alias charset rather than passing it through', () => {
    expect(aliasFor({ name: "a';touch /tmp/pwned;'b" })).toBe('ar-acme.a-touch-tmp-pwned-b');
  });
});
