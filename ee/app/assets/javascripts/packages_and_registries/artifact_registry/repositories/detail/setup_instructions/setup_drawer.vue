<script>
import { GlTab, GlTabs } from '@gitlab/ui';
import {
  REPOSITORY_KIND_HOSTED,
  SETUP_INSTRUCTIONS_TITLE,
  SETUP_SECTION_INSTALL,
  SETUP_SECTION_PUBLISH,
  SETUP_TOOLS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import { s__ } from '~/locale';
import InstructionsDrawer from '../../../components/instructions_drawer.vue';
import SetupSnippets from './setup_snippets.vue';
import ToolSelector from './tool_selector.vue';

export default {
  name: 'ArtifactRegistrySetupDrawer',
  components: {
    GlTab,
    GlTabs,
    InstructionsDrawer,
    SetupSnippets,
    ToolSelector,
  },
  props: {
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    name: {
      type: String,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
    kind: {
      type: String,
      required: true,
    },
  },
  emits: ['close'],
  data() {
    return {
      selectedTool: null,
    };
  },
  computed: {
    isPublishable() {
      return this.kind === REPOSITORY_KIND_HOSTED;
    },
    tools() {
      return SETUP_TOOLS[this.format] ?? [];
    },
    activeTool() {
      const selected = this.tools.find(({ value }) => value === this.selectedTool);

      return selected?.value ?? this.tools[0]?.value ?? '';
    },
  },
  watch: {
    open(open) {
      if (open) this.selectedTool = null;
    },
  },
  i18n: {
    title: SETUP_INSTRUCTIONS_TITLE,
    install: s__('ArtifactRegistry|Install'),
    publish: s__('ArtifactRegistry|Publish'),
  },
  sections: {
    install: SETUP_SECTION_INSTALL,
    publish: SETUP_SECTION_PUBLISH,
  },
};
</script>

<template>
  <instructions-drawer :title="$options.i18n.title" :open="open" @close="$emit('close')">
    <gl-tabs class="!gl-p-0" :content-class="'gl-p-5'">
      <gl-tab :title="$options.i18n.install" data-testid="install-tab">
        <setup-snippets
          :name="name"
          :format="format"
          :tool="activeTool"
          :section="$options.sections.install"
        />
      </gl-tab>

      <gl-tab v-if="isPublishable" :title="$options.i18n.publish" data-testid="publish-tab">
        <setup-snippets
          :name="name"
          :format="format"
          :tool="activeTool"
          :section="$options.sections.publish"
        />
      </gl-tab>

      <template #toolbar-end>
        <tool-selector
          class="gl-ml-auto gl-mr-5 gl-self-center"
          :format="format"
          :selected="activeTool"
          @select="selectedTool = $event"
        />
      </template>
    </gl-tabs>
  </instructions-drawer>
</template>
