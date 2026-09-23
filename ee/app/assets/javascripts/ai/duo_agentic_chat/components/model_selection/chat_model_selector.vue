<script>
import { GlDisclosureDropdown, GlToggle, GlTooltipDirective } from '@gitlab/ui';
import getAiChatAvailableModels from 'ee/ai/graphql/get_ai_chat_available_models.query.graphql';
import { GITLAB_DEFAULT_MODEL } from 'ee/ai/model_selection/constants';
import { fetchPolicies } from '~/lib/graphql';
import { s__ } from '~/locale';
import {
  getCurrentModel,
  getDefaultModel,
  getModel,
  getRecentModelRefs,
  recordRecentModelRef,
  saveModel,
  isModelSelectionDisabled as checkModelSelectionDisabled,
} from '../../utils/model_selection_utils';
import ChatModelSelectDropdown from './chat_model_select_dropdown.vue';

// Connected component boundary for model selection: owns the available-models
// query and the locally stored recents. Emits the resolved selection so the
// state manager can build the websocket URL and tracking context without
// touching that query.
export default {
  name: 'ChatModelSelector',
  components: {
    ChatModelSelectDropdown,
    GlDisclosureDropdown,
    GlToggle,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    projectId: {
      type: String,
      required: false,
      default: null,
    },
    namespaceId: {
      type: String,
      required: false,
      default: null,
    },
    rootNamespaceId: {
      type: String,
      required: false,
      default: null,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    showClassicChatButton: {
      type: Boolean,
      required: false,
      default: false,
    },
    agenticModeEnabled: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['change', 'switch-to-classic', 'error'],
  apollo: {
    availableModels: {
      query: getAiChatAvailableModels,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      skip() {
        // Non-agentic chat does not use model selection, so skip the query
        // entirely to avoid an unused request and leaking its error/pinned state.
        if (!this.agenticModeEnabled) return true;

        return !this.projectId && !this.namespaceId && !this.rootNamespaceId;
      },
      variables() {
        if (this.projectId) {
          return { projectId: this.projectId };
        }

        if (this.namespaceId) {
          return { namespaceId: this.namespaceId };
        }

        return { rootNamespaceId: this.rootNamespaceId };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      update(data) {
        const { selectableModels = [], defaultModel, pinnedModel } = data.aiChatAvailableModels;

        this.pinnedModel = pinnedModel?.ref
          ? {
              text: pinnedModel.name,
              value: pinnedModel.ref,
            }
          : null;

        return selectableModels.map(
          ({ ref, name, modelProvider, modelDescription, costIndicator }) => {
            const isDefault = ref === defaultModel?.ref;

            return {
              text: name,
              value: isDefault ? GITLAB_DEFAULT_MODEL : ref,
              ref,
              isDefault,
              provider: modelProvider,
              description: modelDescription,
              costIndicator,
            };
          },
        );
      },
      result() {
        this.emitChange();
      },
      error(err) {
        this.$emit('error', err);
      },
    },
  },
  data() {
    return {
      availableModels: [],
      recentModelRefs: getRecentModelRefs(),
      pinnedModel: null,
      selectedModel: null,
    };
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.availableModels.loading;
    },
    currentModel() {
      return this.isLoading
        ? null
        : getCurrentModel({
            availableModels: this.availableModels,
            pinnedModel: this.pinnedModel,
            selectedModel: this.selectedModel,
          });
    },
    defaultModel() {
      return getDefaultModel(this.availableModels);
    },
    isModelSelectionDisabled() {
      return checkModelSelectionDisabled(this.pinnedModel);
    },
    modelSelectionDisabledTooltipText() {
      return this.isModelSelectionDisabled
        ? s__('ModelSelection|Model has been pinned by an administrator.')
        : '';
    },
  },
  methods: {
    emitChange() {
      this.$emit('change', {
        currentModel: this.currentModel,
        defaultModel: this.defaultModel,
      });
    },
    onSelect(selectedModelValue) {
      const model = getModel(this.availableModels, selectedModelValue);

      if (!model) return;

      this.selectedModel = model;
      saveModel(model);
      this.emitChange();

      if (model.ref) {
        this.recentModelRefs = recordRecentModelRef(model.ref);
      }
    },
  },
};
</script>

<template>
  <div
    v-gl-tooltip
    :title="modelSelectionDisabledTooltipText"
    data-testid="model-dropdown-container"
  >
    <chat-model-select-dropdown
      v-if="agenticModeEnabled"
      :disabled="isModelSelectionDisabled || disabled"
      :is-loading="isLoading"
      :items="availableModels"
      :recent-refs="recentModelRefs"
      :selected-option="currentModel"
      :placeholder-dropdown-text="s__('ModelSelection|Select a model')"
      :show-classic-chat-button="showClassicChatButton"
      :classic-chat-button-disabled="disabled"
      :agentic-mode-enabled="agenticModeEnabled"
      @select="onSelect"
      @switch-to-classic="$emit('switch-to-classic', $event)"
    />
    <gl-disclosure-dropdown
      v-else
      :toggle-text="s__('DuoChat|Non-agentic chat')"
      category="tertiary"
      placement="bottom-end"
      :disabled="disabled"
      data-testid="non-agentic-dropdown"
    >
      <p
        class="gl-mb-0 gl-px-4 gl-py-3 gl-text-sm gl-text-subtle"
        data-testid="model-selection-unavailable-message"
      >
        {{ s__('DuoChat|Non-agentic chat does not use model selection.') }}
      </p>
      <div class="gl-border-t-1 gl-border-t-dropdown-divider gl-px-4 gl-py-3 gl-border-t-solid">
        <gl-toggle
          :value="false"
          :label="s__('DuoChat|Agentic chat')"
          :disabled="disabled"
          label-position="left"
          class="gl-w-full gl-justify-between"
          data-testid="switch-to-agentic-toggle"
          @change="$emit('switch-to-classic', $event)"
        >
          <template #label>
            <span class="gl-font-normal">{{ s__('DuoChat|Agentic chat') }}</span>
          </template>
        </gl-toggle>
      </div>
    </gl-disclosure-dropdown>
  </div>
</template>
