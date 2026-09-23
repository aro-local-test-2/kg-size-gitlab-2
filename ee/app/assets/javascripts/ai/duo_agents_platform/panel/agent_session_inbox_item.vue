<script>
import { formatAgentStatus } from 'ee/ai/duo_agents_platform/utils';
import { AGENT_PLATFORM_STATUS_BADGE } from 'ee/ai/duo_agents_platform/constants';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import { AGENT_SESSION_INBOX_STATUS_LABELS, STATUS_TEXT_CLASS } from './constants';
import InboxRow from './inbox_row.vue';

export default {
  name: 'AgentSessionInboxItem',
  components: { AgentStatusIcon, InboxRow },
  props: {
    item: {
      required: true,
      type: Object,
    },
  },
  computed: {
    statusLabel() {
      return (
        AGENT_SESSION_INBOX_STATUS_LABELS[this.item.status] ??
        formatAgentStatus(this.item.humanStatus)
      );
    },
    statusTextClass() {
      const { variant } = AGENT_PLATFORM_STATUS_BADGE[this.item.status] ?? {};
      return STATUS_TEXT_CLASS[variant] ?? STATUS_TEXT_CLASS.neutral;
    },
  },
};
</script>
<template>
  <inbox-row :item="item">
    <template #status>
      <agent-status-icon :status="item.status" :human-status="statusLabel" />
      <span
        class="gl-shrink-0 gl-text-sm gl-font-semibold"
        :class="statusTextClass"
        data-testid="item-status-label"
        >{{ statusLabel }}</span
      >
    </template>
  </inbox-row>
</template>
