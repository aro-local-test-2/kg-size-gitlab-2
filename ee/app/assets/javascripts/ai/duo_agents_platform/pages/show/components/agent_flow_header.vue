<script>
import { GlIcon, GlLink, GlSkeletonLoader, GlSprintf, GlTruncate } from '@gitlab/ui';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import AgentStatusBadge from 'ee/ai/shared/widgets/agent_status_badge.vue';
import AgentFlowTriggeredUser from '../../../components/common/agent_flow_triggered_user.vue';
import { WORKFLOW_TERMINAL_STATUSES } from '../../../constants';
import AgentSessionActions from './agent_session_actions.vue';

export default {
  name: 'AgentFlowHeader',
  components: {
    GlIcon,
    GlLink,
    GlSkeletonLoader,
    GlSprintf,
    GlTruncate,
    TimeAgoTooltip,
    AgentStatusBadge,
    AgentFlowTriggeredUser,
    AgentSessionActions,
  },
  props: {
    isLoading: {
      required: true,
      type: Boolean,
    },
    title: {
      required: false,
      type: String,
      default: '',
    },
    isSidePanelView: {
      type: Boolean,
      required: false,
      default: false,
    },
    status: {
      type: String,
      required: false,
      default: null,
    },
    humanStatus: {
      type: String,
      required: false,
      default: null,
    },
    createdAt: {
      type: String,
      required: false,
      default: '',
    },
    updatedAt: {
      type: String,
      required: false,
      default: '',
    },
    project: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    user: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    canUpdateWorkflow: {
      type: Boolean,
      required: false,
      default: false,
    },
    showDetailsToggle: {
      type: Boolean,
      required: false,
      default: false,
    },
    detailsExpanded: {
      type: Boolean,
      required: false,
      default: true,
    },
    detailsDrawerId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['cancel-session', 'toggle-details'],
  computed: {
    validUpdatedAt() {
      return this.validDate(this.updatedAt);
    },
    validStartedAt() {
      return this.validDate(this.createdAt);
    },
    isTerminalStatus() {
      return WORKFLOW_TERMINAL_STATUSES.includes(this.status);
    },
    showUpdatedAt() {
      return this.isTerminalStatus && Boolean(this.validUpdatedAt);
    },
    projectWebPath() {
      return this.project?.webPath;
    },
    projectLabel() {
      return this.project?.fullPath?.split('/').join(' / ');
    },
  },
  methods: {
    validDate(value) {
      if (!value) return null;
      const date = new Date(value);
      return Number.isNaN(date.getTime()) ? null : value;
    },
  },
};
</script>
<template>
  <div v-if="isLoading">
    <gl-skeleton-loader class="gl-px-4" :lines="1" :width="400" />
  </div>
  <header
    v-else-if="isSidePanelView"
    class="gl-sticky gl-top-0 gl-z-9999 gl-shrink-0 gl-bg-default gl-p-0"
  >
    <div
      class="drawer-title gl-border-b gl-flex gl-items-center gl-justify-start gl-px-4 gl-pb-3 gl-pt-2"
    >
      <div
        class="gl-flex gl-w-full gl-grow gl-flex-col gl-justify-center gl-gap-2 gl-text-sm gl-text-subtle"
      >
        <div class="gl-flex gl-justify-between">
          <span class="gl-flex gl-items-center gl-gap-4">
            <agent-status-badge v-if="status" :status="status" :human-status="humanStatus" />
            <span
              v-if="validUpdatedAt"
              class="gl-items-center gl-gap-1"
              data-testid="agent-flow-last-updated"
            >
              <gl-sprintf :message="s__('DuoAgentsPlatform|Updated %{timeago}')">
                <template #timeago>
                  <time-ago-tooltip :time="validUpdatedAt" />
                </template>
              </gl-sprintf>
            </span>
          </span>
          <agent-session-actions
            :status="status"
            :can-update-workflow="canUpdateWorkflow"
            :is-side-panel="isSidePanelView"
            @cancel-session="$emit('cancel-session')"
          />
        </div>
        <div class="gl-mt-3 gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <agent-flow-triggered-user :user="user" />
          <template v-if="projectLabel">
            <span aria-hidden="true" data-testid="project-separator">&middot;</span>
            <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-2">
              <gl-icon name="project" variant="subtle" :size="14" class="gl-shrink-0" />
              <gl-link
                v-if="projectWebPath"
                :href="projectWebPath"
                data-testid="agent-flow-project-name"
                class="gl-min-w-0 gl-text-inherit"
              >
                <gl-truncate
                  :text="projectLabel"
                  position="middle"
                  with-tooltip
                  class="hover:gl-underline"
                />
              </gl-link>
              <span v-else data-testid="agent-flow-project-name" class="gl-min-w-0">
                <gl-truncate :text="projectLabel" position="middle" with-tooltip />
              </span>
            </span>
          </template>
        </div>
      </div>
    </div>
  </header>
  <header v-else class="gl-border-b gl-flex gl-flex-col gl-gap-3 gl-pb-4 gl-pt-3">
    <div class="gl-flex gl-flex-row gl-justify-between">
      <h1 class="gl-heading-1 gl-m-0" data-testid="agent-flow-page-title">{{ title }}</h1>
      <agent-session-actions
        :status="status"
        :can-update-workflow="canUpdateWorkflow"
        :is-side-panel="isSidePanelView"
        :show-details-toggle="showDetailsToggle"
        :details-expanded="detailsExpanded"
        :details-drawer-id="detailsDrawerId"
        @cancel-session="$emit('cancel-session')"
        @toggle-details="$emit('toggle-details')"
      />
    </div>
    <div class="gl-flex gl-items-center gl-gap-3 gl-text-subtle">
      <agent-status-badge v-if="status" :status="status" :human-status="humanStatus" />
      <span v-if="showUpdatedAt" data-testid="agent-flow-last-updated">
        <gl-sprintf :message="s__('DuoAgentsPlatform|Updated %{timeago}')">
          <template #timeago>
            <time-ago-tooltip :time="validUpdatedAt" />
          </template>
        </gl-sprintf>
      </span>
      <span
        v-if="showUpdatedAt && validStartedAt"
        aria-hidden="true"
        data-testid="timestamp-separator"
        >&middot;</span
      >
      <span
        v-if="validStartedAt"
        class="gl-flex gl-items-center gl-gap-1"
        data-testid="agent-flow-started-at"
      >
        <gl-sprintf :message="s__('DuoAgentsPlatform|Started %{timeago} by %{user}')">
          <template #timeago>
            <time-ago-tooltip :time="validStartedAt" />
          </template>
          <template #user>
            <agent-flow-triggered-user :user="user" class="gl-pl-2" />
          </template>
        </gl-sprintf>
      </span>
    </div>
  </header>
</template>
