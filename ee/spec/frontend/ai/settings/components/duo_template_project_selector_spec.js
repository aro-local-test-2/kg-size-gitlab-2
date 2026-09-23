import { GlFormGroup, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoTemplateProjectSelector from 'ee/ai/settings/components/duo_template_project_selector.vue';
import { helpPagePath } from '~/helpers/help_page_helper';
import ProjectSelect from '~/vue_shared/components/entity_select/project_select.vue';

describe('DuoTemplateProjectSelector', () => {
  let wrapper;

  const ROOT_NAMESPACE_ID = '42';

  const createWrapper = ({
    selectedProject = null,
    isGroupSettings = true,
    rootNamespaceId = ROOT_NAMESPACE_ID,
  } = {}) => {
    wrapper = shallowMountExtended(DuoTemplateProjectSelector, {
      propsData: { selectedProject },
      provide: { rootNamespaceId, isGroupSettings },
      stubs: { GlSprintf, GlLink },
    });
  };

  const findProjectSelect = () => wrapper.findComponent(ProjectSelect);
  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findSectionTitle = () => wrapper.find('h2');
  const findSectionDescription = () => wrapper.find('p');
  const findDocsLink = () => wrapper.findComponent(GlLink);

  describe('rendering', () => {
    it('renders a ProjectSelect component', () => {
      createWrapper();
      expect(findProjectSelect().exists()).toBe(true);
    });

    it('renders a GlFormGroup', () => {
      createWrapper();
      expect(findFormGroup().exists()).toBe(true);
    });

    it('renders the section title', () => {
      createWrapper();
      expect(findSectionTitle().text()).toBe('Customize code review');
    });

    it('renders the group section description mentioning group scope', () => {
      createWrapper({ isGroupSettings: true });
      expect(findSectionDescription().text()).toContain('code reviews across the group');
    });

    it('renders the instance section description mentioning instance scope', () => {
      createWrapper({ isGroupSettings: false });
      expect(findSectionDescription().text()).toContain('code reviews across the instance');
    });

    it('describes both exclusion rules and custom instructions in the description', () => {
      createWrapper();
      expect(findSectionDescription().text()).toContain(
        'reads exclusion rules and custom instructions from the source project',
      );
    });

    it('passes the empty text to ProjectSelect', () => {
      createWrapper();
      expect(findProjectSelect().props('emptyText')).toBe('Select a project');
    });

    it('renders a docs link in the description', () => {
      createWrapper();
      expect(findDocsLink().exists()).toBe(true);
      expect(findDocsLink().text()).toBe('custom review instructions');
      expect(findDocsLink().attributes('href')).toBe(
        helpPagePath('user/duo_agent_platform/customize/review_instructions'),
      );
    });

    it('passes rootNamespaceId as groupId to ProjectSelect', () => {
      createWrapper();
      expect(findProjectSelect().props('groupId')).toBe(ROOT_NAMESPACE_ID);
    });

    it('passes null groupId to ProjectSelect when rootNamespaceId is not provided', () => {
      createWrapper({ rootNamespaceId: null });
      expect(findProjectSelect().props('groupId')).toBeNull();
    });

    it('passes null initialSelection when no project is selected', () => {
      createWrapper();
      expect(findProjectSelect().props('initialSelection')).toBeNull();
    });

    it('passes initialSelection based on selectedProject when provided', () => {
      const selectedProject = {
        id: 10,
        name: 'My Project',
        nameWithNamespace: 'Group / My Project',
      };
      createWrapper({ selectedProject });

      expect(findProjectSelect().props('initialSelection')).toEqual({
        value: '10',
        text: 'Group / My Project',
      });
    });

    it('falls back to name when nameWithNamespace is absent', () => {
      createWrapper({ selectedProject: { id: 5, name: 'Only Name' } });

      expect(findProjectSelect().props('initialSelection')).toEqual({
        value: '5',
        text: 'Only Name',
      });
    });
  });

  describe('project-changed event', () => {
    it('emits project-changed with null when item has no value (reset)', async () => {
      createWrapper();
      await findProjectSelect().vm.$emit('input', {});

      expect(wrapper.emitted('project-changed')).toEqual([[null]]);
    });

    it('emits project-changed with null when input fires with undefined', async () => {
      createWrapper();
      await findProjectSelect().vm.$emit('input', undefined);

      expect(wrapper.emitted('project-changed')).toEqual([[null]]);
    });

    it('ignores incomplete items that have value/text but no API fields (initialSelectedItem side-effect)', async () => {
      createWrapper();
      await findProjectSelect().vm.$emit('input', { value: '99', text: 'Some Project' });

      expect(wrapper.emitted('project-changed')).toBeUndefined();
    });

    it('emits project-changed with mapped project when a full API item is selected', async () => {
      createWrapper();
      await findProjectSelect().vm.$emit('input', {
        value: '7',
        text: 'Namespace / Project',
        name: 'Project',
        name_with_namespace: 'Namespace / Project',
        full_path: 'namespace/project',
        avatar_url: 'https://example.com/avatar.png',
      });

      expect(wrapper.emitted('project-changed')).toEqual([
        [
          {
            id: 7,
            name: 'Project',
            nameWithNamespace: 'Namespace / Project',
            fullPath: 'namespace/project',
            avatarUrl: 'https://example.com/avatar.png',
          },
        ],
      ]);
    });

    describe('with incomplete items', () => {
      it('does not ignore items that have name but no name_with_namespace', async () => {
        createWrapper();
        await findProjectSelect().vm.$emit('input', {
          value: '99',
          name: 'Project',
          full_path: 'namespace/project',
        });

        expect(wrapper.emitted('project-changed')).toBeDefined();
      });

      it('does not ignore items that have name_with_namespace but no name', async () => {
        createWrapper();
        await findProjectSelect().vm.$emit('input', {
          value: '99',
          name_with_namespace: 'Namespace / Project',
          full_path: 'namespace/project',
        });

        expect(wrapper.emitted('project-changed')).toBeDefined();
      });
    });
  });
});
