<script>
// eslint-disable-next-line no-restricted-imports
import { mapActions } from 'vuex';
import { GlAlert } from '@gitlab/ui';
import { DuoChatThreads } from '@gitlab/duo-ui';
import getUserWorkflows from 'ee/ai/graphql/get_user_workflow.query.graphql';
import { fetchPolicies } from '~/lib/graphql';
import {
  getSessionStorageValue,
  removeSessionStorageValue,
  saveSessionStorageValue,
} from '~/lib/utils/local_storage';
import { getPreferredLocales } from '~/locale';
import { duoChatGlobalState } from 'ee/ai/state';
import { DUO_CURRENT_WORKFLOW_STORAGE_KEY } from 'ee/ai/constants';
import {
  AGENTIC_CHAT_NEW_ROUTE,
  AGENTIC_CHAT_SHOW_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { safeRouterPush } from 'ee/ai/duo_agents_platform/utils/router_utils';
import DuoChatDeleteThreadModal from 'ee/ai/components/duo_chat_delete_thread_modal.vue';
import { removeDraft } from 'ee/ai/utils/chat_draft_storage';
import { CHAT_THREADS_PER_PAGE } from '../constants';
import { workflowStreamFactory } from '../websocket/workflow_stream_factory';
import { ApolloUtils } from '../utils/apollo_utils';
import { clearThreadSnapshot } from '../utils/chat_thread_snapshot';
import { formatErrorMessage } from '../utils/error_handler';
import { captureExceptionForDuoChat } from '../observability/sentry_utils';

export default {
  name: 'DuoAgenticChatHistoryView',
  components: {
    GlAlert,
    DuoChatDeleteThreadModal,
    DuoChatThreads,
  },
  inheritAttrs: false,
  props: {
    // Supplied by the panel, and needed to name the draft key of a thread being deleted.
    userId: {
      type: String,
      required: false,
      default: null,
    },
  },
  apollo: {
    agenticWorkflows: {
      query: getUserWorkflows,
      variables() {
        return this.queryVariables;
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      // fetchMore ends with a reobserve; under network-only that refetches page
      // one and discards the merged pages, so later reads must come from cache.
      nextFetchPolicy: fetchPolicies.CACHE_FIRST,
      update(data) {
        return data?.duoWorkflowWorkflows?.edges?.map((edge) => edge.node) || [];
      },
      result({ data }) {
        this.pageInfo = data?.duoWorkflowWorkflows?.pageInfo ?? null;
      },
      error(err) {
        this.onError(err);
      },
    },
  },
  data() {
    return {
      agenticWorkflows: [],
      pageInfo: null,
      isLoadingMore: false,
      errorMessage: '',
      deleteModalVisible: false,
      pendingDeleteThreadId: null,
      isDeletingThread: false,
    };
  },
  computed: {
    queryVariables() {
      return {
        type: 'foundational_chat_agents',
        first: CHAT_THREADS_PER_PAGE,
        environment: 'WEB',
      };
    },
    isLoadingThreadList() {
      return this.$apollo.queries.agenticWorkflows.loading;
    },
    showThreadsSkeleton() {
      // vue-apollo flips `loading` during fetchMore too; keep the loaded pages
      // on screen and show the inline spinner instead of the skeleton.
      return this.isLoadingThreadList && !this.isLoadingMore;
    },
    hasNextPage() {
      return Boolean(this.pageInfo?.hasNextPage);
    },
    preferredLocale() {
      return getPreferredLocales();
    },
  },
  methods: {
    ...mapActions(['setMessages']),
    onError(err) {
      captureExceptionForDuoChat(err);
      this.errorMessage = formatErrorMessage(err);
    },
    async loadMoreThreads() {
      if (!this.hasNextPage || this.isLoadingMore) {
        return;
      }

      this.isLoadingMore = true;
      try {
        await this.$apollo.queries.agenticWorkflows.fetchMore({
          variables: { after: this.pageInfo.endCursor },
          updateQuery: (previousResult, { fetchMoreResult }) => {
            const previousEdges = previousResult?.duoWorkflowWorkflows?.edges ?? [];
            const knownIds = new Set(previousEdges.map((edge) => edge.node.id));
            // Cursors are offsets, so a thread created between page loads can
            // make the next page repeat the previous page's last node.
            const newEdges = (fetchMoreResult.duoWorkflowWorkflows?.edges ?? []).filter(
              (edge) => !knownIds.has(edge.node.id),
            );

            return {
              ...fetchMoreResult,
              duoWorkflowWorkflows: {
                ...fetchMoreResult.duoWorkflowWorkflows,
                edges: [...previousEdges, ...newEdges],
              },
            };
          },
        });
        // A page that loads after a failed one should not sit under the old error.
        this.errorMessage = '';
      } catch (err) {
        this.onError(err);
      } finally {
        this.isLoadingMore = false;
      }
    },
    removeThreadFromCache(threadId) {
      // Drop the edge from the cached list rather than refetching, which would
      // flash the skeleton. fetchMore merges from this cache entry, so a local
      // filter alone would let the deleted thread reappear on the next page.
      this.$apollo
        .getClient()
        .cache.updateQuery({ query: getUserWorkflows, variables: this.queryVariables }, (data) => {
          if (!data?.duoWorkflowWorkflows) {
            return undefined;
          }

          return {
            ...data,
            duoWorkflowWorkflows: {
              ...data.duoWorkflowWorkflows,
              edges: data.duoWorkflowWorkflows.edges.filter((edge) => edge.node.id !== threadId),
            },
          };
        });
    },
    async onNewChat() {
      // Mirror onThreadSelected: a stream and transcript from a previously
      // active thread outlive this component, so tear them down before the
      // state manager mounts on the new-chat route.
      workflowStreamFactory.getWorkflowStream().disconnect();
      this.setMessages([]);

      try {
        await safeRouterPush(
          this.$router,
          { name: AGENTIC_CHAT_NEW_ROUTE },
          { component: 'DuoAgenticChatHistoryView' },
        );
      } catch {
        // safeRouterPush already reported the failure to Sentry; skip the
        // focus signal so it doesn't fire at whatever stays mounted.
        return;
      }

      // The chat state manager watches this flag and focuses the prompt
      // textarea. Wait a tick so its children are rendered before signalling.
      await this.$nextTick();
      duoChatGlobalState.focusChatInput = true;
    },
    async onThreadSelected(thread) {
      // The workflow stream is factory-scoped, so a stream started for a
      // previously active thread survives this component. Disconnect it so the
      // chat view hydrates the selected thread instead of adopting the old
      // stream, mirroring the cleanup the state manager performed before the
      // thread list was extracted into its own route.
      workflowStreamFactory.getWorkflowStream().disconnect();

      // The message store is shared across routes; clear it so the chat view
      // doesn't flash the previous thread's transcript while the selected one
      // hydrates.
      this.setMessages([]);

      // The chat state manager reads the active workflow from session storage
      // when it mounts on the show route.
      saveSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY, { workflowId: thread.id });

      await safeRouterPush(
        this.$router,
        { name: AGENTIC_CHAT_SHOW_ROUTE },
        { component: 'DuoAgenticChatHistoryView' },
      ).catch(() => {});
    },
    clearStoredWorkflowIfDeleted(threadId) {
      // This view owns the delete flow, so it's the only place that can drop the
      // stored active workflow. Otherwise the Chat tab would remount the state
      // manager against a deleted thread.
      const stored = getSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY);
      if (stored?.exists && stored.value?.workflowId === threadId) {
        removeSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY);
      }
    },
    onDeleteThread(threadId) {
      // Confirm before deleting; the request runs from onConfirmDeleteThread.
      this.pendingDeleteThreadId = threadId;
      this.deleteModalVisible = true;
    },
    async onConfirmDeleteThread() {
      const threadId = this.pendingDeleteThreadId;
      if (!threadId) {
        return;
      }

      this.isDeletingThread = true;
      // Clear any error from a previous failed delete so a success doesn't leave
      // a stale message in the header.
      this.errorMessage = '';

      try {
        const success = await ApolloUtils.deleteWorkflow(this.$apollo, threadId);
        if (success) {
          this.removeThreadFromCache(threadId);
          clearThreadSnapshot(threadId);
          this.clearStoredWorkflowIfDeleted(threadId);
          removeDraft({ userId: this.userId, threadId });
        }
      } catch (err) {
        this.onError(err);
      } finally {
        this.isDeletingThread = false;
        this.deleteModalVisible = false;
        this.pendingDeleteThreadId = null;
      }
    },
  },
};
</script>
<template>
  <div class="gl-flex gl-min-h-0 gl-grow gl-flex-col">
    <div
      class="panel-content-inner gl-flex gl-flex-grow gl-flex-col gl-overscroll-contain gl-bg-inherit"
      data-testid="chat-history-view"
    >
      <gl-alert
        v-if="errorMessage"
        :dismissible="false"
        variant="danger"
        role="alert"
        data-testid="chat-error"
      >
        {{ errorMessage }}
      </gl-alert>
      <duo-chat-threads
        class="gl-mx-auto gl-w-full gl-max-w-4xl"
        data-testid="duo-chat-threads"
        :threads="agenticWorkflows"
        :preferred-locale="preferredLocale"
        :loading="showThreadsSkeleton"
        :has-next-page="hasNextPage"
        :loading-more="isLoadingMore"
        @new-chat="onNewChat"
        @select-thread="onThreadSelected"
        @delete-thread="onDeleteThread"
        @load-more="loadMoreThreads"
      />
    </div>
    <duo-chat-delete-thread-modal
      v-model="deleteModalVisible"
      :loading="isDeletingThread"
      @confirm="onConfirmDeleteThread"
    />
  </div>
</template>
