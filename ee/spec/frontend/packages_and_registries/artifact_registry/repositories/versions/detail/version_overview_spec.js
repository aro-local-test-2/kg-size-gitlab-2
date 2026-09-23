import { GlCollapsibleListbox, GlLink } from '@gitlab/ui';
import mavenVersionFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version.query.graphql.json';
import npmVersionFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version.npm.query.graphql.json';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import SnippetCodeBlock from 'ee/packages_and_registries/artifact_registry/components/snippet_code_block.vue';
import VersionOverview from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/version_overview.vue';
import { CLIENT_BASE_URL, SLUG } from '../../../mock_data';

const NAME = 'my-repository';

const REPOSITORY_FOR = {
  MAVEN: mavenVersionFixture.data.organization.artifactRegistryRepository,
  NPM: npmVersionFixture.data.organization.artifactRegistryRepository,
};

const MAVEN_DEPENDENCY = `<dependency>
  <groupId>com.example.tools</groupId>
  <artifactId>payment-core</artifactId>
  <version>3.2.1</version>
</dependency>`;

describe('ArtifactRegistryVersionOverview', () => {
  let wrapper;

  const findPanel = () => wrapper.findByTestId('install-panel');
  const findTitle = () => wrapper.findByTestId('crud-title');
  const findSnippet = () => wrapper.findComponent(SnippetCodeBlock);
  const findSelector = () => wrapper.findComponent(GlCollapsibleListbox);
  const findUnavailable = () => wrapper.findByTestId('install-unavailable');
  const findFooter = () => wrapper.findByTestId('crud-footer');
  const findDocLink = () => findFooter().findComponent(GlLink);

  const createComponent = ({
    format = 'MAVEN',
    artifact = REPOSITORY_FOR[format].package,
    version = REPOSITORY_FOR[format].version,
    provide = {},
  } = {}) => {
    wrapper = mountExtended(VersionOverview, {
      propsData: { format, name: NAME, artifact, version },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL, ...provide },
    });
  };

  const selectTool = (tool) => findSelector().vm.$emit('select', tool);

  describe('the panel it renders', () => {
    beforeEach(() => createComponent());

    it('names the panel for the one thing it offers', () => {
      expect(findTitle().text()).toBe('Install');
    });

    it('renders one snippet, without the registry configuration the setup drawer carries', () => {
      expect(wrapper.findAllComponents(SnippetCodeBlock)).toHaveLength(1);
    });

    it('gives the copy button a label, because the button itself carries only an icon', () => {
      expect(findSnippet().props('copyText')).toBe('Copy the dependency declaration');
    });

    it('says nothing about instructions being unavailable, because they are not', () => {
      expect(findUnavailable().exists()).toBe(false);
    });
  });

  describe('the snippet it builds', () => {
    it('declares the Maven dependency this version publishes', () => {
      createComponent();

      expect(findSnippet().props('snippet')).toBe(MAVEN_DEPENDENCY);
    });

    it('pins the npm install command to this version, under the scoped package name', () => {
      createComponent({ format: 'NPM' });

      expect(findSnippet().props('snippet')).toBe('npm install @acme/ui-components@3.2.1');
    });

    it.each(['MAVEN', 'NPM'])('names no credential in the %s snippet', (format) => {
      createComponent({ format });

      expect(findSnippet().props('snippet')).not.toContain('ARTIFACT_REGISTRY_TOKEN');
    });
  });

  describe('the build tool it composes for', () => {
    it.each`
      format     | tools
      ${'MAVEN'} | ${['maven', 'gradle_groovy', 'gradle_kotlin', 'sbt']}
      ${'NPM'}   | ${['npm', 'yarn', 'pnpm']}
    `('offers a $format repository the tools the setup drawer offers', ({ format, tools }) => {
      createComponent({ format });

      expect(
        findSelector()
          .props('items')
          .map(({ value }) => value),
      ).toEqual(tools);
    });

    it('offers the first tool until one is chosen', () => {
      createComponent();

      expect(findSelector().props('selected')).toBe('maven');
    });

    it('falls back to the first tool when the format changes under a chosen one', async () => {
      createComponent();
      await selectTool('gradle_kotlin');

      await wrapper.setProps({ format: 'NPM', artifact: REPOSITORY_FOR.NPM.package });

      expect(findSelector().props('selected')).toBe('npm');
      expect(findSnippet().props('snippet')).toBe('npm install @acme/ui-components@3.2.1');
    });

    it.each`
      format     | tool               | code
      ${'MAVEN'} | ${'gradle_kotlin'} | ${'implementation("com.example.tools:payment-core:3.2.1")'}
      ${'MAVEN'} | ${'sbt'}           | ${'libraryDependencies += "com.example.tools" % "payment-core" % "3.2.1"'}
      ${'NPM'}   | ${'pnpm'}          | ${'pnpm add @acme/ui-components@3.2.1'}
    `('recomposes the snippet for $tool', async ({ format, tool, code }) => {
      createComponent({ format });

      await selectTool(tool);

      expect(findSnippet().props('snippet')).toBe(code);
    });
  });

  describe('the documentation it points at', () => {
    it.each`
      format     | text                                                                    | path
      ${'MAVEN'} | ${'For more information on the Maven registry, see the documentation.'} | ${'https://docs.gitlab.com/artifact-registry/formats/maven/'}
      ${'NPM'}   | ${'For more information on the npm registry, see the documentation.'}   | ${'https://docs.gitlab.com/artifact-registry/formats/npm/'}
    `('names the $format registry and links its page', ({ format, text, path }) => {
      createComponent({ format });

      expect(findFooter().text()).toBe(text);
      expect(findDocLink().attributes('href')).toBe(path);
    });
  });

  describe('when the snippet cannot be composed', () => {
    const UNCOMPOSABLE = [
      ['the Maven artifact beside the version is null', { artifact: null }],
      ['the npm artifact beside the version is null', { format: 'NPM', artifact: null }],
      ['no client base URL reached the browser', { provide: { clientBaseUrl: '' } }],
      [
        'the version string is not a safe coordinate',
        { version: { ...REPOSITORY_FOR.MAVEN.version, version: '1.0<x' } },
      ],
    ];

    it.each(UNCOMPOSABLE)('renders no snippet when %s', (_outcome, overrides) => {
      createComponent(overrides);

      expect(findSnippet().exists()).toBe(false);
      expect(findSelector().exists()).toBe(false);
    });

    it.each(UNCOMPOSABLE)(
      'says why the instructions are missing when %s',
      (_outcome, overrides) => {
        createComponent(overrides);

        expect(findUnavailable().text()).toBe(
          'Install instructions are unavailable because the package could not be loaded.',
        );
      },
    );

    it('keeps the panel and its documentation link, which do not depend on the artifact', () => {
      createComponent({ artifact: null });

      expect(findPanel().exists()).toBe(true);
      expect(findDocLink().attributes('href')).toBe(
        'https://docs.gitlab.com/artifact-registry/formats/maven/',
      );
    });

    it('names no module placeholder in place of the coordinates it lacks', () => {
      createComponent({ artifact: null });

      expect(wrapper.text()).not.toContain('com.example');
    });
  });
});
