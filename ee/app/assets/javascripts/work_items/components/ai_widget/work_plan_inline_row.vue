<script>
import {
  GlButton,
  GlButtonGroup,
  GlDisclosureDropdown,
  GlIcon,
  GlLink,
  GlSprintf,
} from '@gitlab/ui';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import DuoChatQuickAction from 'ee/ai/shared/widgets/duo_chat_quick_action.vue';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import AiWidgetSegment from 'ee/vue_shared/components/work_items/ai_widget_segment.vue';
import {
  buildWorkPlanChatCommand,
  WORKPLAN_GOAL_PREFIX,
  GENERATE_MR_BUTTON_OPTIONS,
  GENERATION_STATUS_GENERATING,
  GENERATION_STATUS_NEEDS_INPUT,
  GENERATION_STATUS_FAILED,
  GENERATION_STATUSES,
  WORKPLAN_ACTION,
} from './constants';
import WorkPlanStatusBar from './work_plan_status_bar.vue';

export default {
  name: 'WorkPlanInlineRow',
  components: {
    AiWidgetSegment,
    GlButton,
    GlButtonGroup,
    GlIcon,
    GlLink,
    GlSprintf,
    HelpPopover,
    GlDisclosureDropdown,
    DuoChatQuickAction,
    DuoWorkItemToMrAction,
    WorkPlanStatusBar,
  },
  props: {
    hasContent: {
      type: Boolean,
      required: false,
      default: false,
    },
    canUpdate: {
      type: Boolean,
      required: false,
      default: false,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    workItemId: {
      type: String,
      required: true,
    },
    workItemIid: {
      type: String,
      required: false,
      default: null,
    },
    workItemType: {
      type: String,
      required: false,
      default: null,
    },
    workItemWebUrl: {
      type: String,
      required: false,
      default: '',
    },
    hasRemoteFlowsEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    projectPath: {
      type: String,
      required: false,
      default: '',
    },
    generation: {
      type: Object,
      required: false,
      default: () => ({}),
      validator: ({ status }) => status == null || GENERATION_STATUSES.includes(status),
    },
    canGenerateAsync: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: [
    'open',
    'create-manually',
    'generate',
    'open-chat-request',
    'open-chat-completed',
    'retry',
    'continue',
  ],
  computed: {
    helpPopoverOptions() {
      return {
        title: s__('AgentPlan|What is a workplan?'),
      };
    },
    workPlanChatCommand() {
      return buildWorkPlanChatCommand(this.workItemWebUrl);
    },
    isAwaitingInput() {
      return this.generation.status === GENERATION_STATUS_NEEDS_INPUT;
    },
    hasFailedGeneration() {
      return this.generation.status === GENERATION_STATUS_FAILED;
    },
    isFlowActive() {
      return this.generation.isRunning;
    },
    showAwaitingInputIcon() {
      return this.isAwaitingInput;
    },
    notStartedStatus() {
      return {
        label: this.canUpdate ? s__('AgentPlan|Not yet created') : s__('AgentPlan|No workplan'),
        variant: 'neutral',
      };
    },
    statusByGenerationStatus() {
      return {
        [GENERATION_STATUS_GENERATING]: {
          // A saved plan means the run is past its review pass, same as a resumed run,
          // so only a run with neither reports that it is still reviewing.
          label:
            this.generation.hasAwaitedInput || this.hasContent
              ? s__('AgentPlan|Generating workplan...')
              : s__('AgentPlan|Reviewing work item...'),
          variant: 'info',
        },
        [GENERATION_STATUS_NEEDS_INPUT]: {
          label: s__('AgentPlan|Awaiting input'),
          variant: 'warning',
        },
        [GENERATION_STATUS_FAILED]: {
          label: s__('AgentPlan|Generation failed'),
          variant: 'error',
        },
      };
    },
    status() {
      // An active run wins over content: on a regenerate the previous plan is still
      // saved, so its presence must not mask the run in progress.
      if (this.generation.isStarting) {
        return { label: s__('AgentPlan|Preparing to generate...'), variant: 'info' };
      }
      if (this.isFlowActive) {
        return this.statusByGenerationStatus[this.generation.status];
      }
      if (this.hasContent) {
        return { label: s__('AgentPlan|Ready for review'), variant: 'success' };
      }
      return this.statusByGenerationStatus[this.generation.status] ?? this.notStartedStatus;
    },
    showWorkplanToggle() {
      return this.hasContent && !this.isFlowActive;
    },
    showCreateWorkPlanAction() {
      return (
        !this.isLoading &&
        !this.hasContent &&
        this.canUpdate &&
        !this.isFlowActive &&
        !this.hasFailedGeneration
      );
    },
    showRetryAction() {
      return this.hasFailedGeneration && !this.hasContent && this.canUpdate;
    },
    showContinueAction() {
      return this.isAwaitingInput && this.canUpdate;
    },
    primaryAction() {
      if (this.showContinueAction) return WORKPLAN_ACTION.CONTINUE;
      if (this.showWorkplanToggle) return WORKPLAN_ACTION.VIEW;
      if (this.showRetryAction) return WORKPLAN_ACTION.RETRY;
      if (this.showCreateWorkPlanAction) return WORKPLAN_ACTION.CREATE;
      return WORKPLAN_ACTION.NONE;
    },
    showGenerateMrAction() {
      return this.hasRemoteFlowsEnabled && this.hasContent && this.canUpdate && !this.isFlowActive;
    },
  },
  createWorkplanDropdownItems: [
    {
      text: s__('AgentPlan|Create manually'),
      extraAttrs: {
        'data-testid': 'create-workplan-dropdown-item',
      },
    },
  ],
  duoQuickAction: {
    tracking: { label: 'create_work_plan' },
    buttonOptions: { size: 'medium' },
  },
  WORKPLAN_GOAL_PREFIX,
  generateMrButtonOptions: GENERATE_MR_BUTTON_OPTIONS,
  workplanHelpPath: helpPagePath('user/work_items/workplan'),
  WORKPLAN_ACTION,
};
</script>

<template>
  <div
    data-testid="work-plan-inline-row"
    class="gl-relative gl-flex gl-w-fit gl-flex-wrap gl-items-stretch gl-justify-between gl-gap-x-6 gl-gap-y-4 gl-rounded-2xl"
  >
    <div class="gl-flex gl-gap-4">
      <div class="gl-flex gl-flex-row gl-items-stretch gl-gap-4">
        <work-plan-status-bar :variant="status.variant" :aria-label="status.label" />

        <ai-widget-segment :label="s__('AgentPlan|Workplan')">
          <template #label-append>
            <help-popover
              v-if="!hasContent && !isFlowActive"
              :options="helpPopoverOptions"
              class="gl-inline-flex"
            >
              <gl-sprintf
                :message="
                  s__(
                    'AgentPlan|A workplan breaks a work item into clear, ordered steps that guide implementation. Create one manually, or generate it with GitLab Duo. %{linkStart}Learn more%{linkEnd}.',
                  )
                "
              >
                <template #link="{ content }">
                  <gl-link :href="$options.workplanHelpPath" target="_blank">{{ content }}</gl-link>
                </template>
              </gl-sprintf>
            </help-popover>
          </template>
          <span class="gl-inline-flex gl-items-center gl-gap-2 gl-text-subtle">
            <gl-icon
              v-if="showAwaitingInputIcon"
              name="status"
              :size="14"
              variant="warning"
              data-testid="awaiting-input-icon"
            />
            {{ status.label }}
          </span>
        </ai-widget-segment>
      </div>
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
        <gl-button
          v-if="primaryAction === $options.WORKPLAN_ACTION.VIEW"
          :aria-pressed="String(isPanelOpen)"
          category="secondary"
          data-testid="open-work-plan-button"
          @click="$emit('open')"
        >
          {{ __('View') }}
        </gl-button>
        <gl-button
          v-else-if="primaryAction === $options.WORKPLAN_ACTION.CONTINUE"
          :loading="generation.actionInFlight"
          data-testid="continue-workplan-button"
          @click="$emit('continue')"
        >
          {{ s__('AgentPlan|Continue') }}
        </gl-button>
        <gl-button
          v-else-if="primaryAction === $options.WORKPLAN_ACTION.RETRY"
          :loading="generation.actionInFlight"
          data-testid="retry-workplan-button"
          @click="$emit('retry')"
        >
          {{ s__('AgentPlan|Try again') }}
        </gl-button>
        <gl-button-group v-else-if="primaryAction === $options.WORKPLAN_ACTION.CREATE">
          <gl-button
            v-if="canGenerateAsync"
            :loading="generation.actionInFlight"
            data-testid="inline-generate-button"
            @click="$emit('generate')"
          >
            {{ s__('AgentPlan|Generate') }}
          </gl-button>
          <duo-chat-quick-action
            v-else
            :resource-id="workItemId"
            :button-text="s__('AgentPlan|Generate')"
            :command="workPlanChatCommand"
            :tracking-info="$options.duoQuickAction.tracking"
            :button-options="$options.duoQuickAction.buttonOptions"
            data-testid="inline-generate-with-duo-button"
            @click="$emit('open-chat-request')"
            @chat-opened="$emit('open-chat-completed')"
          />
          <gl-disclosure-dropdown
            :items="$options.createWorkplanDropdownItems"
            :toggle-text="s__('AgentPlan|More options')"
            text-sr-only
            placement="bottom-end"
            data-testid="create-workplan-dropdown"
            @action="$emit('create-manually')"
          />
        </gl-button-group>
        <duo-work-item-to-mr-action
          v-if="showGenerateMrAction"
          :project-path="projectPath"
          :work-item-iid="workItemIid"
          :work-item-type="workItemType"
          :work-item-web-url="workItemWebUrl"
          :additional-goal-context="$options.WORKPLAN_GOAL_PREFIX"
          :generate-mr-button-options="$options.generateMrButtonOptions"
          data-testid="generate-mr-with-duo"
        />
      </div>
    </div>
  </div>
</template>
