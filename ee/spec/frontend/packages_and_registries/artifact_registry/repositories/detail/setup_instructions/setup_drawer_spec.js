import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import {
  SETUP_SECTION_INSTALL,
  SETUP_SECTION_PUBLISH,
} from 'ee/packages_and_registries/artifact_registry/constants';
import InstructionsDrawer from 'ee/packages_and_registries/artifact_registry/components/instructions_drawer.vue';
import SetupDrawer from 'ee/packages_and_registries/artifact_registry/repositories/detail/setup_instructions/setup_drawer.vue';
import SetupSnippets from 'ee/packages_and_registries/artifact_registry/repositories/detail/setup_instructions/setup_snippets.vue';
import ToolSelector from 'ee/packages_and_registries/artifact_registry/repositories/detail/setup_instructions/tool_selector.vue';
import { buildRepositoryClientUrl } from 'ee/packages_and_registries/artifact_registry/utils';
import { CLIENT_BASE_URL, SLUG } from '../../../mock_data';

describe('ArtifactRegistrySetupDrawer', () => {
  let wrapper;

  const findDrawer = () => wrapper.findComponent(InstructionsDrawer);
  const findTabLinks = () => wrapper.findAll('[role="tab"]').wrappers.map((tab) => tab.text());
  const findSelector = () => wrapper.findComponent(ToolSelector);
  const findSnippets = () => wrapper.findAllComponents(SetupSnippets);

  const createComponent = ({ format = 'MAVEN', kind = 'HOSTED', open = true } = {}) => {
    wrapper = mountExtended(SetupDrawer, {
      propsData: { name: 'my-repository', format, kind, open },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
      stubs: {
        InstructionsDrawer: stubComponent(InstructionsDrawer, {
          template: '<div><slot /></div>',
        }),
      },
    });
  };

  describe('the drawer it renders', () => {
    beforeEach(() => createComponent());

    it('titles the shared drawer and passes its open state through', () => {
      expect(findDrawer().props()).toMatchObject({ title: 'Setup instructions', open: true });
    });

    it('closes when the drawer asks to be closed', () => {
      findDrawer().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('the tabs', () => {
    beforeEach(() => createComponent());

    it('offers Install before Publish on a hosted repository', () => {
      expect(findTabLinks()).toEqual(['Install', 'Publish']);
    });

    it('keeps the tablist to tabs, so the tool selector is not an invalid child of it', () => {
      expect(wrapper.find('[role="tablist"]').findComponent(ToolSelector).exists()).toBe(false);
      expect(findSelector().exists()).toBe(true);
    });

    it('gives each tab the section it names, for this repository', () => {
      expect(findSnippets().wrappers.map((s) => s.props())).toEqual([
        expect.objectContaining({
          name: 'my-repository',
          format: 'MAVEN',
          section: SETUP_SECTION_INSTALL,
        }),
        expect.objectContaining({
          name: 'my-repository',
          format: 'MAVEN',
          section: SETUP_SECTION_PUBLISH,
        }),
      ]);
    });
  });

  describe('on a remote repository', () => {
    beforeEach(() => createComponent({ kind: 'REMOTE' }));

    it('offers the Install tab alone', () => {
      expect(findTabLinks()).toEqual(['Install']);
    });

    it('renders the install section and nothing else', () => {
      expect(findSnippets().wrappers.map((snippet) => snippet.props('section'))).toEqual([
        SETUP_SECTION_INSTALL,
      ]);
    });

    it('keeps the tool selector, which the install snippets still read from', () => {
      expect(findSelector().props()).toMatchObject({ format: 'MAVEN', selected: 'maven' });
    });
  });

  describe('on a virtual repository', () => {
    it.each([
      ['MAVEN', 'maven'],
      ['NPM', 'npm'],
      ['DOCKER', 'docker'],
      ['OCI', 'docker'],
    ])(
      'offers the Install tab alone for a %s repository, on its first tool and its own URL',
      async (format, tool) => {
        createComponent({ kind: 'VIRTUAL', format });
        await nextTick();

        expect(findTabLinks()).toEqual(['Install']);
        expect(findSelector().props()).toMatchObject({ format, selected: tool });
        expect(findSnippets().wrappers.map((snippet) => snippet.props())).toEqual([
          expect.objectContaining({
            name: 'my-repository',
            format,
            section: SETUP_SECTION_INSTALL,
          }),
        ]);
        expect(wrapper.text()).toContain(
          buildRepositoryClientUrl({
            clientBaseUrl: CLIENT_BASE_URL,
            slug: SLUG,
            format,
            name: 'my-repository',
          }).replace('https://', ''),
        );
      },
    );
  });

  describe('the tool selector', () => {
    it.each([
      ['MAVEN', 'maven'],
      ['NPM', 'npm'],
      ['DOCKER', 'docker'],
      ['OCI', 'docker'],
    ])('starts a %s repository on its first tool', (format, tool) => {
      createComponent({ format });

      expect(findSelector().props()).toMatchObject({ format, selected: tool });
    });

    it('applies a chosen tool to both tabs at once', async () => {
      createComponent({ format: 'NPM' });

      findSelector().vm.$emit('select', 'pnpm');
      await nextTick();

      expect(findSnippets().wrappers.map((s) => s.props('tool'))).toEqual(['pnpm', 'pnpm']);
    });

    it('falls back rather than keeping a tool the new format cannot offer', async () => {
      createComponent({ format: 'DOCKER' });

      findSelector().vm.$emit('select', 'podman');
      await nextTick();
      await wrapper.setProps({ format: 'MAVEN' });

      expect(findSelector().props('selected')).toBe('maven');
    });

    it('starts again from the default each time the drawer opens', async () => {
      createComponent({ format: 'NPM' });

      findSelector().vm.$emit('select', 'yarn');
      await nextTick();

      await wrapper.setProps({ open: false });
      await wrapper.setProps({ open: true });

      expect(findSelector().props('selected')).toBe('npm');
    });
  });
});
