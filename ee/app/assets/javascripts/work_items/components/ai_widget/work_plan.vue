<script>
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import { __, s__, sprintf } from '~/locale';
import { clearDraft, getDraft, updateDraft } from '~/lib/utils/autosave';
import { visitUrl } from '~/lib/utils/url_utility';
import { AGENT_PLAN_PANEL, I18N_WORK_ITEM_ERROR_UPDATING } from '~/work_items/constants';
import { findAgentPlanWidget } from 'ee/work_items/utils';
import { writeAgentPlanToCache } from 'ee/work_items/graphql/cache_utils';
import updateWorkItemAgentPlanMutation from 'ee/work_items/graphql/update_work_item_agent_plan.mutation.graphql';
import workItemGenerateWorkplanMutation from 'ee/work_items/graphql/work_item_generate_workplan.mutation.graphql';
import workItemResumeWorkplanMutation from 'ee/work_items/graphql/work_item_resume_workplan.mutation.graphql';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { eventHub, QUEUE_CHAT_COMMAND, SHOW_NEW_CHAT, REFETCH_SESSIONS } from 'ee/ai/events/panel';
import WorkPlanInlineRow from './work_plan_inline_row.vue';
import WorkPlanPanel from './work_plan_panel.vue';
import {
  buildWorkPlanChatCommand,
  FLOW_ACTION_TIMEOUT_MS,
  TERMINAL_STATUS_CONFIRM_MS,
  GENERATION_STATUS_GENERATING,
  GENERATION_STATUS_NEEDS_INPUT,
  GENERATION_STATUSES_ACTIVE,
} from './constants';
import {
  parseWorkplanUrlState,
  buildWorkplanPageUrl,
  writeWorkplanUrl,
  clearWorkplanUrl,
} from './use_workplan_panel_state';

export default {
  name: 'WorkPlan',
  components: {
    WorkPlanInlineRow,
    WorkPlanPanel,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    fullPath: { default: '' },
    hasRemoteFlowsEnabled: { from: 'duoRemoteFlowsAvailability', default: false },
  },
  props: {
    workItem: {
      type: Object,
      required: true,
    },
    canUpdate: {
      type: Boolean,
      required: false,
      default: false,
    },
    workItemWebUrl: {
      type: String,
      required: false,
      default: '',
    },
    isInDrawer: {
      type: Boolean,
      required: false,
      default: false,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
    agentPlan: {
      type: Object,
      required: false,
      default: null,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['request-panel', 'refetch-plan', 'run-active'],
  data() {
    return {
      isEditing: false,
      isSaving: false,
      tmpContent: '',
      draftContent: '',
      pendingGenerateOpen: false,
      planLanded: false,
      runExpected: false,
      terminalConfirmTimeout: null,
      isFlowActionInFlight: false,
      flowActionTimeout: null,
      hasAwaitedInput: false,
    };
  },
  computed: {
    workItemId() {
      return this.workItem.id;
    },
    workItemIid() {
      return this.workItem.iid;
    },
    useWorkItemFeatures() {
      return Boolean(this.glFeatures?.workItemFeaturesField);
    },
    includeReadinessScore() {
      return Boolean(this.glFeatures?.workplanScore);
    },
    workItemType() {
      return this.workItem.workItemType.name;
    },
    content() {
      return this.agentPlan?.content || '';
    },
    contentHtml() {
      return this.agentPlan?.contentHtml || '';
    },
    hasSavedContent() {
      return Boolean(this.content);
    },
    generationStatus() {
      return this.agentPlan?.generationStatus;
    },
    canGenerateAsync() {
      return Boolean(this.glFeatures?.duoWorkplanAsyncFlow);
    },
    isFlowActive() {
      if (this.planLanded) {
        return false;
      }
      return this.runExpected || GENERATION_STATUSES_ACTIVE.includes(this.generationStatus);
    },
    isRunStarting() {
      return this.runExpected && !GENERATION_STATUSES_ACTIVE.includes(this.generationStatus);
    },
    generation() {
      return {
        status: this.generationStatus,
        hasAwaitedInput: this.hasAwaitedInput,
        actionInFlight: this.isFlowActionInFlight,
        isRunning: this.isFlowActive,
        isStarting: this.isRunStarting,
      };
    },
    planStorageKey() {
      return `work-plan-draft-${this.workItemId}`;
    },
  },
  watch: {
    // Immediate, because the parent owns the query and the status can already be set
    // on first render rather than arriving as a change.
    generationStatus: {
      immediate: true,
      handler(status, previousStatus) {
        // The status moving is what tells us the action landed, so it, not the
        // mutation returning, is what releases the button.
        if (previousStatus !== undefined && status !== previousStatus) {
          this.setFlowActionPending(false);
        }
        if (GENERATION_STATUSES_ACTIVE.includes(status)) {
          this.cancelTerminalConfirm();
        } else if (this.runExpected) {
          this.confirmTerminalStatus();
        }
        // GENERATING covers both the refinement and plan-writing passes, so a prior
        // NEEDS_INPUT is the only signal that the next one is the second pass.
        if (status === GENERATION_STATUS_NEEDS_INPUT) {
          this.hasAwaitedInput = true;
        }
        if (status === GENERATION_STATUS_GENERATING && !this.hasSavedContent) {
          this.onGenerateRequested();
        }
      },
    },
    isFlowActive: {
      immediate: true,
      handler(active) {
        this.$emit('run-active', active);
      },
    },
    // Writing the plan is the flow's last act and reaches us immediately, so new content
    // ends the run ahead of its status. Covers a regenerate too, where the plan is
    // replaced rather than appearing for the first time.
    content(newContent, previousContent) {
      if (newContent === previousContent) {
        return;
      }
      if (this.isFlowActive) {
        this.planLanded = true;
        this.runExpected = false;
        this.cancelTerminalConfirm();
      }

      // Open the panel now, never on the click itself, so the user lands on the
      // previewable plan rather than an empty or stale one.
      if (newContent && this.pendingGenerateOpen) {
        this.pendingGenerateOpen = false;
        if (!this.isInDrawer && !this.isPanelOpen) {
          // Sync the URL here too, so a refresh or shared link reopens the generated plan.
          writeWorkplanUrl({ editing: false });
          this.$emit('request-panel', AGENT_PLAN_PANEL);
        }
      }
    },
  },
  created() {
    const { content: storedDraft } = this.loadFromStorage();
    if (storedDraft) {
      this.draftContent = storedDraft;
    }
    if (!this.isInDrawer) {
      window.addEventListener('popstate', this.onPopState);
      this.syncPanelFromUrl({ canClose: false });
    }
  },
  beforeDestroy() {
    clearTimeout(this.flowActionTimeout);
    this.cancelTerminalConfirm();
    window.removeEventListener('popstate', this.onPopState);
  },
  methods: {
    persistField(key, value) {
      if (!key) return;
      if (value) {
        updateDraft(key, value);
      } else {
        clearDraft(key);
      }
    },
    loadFromStorage() {
      return {
        content: this.planStorageKey ? getDraft(this.planStorageKey) : null,
      };
    },
    clearStorage() {
      this.persistField(this.planStorageKey, null);
    },
    openWorkplanAt({ editing = false } = {}) {
      // In the drawer, opening the work plan requires
      // a full navigation to the work item details page.
      // Preserve the url to keep the intent after nav.
      if (this.isInDrawer && this.workItemWebUrl) {
        try {
          visitUrl(buildWorkplanPageUrl(this.workItemWebUrl, { editing }));
          return;
        } catch (e) {
          Sentry.captureException(e);
        }
      }
      this.isEditing = editing;
      writeWorkplanUrl({ editing });
      this.$emit('request-panel', AGENT_PLAN_PANEL);
    },
    openPanel() {
      if (this.isPanelOpen) {
        this.closePanel();
        return;
      }
      this.openWorkplanAt({ editing: false });
    },
    onCreateManually() {
      this.openWorkplanAt({ editing: true });
    },
    closePanel() {
      this.$emit('request-panel', null);
      clearWorkplanUrl();
      this.isEditing = false;
    },
    syncPanelFromUrl({ canClose = true } = {}) {
      const { requestsPanel, requestsEdit } = parseWorkplanUrlState();
      // The URL carries the edit intent, so mirror it whenever the panel is requested.
      if (requestsPanel) {
        this.isEditing = requestsEdit;
      }
      // URL and panel already are in sync, do nothing
      if (requestsPanel === this.isPanelOpen) {
        return;
      }
      // On initial load a missing param must not close a panel the parent opened.
      if (!requestsPanel && !canClose) {
        return;
      }
      // URL and panel are not in sync and so we open or close to match the URL.
      this.$emit('request-panel', requestsPanel ? AGENT_PLAN_PANEL : null);
    },
    onPopState() {
      this.syncPanelFromUrl();
    },
    onGenerateRequested() {
      if (this.isInDrawer) {
        return;
      }
      this.pendingGenerateOpen = true;
    },
    handleDraftChange(value) {
      this.draftContent = value || '';
      this.persistField(this.planStorageKey, value);
    },
    // Duo chat is taking over — drop any in-progress edit so the panel
    // re-renders against the soon-to-be-written content rather than
    // stomping the user's stale draft on top of it.
    onAgentHandoff() {
      if (this.isEditing) {
        this.handleCancelEdit();
      }
    },
    showUpdateError(error) {
      createAlert({
        message: sprintf(I18N_WORK_ITEM_ERROR_UPDATING, {
          workItemType: this.workItemType,
        }),
      });
      Sentry.captureException(error);
    },
    async mutateAgentPlanContent() {
      const { data } = await this.$apollo.mutate({
        mutation: updateWorkItemAgentPlanMutation,
        variables: {
          input: {
            id: this.workItemId,
            agentPlanWidget: { content: this.tmpContent },
          },
          useWorkItemFeatures: this.useWorkItemFeatures,
          includeReadinessScore: this.includeReadinessScore,
        },
        update: (cache, { data: result }) => {
          if (result?.workItemUpdate?.errors?.length === 0) {
            const updatedPlan = findAgentPlanWidget(result.workItemUpdate.workItem);
            if (!updatedPlan) return;

            writeAgentPlanToCache({
              cache,
              workItemId: this.workItemId,
              workItemIid: this.workItemIid,
              content: this.tmpContent,
              contentHtml: updatedPlan.contentHtml || '',
              aiPlanningEnabled: this.agentPlan?.aiPlanningEnabled ?? true,
              readinessScore: this.agentPlan?.readinessScore ?? null,
              generationStatus: this.generationStatus,
              useWorkItemFeatures: this.useWorkItemFeatures,
              includeReadinessScore: this.includeReadinessScore,
            });
          }
        },
      });
      if (data.workItemUpdate.errors.length) {
        throw new Error(data.workItemUpdate.errors.join('\n'));
      }
    },
    handleStartEdit() {
      this.isEditing = true;
    },
    handleCancelEdit() {
      this.isEditing = false;
      this.draftContent = '';
      this.persistField(this.planStorageKey, null);
      // Cancelling a brand-new create (nothing saved yet) dismisses the panel so
      // no empty workplan is left behind. An existing plan returns to the view.
      if (!this.hasSavedContent) {
        this.closePanel();
      }
    },
    async handleSave(content) {
      // Defence-in-depth: the panel already trims before emitting, but
      // trimming here too means any future caller (e.g. an automated
      // save from a Duo flow) can't accidentally persist whitespace-only
      // content and flip the inline-row status pill to "Ready".
      this.tmpContent = content?.trim() || '';
      this.isSaving = true;
      try {
        await this.mutateAgentPlanContent();
        this.isEditing = false;
        this.draftContent = '';
        this.persistField(this.planStorageKey, null);
      } catch (error) {
        this.showUpdateError(error);
      } finally {
        this.isSaving = false;
        this.tmpContent = '';
      }
    },
    // A terminal status is only believed once a later read still agrees, so a run that
    // momentarily reads as finished cannot end the UI's run state or stop polling.
    confirmTerminalStatus() {
      if (this.terminalConfirmTimeout) {
        return;
      }
      this.terminalConfirmTimeout = setTimeout(() => {
        this.terminalConfirmTimeout = null;
        if (!GENERATION_STATUSES_ACTIVE.includes(this.generationStatus)) {
          this.runExpected = false;
        }
      }, TERMINAL_STATUS_CONFIRM_MS);
    },
    cancelTerminalConfirm() {
      clearTimeout(this.terminalConfirmTimeout);
      this.terminalConfirmTimeout = null;
    },
    // Arms the watchdog alongside the flag, so the two can't drift apart and a
    // stale timer can't release an action started after it.
    setFlowActionPending(pending) {
      clearTimeout(this.flowActionTimeout);
      this.isFlowActionInFlight = pending;
      this.flowActionTimeout = pending
        ? setTimeout(() => {
            this.isFlowActionInFlight = false;
          }, FLOW_ACTION_TIMEOUT_MS)
        : null;
    },
    async runFlowMutation({ mutation, payloadKey, failureMessage }) {
      this.planLanded = false;
      this.runExpected = true;
      this.cancelTerminalConfirm();
      this.confirmTerminalStatus();
      this.setFlowActionPending(true);
      try {
        const { data } = await this.$apollo.mutate({
          mutation,
          variables: { input: { id: this.workItemId } },
        });

        // Service messages are written for the user, so surface them verbatim.
        const { errors } = data[payloadKey];
        if (errors.length) {
          createAlert({ message: errors.join('\n') });
          this.runExpected = false;
          this.setFlowActionPending(false);
          return;
        }

        // The action deliberately stays pending here. The run keeps its old status
        // for seconds after this returns, so releasing now re-offers the same
        // action; the `generationStatus` watcher releases it instead.
        this.$emit('refetch-plan');
        eventHub.$emit(REFETCH_SESSIONS);
      } catch (error) {
        createAlert({ message: failureMessage, captureError: true, error });
        this.runExpected = false;
        this.setFlowActionPending(false);
      }
    },
    handleGenerate() {
      return this.runFlowMutation({
        mutation: workItemGenerateWorkplanMutation,
        payloadKey: 'workItemGenerateWorkplan',
        failureMessage: s__('AgentPlan|Something went wrong while starting workplan generation.'),
      });
    },
    handleContinue() {
      return this.runFlowMutation({
        mutation: workItemResumeWorkplanMutation,
        payloadKey: 'workItemResumeWorkplan',
        failureMessage: s__('AgentPlan|Something went wrong while resuming workplan generation.'),
      });
    },
    handleRegenerate() {
      if (this.isEditing) {
        this.handleCancelEdit();
      }
      if (this.canGenerateAsync) {
        this.pendingGenerateOpen = true;
        this.closePanel();
        this.handleGenerate();
        return;
      }
      const command = buildWorkPlanChatCommand(this.workItemWebUrl);
      eventHub.$emit(SHOW_NEW_CHAT);
      eventHub.$emit(QUEUE_CHAT_COMMAND, {
        ...command,
        question: command.agenticPrompt,
        resourceId: this.workItemId,
      });
    },
    async handleDelete() {
      const confirmed = await confirmAction(
        s__(
          'AgentPlan|Are you sure you want to delete this workplan? This action cannot be undone.',
        ),
        {
          primaryBtnText: __('Delete'),
          primaryBtnVariant: 'danger',
        },
      );
      if (!confirmed) return;

      this.tmpContent = '';
      this.isSaving = true;
      this.clearStorage();
      try {
        await this.mutateAgentPlanContent();
      } catch (error) {
        this.showUpdateError(error);
      } finally {
        this.isSaving = false;
      }
    },
  },
};
</script>

<template>
  <div>
    <work-plan-inline-row
      :can-update="canUpdate"
      :is-panel-open="isPanelOpen"
      :is-loading="isLoading"
      :project-path="fullPath"
      :has-content="hasSavedContent"
      :has-remote-flows-enabled="hasRemoteFlowsEnabled"
      :work-item-id="workItemId"
      :work-item-iid="workItemIid"
      :work-item-type="workItemType"
      :work-item-web-url="workItemWebUrl"
      :generation="generation"
      :can-generate-async="canGenerateAsync"
      @open="openPanel"
      @create-manually="onCreateManually"
      @open-chat-request="onGenerateRequested"
      @open-chat-completed="onAgentHandoff"
      @generate="handleGenerate"
      @retry="handleGenerate"
      @continue="handleContinue"
    />
    <work-plan-panel
      :open="isPanelOpen"
      :work-item-id="workItemId"
      :work-item-iid="workItemIid"
      :work-item-type="workItemType"
      :work-item-web-url="workItemWebUrl"
      :has-remote-flows-enabled="hasRemoteFlowsEnabled"
      :saved-content="content"
      :saved-content-html="contentHtml"
      :draft-content="draftContent"
      :can-update="canUpdate"
      :is-editing="isEditing"
      :is-saving="isSaving"
      :is-loading="isLoading"
      :is-flow-active="isFlowActive"
      :is-action-in-flight="isFlowActionInFlight"
      :can-generate-async="canGenerateAsync"
      @start-edit="handleStartEdit"
      @cancel-edit="handleCancelEdit"
      @save="handleSave"
      @delete="handleDelete"
      @regenerate="handleRegenerate"
      @generate="handleGenerate"
      @draft-change="handleDraftChange"
      @close="closePanel"
    />
  </div>
</template>
