<script>
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';
import DuoWorkflowAction from './duo_workflow_action.vue';

export default {
  name: 'DuoWorkItemToMrAction',
  components: {
    DuoWorkflowAction,
  },
  mixins: [glListenersMixin],
  agentPrivileges: [1, 2, 3, 4, 5],
  SOURCE: 'work_item_to_merge_request',
  props: {
    generateMrButtonOptions: {
      type: Object,
      required: false,
      default: () => ({ size: 'medium', variant: 'default', category: 'primary' }),
    },
    projectPath: {
      type: String,
      required: true,
    },
    workItemIid: {
      type: [String, Number],
      required: true,
    },
    workItemType: {
      type: String,
      required: false,
      default: 'issue',
    },
    workItemWebUrl: {
      type: String,
      required: true,
    },
    additionalGoalContext: {
      type: String,
      required: false,
      default: '',
    },
  },
  computed: {
    goal() {
      const username = window.gon?.current_username || '';
      const resourceName = this.workItemType?.toLowerCase() || 'issue';
      /* eslint-disable @gitlab/require-i18n-strings -- LLM prompt content sent to Duo Developer agent, not user-facing UI */
      const baseGoal = [
        `@${username} assigned you to solve the following ${resourceName}: ${this.workItemWebUrl}`,
        '',
        'Fetch the details and understand the problem thoroughly before writing any code. Consider what might be causing the issue and where in the codebase the relevant logic lives. If there are multiple possible approaches, reason about the tradeoffs and pick the simplest one that fully addresses the issue. Implement your solution, verify it works, then create a merge request with your changes.',
        '',
        `When you have completed your work, @mention @${username} in a comment on the issue to notify them. Assign @${username} as the assignee of the merge request unless told differently.`,
      ].join('\n');
      /* eslint-enable @gitlab/require-i18n-strings */

      if (this.additionalGoalContext) {
        return `${this.additionalGoalContext}\n\n${baseGoal}`;
      }
      return baseGoal;
    },
  },
};
</script>
<template>
  <duo-workflow-action
    :project-path="projectPath"
    :hover-message="s__('DuoAgentPlatform|Implement work item with GitLab Duo')"
    :goal="goal"
    workflow-definition="developer/v1"
    :agent-privileges="$options.agentPrivileges"
    :work-item-iid="workItemIid"
    :size="generateMrButtonOptions.size"
    :variant="generateMrButtonOptions.variant"
    :category="generateMrButtonOptions.category"
    :source="$options.SOURCE"
    v-bind="$attrs"
    v-on="glListeners()"
  >
    <slot>{{ s__('DuoAgentPlatform|Implement') }}</slot>
  </duo-workflow-action>
</template>
