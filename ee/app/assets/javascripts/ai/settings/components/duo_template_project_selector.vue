<script>
import { GlFormGroup, GlLink, GlSprintf } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { s__ } from '~/locale';
import ProjectSelect from '~/vue_shared/components/entity_select/project_select.vue';

export default {
  name: 'DuoTemplateProjectSelector',
  i18n: {
    sectionTitle: s__('Duo|Customize code review'),
    groupSectionDescription: s__(
      'Duo|GitLab Duo reads exclusion rules and custom instructions from the source project and applies them to code reviews across the group. For more information, see %{linkStart}custom review instructions%{linkEnd}.',
    ),
    instanceSectionDescription: s__(
      'Duo|GitLab Duo reads exclusion rules and custom instructions from the source project and applies them to code reviews across the instance. For more information, see %{linkStart}custom review instructions%{linkEnd}.',
    ),
    project: s__('Duo|Source project'),
    selectProject: s__('Duo|Select a project'),
  },
  components: {
    GlFormGroup,
    GlLink,
    GlSprintf,
    ProjectSelect,
  },
  inject: {
    rootNamespaceId: { default: null },
    isGroupSettings: { default: false },
  },
  props: {
    selectedProject: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['project-changed'],
  computed: {
    initialSelection() {
      if (!this.selectedProject) return null;

      return {
        value: String(this.selectedProject.id),
        text: this.selectedProject.nameWithNamespace || this.selectedProject.name,
      };
    },
    sectionDescription() {
      return this.isGroupSettings
        ? this.$options.i18n.groupSectionDescription
        : this.$options.i18n.instanceSectionDescription;
    },
  },
  methods: {
    onProjectSelected(item) {
      if (!item?.value) {
        this.$emit('project-changed', null);
        return;
      }

      // EntitySelector's watch fires with `initialSelectedItem` ({ value, text } only) as a
      // side effect when the user clicks reset - before the explicit @input({}) from onReset.
      // Real search results always include full API fields like `name`. Skip incomplete items
      // and let the subsequent @input({}) handle the clear.
      // Check `with incomplete items` in tests.
      if (!item.name && !item.name_with_namespace) return;

      this.$emit('project-changed', {
        id: parseInt(item.value, 10),
        name: item.name,
        nameWithNamespace: item.name_with_namespace,
        fullPath: item.full_path,
        avatarUrl: item.avatar_url,
      });
    },
  },
  docsPath: helpPagePath('user/duo_agent_platform/customize/review_instructions'),
};
</script>
<template>
  <div>
    <gl-form-group class="gl-mb-0">
      <h2 class="gl-heading-3 gl-mb-2 gl-mt-6">
        {{ $options.i18n.sectionTitle }}
      </h2>

      <p class="gl-text-subtle">
        <gl-sprintf :message="sectionDescription">
          <template #link="{ content }">
            <gl-link :href="$options.docsPath" target="_blank">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>

      <project-select
        :initial-selection="initialSelection"
        :group-id="rootNamespaceId"
        :label="$options.i18n.project"
        :empty-text="$options.i18n.selectProject"
        class="gl-mt-3"
        input-name="duo_template_project_id"
        input-id="duo_template_project_id"
        @input="onProjectSelected"
      />
    </gl-form-group>
  </div>
</template>
