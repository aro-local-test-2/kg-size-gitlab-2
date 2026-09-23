<script>
import Visibility from 'visibilityjs';
import { s__ } from '~/locale';
import { createAlert } from '~/alert';
import AgentSessionsList from 'ee/ai/shared/widgets/agent_sessions_list.vue';
import getDuoAgentSessionsOnWorkItemQuery from 'ee/ai/shared/widgets/graphql/get_duo_agent_sessions_on_work_item.query.graphql';
import duoAgentSessionsOnWorkItemUpdatedSubscription from 'ee/ai/shared/widgets/graphql/duo_agent_sessions_on_work_item.subscription.graphql';
import {
  eventHub,
  SHOW_SESSION,
  REFETCH_SESSIONS,
  SCROLL_TO_SESSIONS,
  consumeScrollToSessions,
} from 'ee/ai/events/panel';
import { WORKFLOW_TERMINAL_STATUSES } from 'ee/ai/duo_agents_platform/constants';
import {
  AGENT_SESSIONS_PAGE_SIZE,
  AGENT_SESSIONS_POLL_INTERVAL,
} from 'ee/ai/shared/widgets/constants';

export default {
  name: 'WorkItemAgentSessions',

  components: {
    AgentSessionsList,
  },
  props: {
    workItemId: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      allSessions: [],
      shouldScrollOnLoad: false,
    };
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.allSessions.loading;
    },
    hasActiveSession() {
      return this.allSessions.some(
        (session) => !WORKFLOW_TERMINAL_STATUSES.includes(session.status),
      );
    },
    sessionsVariables() {
      return {
        id: this.workItemId,
        first: AGENT_SESSIONS_PAGE_SIZE,
      };
    },
  },
  apollo: {
    allSessions: {
      query: getDuoAgentSessionsOnWorkItemQuery,
      variables() {
        return this.sessionsVariables;
      },
      skip() {
        return !this.workItemId;
      },
      update(data) {
        return data?.workItem?.features?.aiSession?.duoWorkflows?.nodes ?? [];
      },
      // An errored result still reaches this hook so it would
      // bring the banner back on every tick.
      result({ error, errors }) {
        if (!error && !errors?.length) {
          this.syncPolling();
        }
      },
      // Pushes on every status transition from any tab, page, or API call - this is
      // what makes a restarted session show up right away instead of on the next poll.
      subscribeToMore: {
        document: duoAgentSessionsOnWorkItemUpdatedSubscription,
        variables() {
          return this.sessionsVariables;
        },
        skip() {
          return !this.workItemId;
        },
      },
      error(err) {
        // Polling resumes on the next successful fetch, pushed update, or refetch.
        this.$apollo.queries.allSessions.stopPolling();

        createAlert({
          message:
            err?.message ||
            s__('DuoAgentPlatform|Failed to load agent sessions for this work item.'),
          captureError: true,
          error: err,
        });
      },
    },
  },
  watch: {
    allSessions(sessions) {
      if (this.shouldScrollOnLoad && sessions.length > 0) {
        this.$nextTick(() => this.scrollToSelf());
      }
    },
  },
  created() {
    eventHub.$on(SHOW_SESSION, this.refetchSessions);
    // A new session triggers no server push - that only fires on status transitions,
    // so without this the new row waits for the executor's first status report.
    eventHub.$on(REFETCH_SESSIONS, this.refetchSessions);
    eventHub.$on(SCROLL_TO_SESSIONS, this.requestScrollOnLoad);
    if (consumeScrollToSessions()) {
      this.requestScrollOnLoad();
    }
    this.visibilityId = Visibility.change(this.syncPolling);
  },
  beforeDestroy() {
    Visibility.unbind(this.visibilityId);
    eventHub.$off(SHOW_SESSION, this.refetchSessions);
    eventHub.$off(REFETCH_SESSIONS, this.refetchSessions);
    eventHub.$off(SCROLL_TO_SESSIONS, this.requestScrollOnLoad);
  },
  methods: {
    requestScrollOnLoad() {
      if (this.allSessions.length > 0) {
        this.$nextTick(() => this.scrollToSelf());
      } else {
        this.shouldScrollOnLoad = true;
      }
    },
    scrollToSelf() {
      this.$el?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      this.shouldScrollOnLoad = false;
    },
    refetchSessions() {
      this.$apollo.queries.allSessions.refetch();
    },
    // Workplan pushes don't cover other flow types (e.g. Developer flow), FF-off,
    // or websocket outages - gated on tab visibility so background tabs are free.
    syncPolling() {
      const { allSessions } = this.$apollo.queries;

      if (this.hasActiveSession && !Visibility.hidden()) {
        allSessions.startPolling(AGENT_SESSIONS_POLL_INTERVAL);
      } else {
        allSessions.stopPolling();
      }
    },
  },
};
</script>

<template>
  <agent-sessions-list :sessions="allSessions" :is-loading="isLoading" />
</template>
