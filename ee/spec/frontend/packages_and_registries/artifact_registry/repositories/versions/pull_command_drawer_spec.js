import { GlCollapsibleListbox, GlLink } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import InstructionsDrawer from 'ee/packages_and_registries/artifact_registry/components/instructions_drawer.vue';
import PullCommandDrawer from 'ee/packages_and_registries/artifact_registry/repositories/versions/pull_command_drawer.vue';
import SnippetCodeBlock from 'ee/packages_and_registries/artifact_registry/components/snippet_code_block.vue';
import {
  CLIENT_BASE_URL,
  SLUG,
  mockManifests,
  mockRepository,
  mockRepositoryArtifacts,
  mockVersions,
} from '../../mock_data';

const VERSION = mockVersions[0].version;
const DIGEST = mockManifests[0].digest;

describe('ArtifactRegistryPullCommandDrawer', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = {} } = {}) => {
    wrapper = mountExtended(PullCommandDrawer, {
      propsData: {
        open: true,
        format: 'MAVEN',
        artifact: mockRepositoryArtifacts('MAVEN').package,
        name: mockRepository.name,
        version: VERSION,
        ...props,
      },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL, ...provide },
      stubs: {
        InstructionsDrawer: stubComponent(InstructionsDrawer, {
          template: '<div><slot /></div>',
        }),
      },
    });
  };

  const createContainerComponent = ({ props = {}, provide = {} } = {}) =>
    createComponent({
      props: {
        format: 'DOCKER',
        artifact: mockRepositoryArtifacts('DOCKER').image,
        version: '',
        digest: DIGEST,
        ...props,
      },
      provide,
    });

  const findDrawer = () => wrapper.findComponent(InstructionsDrawer);
  const findSections = () => wrapper.findAllByTestId('pull-command-section');
  const findBlocks = () => wrapper.findAllComponents(SnippetCodeBlock);
  const findHelp = () => wrapper.findByTestId('pull-command-help');
  const findTagSelector = () => wrapper.findComponent(GlCollapsibleListbox);
  const findSnippets = () => findBlocks().wrappers.map((block) => block.props('snippet'));
  const findSectionTitle = (index) =>
    findSections().at(index).find('[data-testid="crud-title"]').text();

  describe('the drawer it renders', () => {
    beforeEach(() => createComponent());

    it('titles the drawer, which is its accessible name', () => {
      expect(findDrawer().props()).toMatchObject({
        title: 'Pull command',
        accessibleTitle: 'Pull command for 3.2.1',
        open: true,
      });
    });

    it('links the footer to the documentation for the format', () => {
      expect(findHelp().text()).toBe('For more information, see the documentation.');
      expect(findHelp().findComponent(GlLink).attributes('href')).toBe(
        'https://docs.gitlab.com/artifact-registry/formats/maven/',
      );
    });

    it('closes when the drawer asks to be closed', () => {
      findDrawer().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('the command it renders', () => {
    it('heads the section and hands its command to a copyable block', () => {
      createComponent();

      expect(findSections()).toHaveLength(1);
      expect(findSectionTitle(0)).toBe('Install by version');
      expect(findBlocks().at(0).props()).toMatchObject({
        snippet: expect.stringContaining('mvn dependency:get'),
        copyText: 'Copy the install command',
      });
    });

    it.each`
      format     | artifactFor | snippet
      ${'MAVEN'} | ${'MAVEN'}  | ${"-Dversion='3.2.1'"}
      ${'NPM'}   | ${'NPM'}    | ${"npm install '@company/design-system@3.2.1'"}
    `(
      'pins the $format command to the row it was opened from',
      ({ format, artifactFor, snippet }) => {
        createComponent({
          props: { format, artifact: mockRepositoryArtifacts(artifactFor).package },
        });

        expect(findBlocks().at(0).props('snippet')).toContain(snippet);
      },
    );
  });

  describe('for an npm version carrying dist-tags', () => {
    const createNpmComponent = (tags) =>
      createComponent({
        props: { format: 'NPM', artifact: mockRepositoryArtifacts('NPM').package, tags },
      });

    describe('with one tag', () => {
      beforeEach(() => createNpmComponent(['latest']));

      it('leads with the tag-keyed install and offers no selector for a single tag', () => {
        expect(findSectionTitle(0)).toBe('Install by tag');
        expect(findSectionTitle(1)).toBe('Install by version');
        expect(findSnippets()).toEqual([
          "npm install '@company/design-system@latest'",
          "npm install '@company/design-system@3.2.1'",
        ]);
        expect(findTagSelector().exists()).toBe(false);
      });
    });

    describe('with several tags', () => {
      beforeEach(() => createNpmComponent(['latest', 'stable']));

      it('offers a selector on the tag card, starting from the first tag', () => {
        expect(findTagSelector().props()).toMatchObject({
          selected: 'latest',
          items: [
            { value: 'latest', text: 'latest' },
            { value: 'stable', text: 'stable' },
          ],
        });
        expect(findSections().at(0).findComponent(GlCollapsibleListbox).exists()).toBe(true);
      });

      it('rekeys the tag install to the tag picked', async () => {
        findTagSelector().vm.$emit('select', 'stable');
        await nextTick();

        expect(findSnippets()[0]).toBe("npm install '@company/design-system@stable'");
      });
    });

    it('renders the version card alone for a version carrying no dist-tag', () => {
      createNpmComponent([]);

      expect(findSections()).toHaveLength(1);
      expect(findSectionTitle(0)).toBe('Install by version');
    });
  });

  describe('for a container manifest', () => {
    beforeEach(() => createContainerComponent());

    it('links the footer to the container documentation', () => {
      expect(findHelp().findComponent(GlLink).attributes('href')).toBe(
        'https://docs.gitlab.com/artifact-registry/formats/docker/',
      );
    });

    it('names the drawer for the digest it was opened for', () => {
      expect(findDrawer().props('accessibleTitle')).toBe('Pull command for 111111111111');
    });

    it('composes the pull-by-digest command from the registry the page was mounted for', () => {
      expect(findSections()).toHaveLength(1);
      expect(findSectionTitle(0)).toBe('Pull by digest');
      expect(findBlocks().at(0).props()).toMatchObject({
        snippet: `docker pull 'artifact-registry.example.com/acme/container/my-repository/payment-service@${DIGEST}'`,
        copyText: 'Copy the pull command',
      });
    });
  });

  describe('when there is no command to render', () => {
    it.each`
      case                                            | props
      ${'no version'}                                 | ${{ version: '' }}
      ${'a format the drawer carries no command for'} | ${{ format: 'CONAN' }}
    `('renders the drawer with no section for $case', ({ props }) => {
      createComponent({ props });

      expect(findDrawer().exists()).toBe(true);
      expect(findSections()).toHaveLength(0);
    });

    it('renders no documentation link for a format it has none for', () => {
      createComponent({ props: { format: 'CONAN' } });

      expect(findHelp().exists()).toBe(false);
    });

    it.each`
      case                                     | props             | provide
      ${'no digest'}                           | ${{ digest: '' }} | ${{}}
      ${'no client base URL reached the page'} | ${{}}             | ${{ clientBaseUrl: '' }}
    `('renders the drawer with no section for $case', ({ props, provide }) => {
      createContainerComponent({ props, provide });

      expect(findDrawer().exists()).toBe(true);
      expect(findSections()).toHaveLength(0);
    });
  });
});
