<script>
import { GlDrawer } from '@gitlab/ui';
import { PanelBreakpointInstance } from '~/panel_breakpoint_instance';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import infoToggleStatesQuery from 'ee/ai/graphql/get_ai_panel_info_toggle_states.query.graphql';
import { AGENT_PLATFORM_STATUS_FAILED } from 'ee/ai/duo_agents_platform/constants';
import { toggleInfoToggle } from 'ee/ai/graphql';
import NoCreditsBanner from '../../../components/common/no_credits_banner.vue';
import UsageBillingForbiddenBanner from '../../../components/common/usage_billing_forbidden_banner.vue';
import AgentFlowHeader from './agent_flow_header.vue';
import AgentFlowDetailsPanel from './agent_flow_details_panel.vue';
import AgentFlowDetailsOverlay from './agent_flow_details_overlay.vue';
import AgentTodos from './agent_todos.vue';
import AgentActivityLogs from './agent_activity_logs.vue';
import AgentFlowErrorAlert from './agent_flow_error_alert.vue';
import AgentFlowLinkedItems from './agent_flow_linked_items.vue';

export default {
  name: 'AgentFlowDetails',
  components: {
    AgentFlowHeader,
    AgentFlowDetailsPanel,
    AgentFlowDetailsOverlay,
    AgentTodos,
    AgentActivityLogs,
    AgentFlowErrorAlert,
    AgentFlowLinkedItems,
    NoCreditsBanner,
    UsageBillingForbiddenBanner,
    GlDrawer,
  },
  inject: {
    isSidePanelView: { default: false },
    creditsAvailable: { default: true },
    billingForbidden: { default: false },
  },
  props: {
    isLoading: {
      required: true,
      type: Boolean,
    },
    status: {
      required: true,
      type: String,
    },
    humanStatus: {
      required: true,
      type: String,
    },
    agentFlowDefinition: {
      required: true,
      type: String,
    },
    modelName: {
      type: String,
      required: false,
      default: '',
    },
    modelIdentifier: {
      type: String,
      required: false,
      default: '',
    },
    flowVersion: {
      type: String,
      required: false,
      default: '',
    },
    aiCatalogItemPath: {
      type: String,
      required: false,
      default: '',
    },
    title: {
      required: true,
      type: String,
    },
    duoMessages: {
      type: Array,
      required: true,
    },
    allExecutorUrls: {
      type: Array,
      required: false,
      default: () => [],
    },
    createdAt: {
      type: String,
      required: true,
    },
    updatedAt: {
      type: String,
      required: true,
    },
    project: {
      type: Object,
      required: true,
    },
    user: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    workflowId: {
      type: String,
      required: true,
    },
    canUpdateWorkflow: {
      type: Boolean,
      required: true,
    },
    summary: {
      type: String,
      required: false,
      default: '',
    },
    workItem: {
      type: Object,
      required: false,
      default: null,
    },
    mergeRequest: {
      type: Object,
      required: false,
      default: null,
    },
    workItemLinks: {
      type: Array,
      required: false,
      default: () => [],
    },
    mergeRequestLinks: {
      type: Array,
      required: false,
      default: () => [],
    },
    noteLinks: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['cancel-session'],
  apollo: {
    infoToggleStates: {
      query: infoToggleStatesQuery,
      result({ data }) {
        this.infoToggleStates = data?.infoToggleStates ?? {};
      },
    },
  },
  data() {
    return {
      infoToggleStates: {},
      isErrorDismissed: false,
      isWideLayout: PanelBreakpointInstance.isDesktop(),
      isDetailsExpanded: PanelBreakpointInstance.isDesktop(),
      detailsOpener: null,
      drawerHeaderHeight: getContentWrapperHeight(),
    };
  },
  computed: {
    detailsDrawerId() {
      return `session-details-info-drawer-${this.workflowId}`;
    },
    isPageView() {
      return !this.isSidePanelView;
    },
    isDetailsDrawer() {
      return this.isPageView && !this.isWideLayout;
    },
    isInfoVisible() {
      return this.infoToggleStates[`ai_panel:${this.workflowId}`] ?? false;
    },
    detailsOverlayProps() {
      return {
        isLoading: this.isLoading,
        workflowId: this.workflowId,
        project: this.project,
        agentFlowDefinition: this.agentFlowDefinition,
        flowVersion: this.flowVersion,
        aiCatalogItemPath: this.aiCatalogItemPath,
        allExecutorUrls: this.allExecutorUrls,
        modelName: this.modelName,
        modelIdentifier: this.modelIdentifier,
      };
    },
    detailsPanelProps() {
      return {
        isLoading: this.isLoading,
        agentFlowDefinition: this.agentFlowDefinition,
        aiCatalogItemPath: this.aiCatalogItemPath,
        flowVersion: this.flowVersion,
        modelName: this.modelName,
        modelIdentifier: this.modelIdentifier,
        createdAt: this.createdAt,
        project: this.project,
        updatedAt: this.updatedAt,
        allExecutorUrls: this.allExecutorUrls,
        user: this.user,
        sessionId: this.workflowId,
      };
    },
    hasDuoMessages() {
      return Boolean(this.duoMessages.length);
    },
    sessionFailed() {
      return this.status === AGENT_PLATFORM_STATUS_FAILED;
    },
    isBillingForbidden() {
      return !this.creditsAvailable && this.billingForbidden;
    },
    showErrorAlert() {
      return this.sessionFailed && !this.isErrorDismissed && !this.isBillingForbidden;
    },
  },
  DRAWER_Z_INDEX,
  mounted() {
    if (this.isPageView) {
      PanelBreakpointInstance.addBreakpointListener(this.syncDetailsToLayout);
    }
  },
  beforeDestroy() {
    if (this.isPageView) {
      PanelBreakpointInstance.removeBreakpointListener(this.syncDetailsToLayout);
    }
  },
  methods: {
    dismissError() {
      this.isErrorDismissed = true;
    },
    toggleInfoOverlay() {
      toggleInfoToggle(this.workflowId, 'ai_panel');
    },
    toggleDetails() {
      if (!this.isDetailsExpanded) {
        this.detailsOpener = document.activeElement;
      }
      this.isDetailsExpanded = !this.isDetailsExpanded;
    },
    closeDetailsDrawer() {
      this.isDetailsExpanded = false;
      this.$nextTick(() => this.detailsOpener?.focus());
    },
    syncDetailsToLayout() {
      const isWideLayout = PanelBreakpointInstance.isDesktop();
      if (isWideLayout !== this.isWideLayout) {
        this.isDetailsExpanded = isWideLayout;
      }
      this.isWideLayout = isWideLayout;
    },
  },
};
</script>
<template>
  <div :class="{ 'gl-flex gl-h-full gl-flex-col': isSidePanelView }">
    <agent-flow-header
      :is-loading="isLoading"
      :title="title"
      :is-side-panel-view="isSidePanelView"
      :status="status"
      :human-status="humanStatus"
      :created-at="createdAt"
      :updated-at="updatedAt"
      :project="project"
      :user="user"
      :can-update-workflow="canUpdateWorkflow"
      :show-details-toggle="isDetailsDrawer"
      :details-expanded="isDetailsExpanded"
      :details-drawer-id="detailsDrawerId"
      @cancel-session="$emit('cancel-session')"
      @toggle-details="toggleDetails"
    />
    <usage-billing-forbidden-banner v-if="isBillingForbidden" />
    <no-credits-banner v-else-if="!creditsAvailable" />
    <agent-flow-error-alert
      v-if="showErrorAlert"
      :has-messages="hasDuoMessages"
      :error-summary="summary"
      @dismiss="dismissError"
    />
    <div
      class="gl-flex"
      :class="{
        'gl-flex-col gl-px-[--container-padding-x]': isSidePanelView,
        'gl-flex-row gl-justify-between gl-gap-7': isPageView,
      }"
      data-testid="agent-flow-details-wrapper"
    >
      <div class="gl-flex gl-min-h-0 gl-min-w-0 gl-grow gl-flex-col gl-gap-5 gl-pt-5">
        <agent-todos
          :duo-messages="duoMessages"
          :status="status"
          :is-side-panel-view="isSidePanelView"
        />
        <agent-flow-linked-items
          :work-item-links="workItemLinks"
          :merge-request-links="mergeRequestLinks"
          :note-links="noteLinks"
          :work-item="workItem"
          :merge-request="mergeRequest"
        />
        <agent-activity-logs
          class="gl-overflow-auto"
          :is-loading="isLoading"
          :duo-messages="duoMessages"
          :created-at="createdAt"
          :status="status"
          :updated-at="updatedAt"
          :user="user"
        />
      </div>
      <agent-flow-details-panel
        v-if="!isSidePanelView && !isDetailsDrawer"
        class="gl-mt-3 gl-pt-3"
        :class="{ 'gl-min-w-37': isPageView }"
        data-testid="session-details-rail"
        v-bind="detailsPanelProps"
      />
    </div>
    <gl-drawer
      v-if="isDetailsDrawer"
      :id="detailsDrawerId"
      :open="isDetailsExpanded"
      :header-height="drawerHeaderHeight"
      :z-index="$options.DRAWER_Z_INDEX"
      variant="sidebar"
      header-sticky
      :aria-label="s__('DuoAgentPlatform|Session details')"
      class="gl-max-w-37 !gl-rounded-none"
      data-testid="session-details-info-drawer"
      @close="closeDetailsDrawer"
    >
      <template #title>
        <div>
          <h2 class="gl-sr-only">{{ s__('DuoAgentPlatform|Session details') }}</h2>
        </div>
      </template>
      <agent-flow-details-panel v-bind="detailsPanelProps" />
    </gl-drawer>
    <agent-flow-details-overlay
      v-if="isSidePanelView"
      :visible="isInfoVisible"
      v-bind="detailsOverlayProps"
      @toggle="toggleInfoOverlay"
    />
  </div>
</template>
