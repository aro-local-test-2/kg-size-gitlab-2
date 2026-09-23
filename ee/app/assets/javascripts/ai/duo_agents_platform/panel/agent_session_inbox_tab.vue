<script>
import { GlSkeletonLoader } from '@gitlab/ui';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import AgentFlowList from '../components/common/agent_flow_list.vue';
import AgentSessionCliInboxItem from './agent_session_cli_inbox_item.vue';
import AgentSessionInboxItem from './agent_session_inbox_item.vue';
import { isIdleCliSession } from './cli_sessions';

export default {
  name: 'AgentSessionInboxTab',
  components: {
    AgentFlowList,
    AgentSessionCliInboxItem,
    AgentSessionInboxItem,
    GlSkeletonLoader,
  },
  mixins: [glSlotsMixin],
  props: {
    testidPrefix: {
      required: true,
      type: String,
    },
    workflows: {
      required: true,
      type: Array,
    },
    pageInfo: {
      required: true,
      type: Object,
    },
    loading: {
      required: false,
      type: Boolean,
      default: false,
    },
    showEmptyState: {
      required: false,
      type: Boolean,
      default: false,
    },
  },
  emits: ['next-page', 'prev-page'],
  computed: {
    /* eslint-disable @gitlab/require-i18n-strings -- test ids, not user-facing copy */
    loadingTestid() {
      return `${this.testidPrefix}-loading`;
    },
    listTestid() {
      return `${this.testidPrefix}-flow-list`;
    },
    emptyStateTestid() {
      return `${this.testidPrefix}-empty-state`;
    },
    /* eslint-enable @gitlab/require-i18n-strings */
  },
  methods: {
    isIdleCliSession,
    // A tab that supplies an `empty-state` slot renders it; one that does not falls back to
    // the list's own zero-row copy. Methods rather than computed, because glSlots() is not
    // reactive and a cached computed would go stale if a consumer toggled the slot.
    showSlottedEmptyState() {
      return this.showEmptyState && Boolean(this.glSlots()['empty-state']);
    },
    showListEmptyState() {
      return this.showEmptyState && !this.glSlots()['empty-state'];
    },
  },
};
</script>
<template>
  <div>
    <div
      v-if="loading"
      class="gl-flex gl-w-full gl-flex-col gl-gap-5 gl-p-5"
      :data-testid="loadingTestid"
    >
      <gl-skeleton-loader :lines="2" :width="300" />
      <gl-skeleton-loader :lines="2" :width="300" />
      <gl-skeleton-loader :lines="2" :width="300" />
    </div>
    <div v-else-if="showSlottedEmptyState()" :data-testid="emptyStateTestid">
      <slot name="empty-state"></slot>
    </div>
    <agent-flow-list
      v-else
      :data-testid="listTestid"
      :show-empty-state="showListEmptyState()"
      :workflows="workflows"
      :workflows-page-info="pageInfo"
      @next-page="$emit('next-page')"
      @prev-page="$emit('prev-page')"
    >
      <template #row="{ item }">
        <agent-session-cli-inbox-item v-if="isIdleCliSession(item)" :item="item" />
        <agent-session-inbox-item v-else :item="item" />
      </template>
    </agent-flow-list>
  </div>
</template>
