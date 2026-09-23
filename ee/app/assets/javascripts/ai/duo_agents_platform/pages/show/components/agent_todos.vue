<script>
import { s__, sprintf } from '~/locale';
import { WORKFLOW_TERMINAL_STATUSES } from 'ee/ai/duo_agents_platform/constants';
import { WorkflowUtils } from 'ee/ai/duo_agentic_chat/utils/workflow_utils';
import TodoChecklist from '../../../components/common/todo_checklist.vue';

export default {
  name: 'AgentTodos',
  components: {
    TodoChecklist,
  },
  props: {
    status: {
      required: true,
      type: String,
    },
    duoMessages: {
      type: Array,
      required: false,
      default: () => [],
    },
    isSidePanelView: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    latestTodoToolInfo() {
      const messages = WorkflowUtils.normalizeDuoMessages(this.duoMessages);
      return WorkflowUtils.findLatestTodoToolInfo(messages);
    },
    showPlan() {
      return Boolean(this.latestTodoToolInfo);
    },
    todos() {
      return this.latestTodoToolInfo?.args?.todos || [];
    },
    todoProgressText() {
      return sprintf(s__('DuoAgentPlatform|%{completed} of %{total}'), {
        completed: this.todos.filter((todo) => todo.status === 'completed').length,
        total: this.todos.length,
      });
    },
    isTerminal() {
      return WORKFLOW_TERMINAL_STATUSES.includes(this.status);
    },
  },
};
</script>
<template>
  <div
    v-if="showPlan"
    class="gl-border-b gl-pb-5"
    :class="isSidePanelView ? '-gl-mx-[--container-padding-x] gl-px-[--container-padding-x]' : ''"
    data-testid="plan-section"
  >
    <div
      class="gl-flex gl-items-center gl-gap-3"
      :class="isSidePanelView ? 'gl-mb-2 gl-justify-between' : 'gl-mb-4'"
      data-testid="todos-header-row"
    >
      <component
        :is="isSidePanelView ? 'h4' : 'h2'"
        class="gl-my-0 gl-font-bold"
        :class="isSidePanelView ? 'gl-text-base' : 'gl-heading-2'"
        data-testid="todos-heading"
      >
        {{ s__('DuoAgentPlatform|Agent todos') }}
      </component>
      <span
        class="gl-text-subtle"
        :class="isSidePanelView ? 'gl-text-sm' : 'gl-text-base'"
        data-testid="todo-progress-summary"
      >
        {{ todoProgressText }}
      </span>
    </div>
    <todo-checklist :tool-info="latestTodoToolInfo" :flow-finished="isTerminal" :bordered="false" />
  </div>
</template>
