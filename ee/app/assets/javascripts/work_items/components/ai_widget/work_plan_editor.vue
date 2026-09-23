<script>
import { isEmpty } from 'lodash-es';
import { GlButton } from '@gitlab/ui';
import MarkdownEditor from '~/vue_shared/components/markdown/markdown_editor.vue';
import EditorModeSwitcher from '~/vue_shared/components/markdown/editor_mode_switcher.vue';
import { EDITING_MODE_MARKDOWN_FIELD, EDITING_MODE_CONTENT_EDITOR } from '~/vue_shared/constants';
import { s__ } from '~/locale';
import namespacePathsQuery from '~/work_items/graphql/namespace_paths.query.graphql';

const RESTRICTED_TOOLBAR_ITEMS = ['full-screen'];
const SWITCHER_VALUE_MARKDOWN = 'markdown';
const SWITCHER_VALUE_RICH_TEXT = 'richText';

export default {
  name: 'WorkPlanEditor',
  components: {
    EditorModeSwitcher,
    GlButton,
    MarkdownEditor,
  },
  inject: ['fullPath'],
  props: {
    savedContent: {
      type: String,
      required: true,
    },
    draftContent: {
      type: String,
      required: true,
    },
    isSaving: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['save', 'cancel-edit', 'draft-change'],
  data() {
    return {
      tmpContent: this.draftContent || this.savedContent,
      markdownPaths: {},
      editorMode: EDITING_MODE_MARKDOWN_FIELD,
      formFieldProps: {
        id: 'agent-plan',
        name: 'agent-plan',
        'aria-label': s__('AgentPlan|Workplan'),
      },
    };
  },
  computed: {
    areMarkdownPathsLoaded() {
      return !isEmpty(this.markdownPaths);
    },
    nextEditorMode() {
      return this.editorMode === EDITING_MODE_MARKDOWN_FIELD
        ? EDITING_MODE_CONTENT_EDITOR
        : EDITING_MODE_MARKDOWN_FIELD;
    },
    editorSwitcherValue() {
      return this.editorMode === EDITING_MODE_MARKDOWN_FIELD
        ? SWITCHER_VALUE_MARKDOWN
        : SWITCHER_VALUE_RICH_TEXT;
    },
  },
  apollo: {
    markdownPaths: {
      query: namespacePathsQuery,
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        return data?.namespace?.markdownPaths || {};
      },
      skip() {
        return !this.fullPath;
      },
    },
  },
  methods: {
    toggleEditorMode() {
      this.$refs.markdownEditor?.onEditingModeChange(this.nextEditorMode);
    },
    onEditorModeSynced(mode) {
      this.editorMode = mode;
    },
    cancelEdit() {
      this.$emit('cancel-edit');
    },
    savePlan() {
      this.$emit('save', this.tmpContent?.trim() || '');
    },
    handleInput(value) {
      this.tmpContent = value;
      this.$emit('draft-change', value);
    },
  },
  RESTRICTED_TOOLBAR_ITEMS,
  EDITING_MODE_MARKDOWN_FIELD,
  EDITING_MODE_CONTENT_EDITOR,
};
</script>

<template>
  <div class="work-plan-editor common-note-form gl-flex gl-min-h-0 gl-flex-1 gl-flex-col">
    <markdown-editor
      v-if="areMarkdownPathsLoaded"
      ref="markdownEditor"
      :value="tmpContent"
      :render-markdown-path="markdownPaths.markdownPreviewPath"
      :uploads-path="markdownPaths.uploadsPath"
      :form-field-props="formFieldProps"
      :enable-autocomplete="false"
      autofocus
      immersive
      fill-container
      hide-mode-switcher
      enable-content-editor
      :restricted-tool-bar-items="$options.RESTRICTED_TOOLBAR_ITEMS"
      data-testid="work-plan-editor"
      @input="handleInput"
      @keydown.meta.enter="savePlan"
      @keydown.ctrl.enter="savePlan"
      @markdown-field="onEditorModeSynced($options.EDITING_MODE_MARKDOWN_FIELD)"
      @content-editor="onEditorModeSynced($options.EDITING_MODE_CONTENT_EDITOR)"
    >
      <template #header>
        <div class="gl-flex gl-items-center gl-justify-between gl-gap-2 gl-py-2 gl-pl-2 gl-pr-5">
          <editor-mode-switcher
            :value="editorSwitcherValue"
            data-testid="work-plan-editor-mode-switcher"
            @switch="toggleEditorMode"
          />
          <div class="gl-flex gl-gap-2">
            <gl-button
              :disabled="isSaving"
              size="small"
              data-testid="cancel-work-plan-button"
              @click="cancelEdit"
            >
              {{ __('Cancel') }}
            </gl-button>
            <gl-button
              variant="confirm"
              size="small"
              :loading="isSaving"
              data-testid="save-work-plan-button"
              @click="savePlan"
            >
              {{ __('Save changes') }}
            </gl-button>
          </div>
        </div>
      </template>
    </markdown-editor>
  </div>
</template>
