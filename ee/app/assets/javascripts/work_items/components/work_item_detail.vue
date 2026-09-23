<script>
import WorkItemDetail from '~/work_items/components/work_item_detail.vue';
import WorkItemAiWidget from 'ee/work_items/components/ai_widget/work_item_ai_widget.vue';
import WorkItemDecisionLog from 'ee/work_items/components/decision_log/work_item_decision_log.vue';
import WorkItemAgentSessions from 'ee/work_items/components/agent_sessions/index.vue';
import WorkItemPlanCta from 'ee/work_items/components/work_item_plan_cta.vue';
import { AGENT_PLAN_PANEL, DECISION_LOG_PANEL } from '~/work_items/constants';
import { findDecisionLogWidget, isAgentPlanEnabled } from 'ee/work_items/utils';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';

export default {
  name: 'WorkItemDetailEE',
  AGENT_PLAN_PANEL,
  DECISION_LOG_PANEL,
  components: {
    WorkItemDetail,
    WorkItemAiWidget,
    WorkItemAgentSessions,
    WorkItemDecisionLog,
    WorkItemPlanCta,
  },
  mixins: [glFeatureFlagsMixin(), glListenersMixin],
  inheritAttrs: false,
  methods: {
    isAgentPlanAvailable(workItem) {
      return isAgentPlanEnabled(workItem);
    },
    showDecisionLog(workItem) {
      return Boolean(this.glFeatures?.decisionLog) && Boolean(findDecisionLogWidget(workItem));
    },
    showPlanCta({ editMode, canUpdate, agentPlanWidget }) {
      return (
        !editMode && canUpdate && Boolean(agentPlanWidget) && !agentPlanWidget.aiPlanningEnabled
      );
    },
  },
};
</script>

<template>
  <work-item-detail v-bind="$attrs" v-on="glListeners()">
    <template #widgets-top="{ workItem, isDetailPanel, activePanel, editMode, requestPanel }">
      <!-- eslint-disable local-rules/vue-no-web-url -- Internal drawer-redirect URL; webUrl is what the work-item fragment already exposes. -->
      <work-item-ai-widget
        v-if="workItem && isAgentPlanAvailable(workItem) && !editMode"
        :work-item="workItem"
        :work-item-web-url="workItem.webUrl"
        :is-in-drawer="isDetailPanel"
        :is-panel-open="activePanel === $options.AGENT_PLAN_PANEL"
        :can-update="workItem.userPermissions?.updateWorkItem"
        class="gl-mb-5"
        @request-panel="requestPanel"
      />
      <!-- eslint-enable local-rules/vue-no-web-url -->
    </template>
    <template #header-actions="{ workItem, isDetailPanel, activePanel, requestPanel }">
      <!-- eslint-disable local-rules/vue-no-web-url -- Internal drawer-redirect URL; webUrl is what the work-item fragment already exposes. -->
      <work-item-decision-log
        v-if="showDecisionLog(workItem)"
        :work-item="workItem"
        :work-item-web-url="workItem.webUrl"
        :has-panel-portal="!isDetailPanel"
        :is-panel-open="activePanel === $options.DECISION_LOG_PANEL"
        @request-panel="requestPanel"
      />
      <!-- eslint-enable local-rules/vue-no-web-url -->
    </template>
    <template #plan-cta="{ workItem, canUpdate, editMode, agentPlanWidget, onError }">
      <work-item-plan-cta
        v-if="showPlanCta({ editMode, canUpdate, agentPlanWidget })"
        :work-item="workItem"
        @error="onError($event)"
      />
    </template>
    <template #widgets="{ workItem }">
      <work-item-agent-sessions v-if="workItem" :work-item-id="workItem.id" />
    </template>
  </work-item-detail>
</template>
