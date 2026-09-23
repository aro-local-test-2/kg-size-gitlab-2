<script>
import { GlButton, GlDisclosureDropdown, GlTooltipDirective } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import { s__ } from '~/locale';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import WorkPlanView from './work_plan_view.vue';
import WorkPlanEditor from './work_plan_editor.vue';
import { WORKPLAN_GOAL_PREFIX, GENERATE_MR_BUTTON_OPTIONS } from './constants';

export default {
  name: 'WorkPlanPanel',
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  components: {
    DynamicPanel,
    GlButton,
    GlDisclosureDropdown,
    MountingPortal,
    DuoWorkItemToMrAction,
    WorkPlanView,
    WorkPlanEditor,
  },
  inject: ['fullPath'],
  inheritAttrs: false,
  props: {
    open: {
      type: Boolean,
      required: true,
    },
    workItemId: {
      type: String,
      required: true,
    },
    canUpdate: {
      type: Boolean,
      required: true,
    },
    savedContent: {
      type: String,
      required: true,
    },
    savedContentHtml: {
      type: String,
      required: true,
    },
    draftContent: {
      type: String,
      required: true,
    },
    isEditing: {
      type: Boolean,
      required: true,
    },
    isSaving: {
      type: Boolean,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    isFlowActive: {
      type: Boolean,
      required: false,
      default: false,
    },
    isActionInFlight: {
      type: Boolean,
      required: false,
      default: false,
    },
    canGenerateAsync: {
      type: Boolean,
      required: false,
      default: false,
    },
    workItemIid: {
      type: [String, Number],
      required: true,
    },
    workItemType: {
      type: String,
      required: true,
    },
    workItemWebUrl: {
      type: String,
      required: true,
    },
    hasRemoteFlowsEnabled: {
      type: Boolean,
      required: true,
    },
  },
  emits: [
    'close',
    'save',
    'delete',
    'draft-change',
    'start-edit',
    'cancel-edit',
    'regenerate',
    'generate',
  ],
  computed: {
    isEditingAllowed() {
      return this.canUpdate && !this.isEditing;
    },
    hasSavedContent() {
      return Boolean(this.savedContent);
    },
    showGenerateMrAction() {
      return (
        this.hasRemoteFlowsEnabled && !this.isEditing && this.hasSavedContent && !this.isFlowActive
      );
    },
    panelHeading() {
      return s__('AgentPlan|Workplan');
    },
    // Both plan actions stay disabled for the whole run, not just the mutation: the menu
    // stays on screen throughout a regenerate because the previous plan keeps
    // `hasSavedContent` true. Regenerate would otherwise be re-offered mid-run, and a
    // delete would be silently undone when the run writes its plan back.
    areRunActionsDisabled() {
      return this.canGenerateAsync && (this.isFlowActive || this.isActionInFlight);
    },
    editMoreActions() {
      const actions = [];
      if (this.hasSavedContent) {
        actions.push({
          text: s__('AgentPlan|Regenerate workplan'),
          icon: 'tanuki-ai',
          extraAttrs: { disabled: this.areRunActionsDisabled },
          action: () => this.$emit('regenerate'),
        });
        actions.push({
          text: s__('AgentPlan|Delete workplan'),
          icon: 'remove',
          extraAttrs: { disabled: this.areRunActionsDisabled },
          action: () => this.$emit('delete'),
          variant: 'danger',
        });
      }
      return actions;
    },
  },
  mounted() {
    document.addEventListener('keydown', this.handleKeydown);
  },
  beforeDestroy() {
    document.removeEventListener('keydown', this.handleKeydown);
  },
  methods: {
    handleClose() {
      const active = document.activeElement;
      const activeTag = active?.tagName;
      if (
        document.body.classList.contains('modal-open') ||
        active?.closest('.js-editor') != null ||
        activeTag === 'INPUT' ||
        activeTag === 'TEXTAREA'
      ) {
        return;
      }
      this.$emit('close');
    },
    handleKeydown({ key }) {
      if (key === 'Escape' && this.open) {
        this.handleClose();
      }
    },
  },
  WORKPLAN_GOAL_PREFIX,
  generateMrButtonOptions: { ...GENERATE_MR_BUTTON_OPTIONS, size: 'small' },
};
</script>

<template>
  <mounting-portal v-if="open" mount-to="#contextual-panel-portal" append>
    <dynamic-panel
      data-testid="work-plan-panel"
      :should-fill-content="isEditing"
      @close="handleClose"
    >
      <template #header>
        <span
          class="gl-truncate gl-text-sm gl-font-bold gl-text-default"
          data-testid="work-plan-panel-title"
        >
          {{ panelHeading }}
        </span>
      </template>

      <template #actions>
        <duo-work-item-to-mr-action
          v-if="showGenerateMrAction"
          :project-path="fullPath"
          :work-item-iid="workItemIid"
          :work-item-type="workItemType"
          :work-item-web-url="workItemWebUrl"
          :additional-goal-context="$options.WORKPLAN_GOAL_PREFIX"
          :generate-mr-button-options="$options.generateMrButtonOptions"
          data-testid="panel-generate-mr-with-duo"
        />
        <template v-if="isEditingAllowed">
          <gl-button
            v-if="!isFlowActive"
            size="small"
            category="tertiary"
            data-testid="panel-edit-button"
            @click="$emit('start-edit')"
          >
            {{ s__('AgentPlan|Edit') }}
          </gl-button>
          <gl-disclosure-dropdown
            v-if="editMoreActions.length"
            v-gl-tooltip.bottom
            size="small"
            category="tertiary"
            icon="ellipsis_h"
            no-caret
            text-sr-only
            :toggle-text="__('More actions')"
            :title="__('More actions')"
            :items="editMoreActions"
            data-testid="panel-edit-more-actions"
          />
        </template>
      </template>

      <work-plan-editor
        v-if="isEditing"
        :saved-content="savedContent"
        :draft-content="draftContent"
        :is-saving="isSaving"
        @save="$emit('save', $event)"
        @cancel-edit="$emit('cancel-edit')"
        @draft-change="$emit('draft-change', $event)"
      />
      <work-plan-view
        v-else
        :is-loading="isLoading"
        :can-update="canUpdate"
        :saved-content="savedContent"
        :saved-content-html="savedContentHtml"
        :work-item-id="workItemId"
        :work-item-web-url="workItemWebUrl"
        :is-flow-active="isFlowActive"
        :can-generate-async="canGenerateAsync"
        @start-edit="$emit('start-edit')"
        @generate="$emit('generate')"
      />
    </dynamic-panel>
  </mounting-portal>
</template>
