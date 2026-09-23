<script>
import { GlIcon } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { EMPTY_PLACEHOLDER } from '../constants';

export default {
  name: 'EnvironmentCard',
  components: {
    GlIcon,
    TimeAgoTooltip,
  },
  props: {
    environment: {
      type: Object,
      required: true,
    },
    agents: {
      type: Array,
      required: false,
      default: () => [],
    },
    isGridView: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  computed: {
    environmentRoute() {
      return {
        name: 'environments_show_route',
        params: { id: String(getIdFromGraphQLId(this.environment.id)) },
      };
    },
    latestFinishedRolloutEnvironment() {
      return this.environment.latestFinishedRolloutEnvironment ?? null;
    },
    release() {
      return this.latestFinishedRolloutEnvironment?.rollout?.versionSet?.name ?? EMPTY_PLACEHOLDER;
    },
    lastDeployedAt() {
      return this.latestFinishedRolloutEnvironment?.finishedAt ?? null;
    },
    deployedBy() {
      return (
        this.latestFinishedRolloutEnvironment?.rollout?.rolloutTransitions?.nodes?.[0]
          ?.principalUser?.username ?? EMPTY_PLACEHOLDER
      );
    },
    appsCount() {
      return this.environment.applicationsCount ?? 0;
    },
    latestEnvironmentDriverBinding() {
      const nodes = this.environment.environmentDriverBindings?.nodes || [];

      return nodes.reduce(
        (latest, node) => (!latest || node.version > latest.version ? node : latest),
        null,
      );
    },
    clusterAgentName() {
      const agentId = this.latestEnvironmentDriverBinding?.driverConfig?.cluster_agent_id;

      if (!agentId) {
        return EMPTY_PLACEHOLDER;
      }

      // driverConfig is opaque to the backend and stores the raw numeric ID the driver
      // schema asks for, while cdAvailableAgents returns global IDs.
      const agent = this.agents.find(
        (node) => String(getIdFromGraphQLId(node.id)) === String(agentId),
      );

      return agent?.name ?? EMPTY_PLACEHOLDER;
    },
  },
  EMPTY_PLACEHOLDER,
};
</script>

<template>
  <div
    class="gl-rounded-lg gl-border-1 gl-border-solid gl-border-subtle gl-p-4"
    :class="{ 'gl-w-48': isGridView }"
    data-testid="environment-card"
  >
    <div class="gl-flex gl-items-center gl-gap-3">
      <h2 class="gl-m-0 gl-truncate gl-text-base" :title="environment.name">
        <router-link
          :to="environmentRoute"
          class="gl-text-default hover:gl-no-underline"
          data-testid="environment-card-link"
          >{{ environment.name }}</router-link
        >
      </h2>
    </div>

    <div class="gl-mt-3 gl-flex gl-items-center gl-gap-4 gl-text-subtle">
      <span class="gl-flex gl-items-center gl-gap-2">
        <gl-icon name="kubernetes" />
        {{ __('Kubernetes') }}
      </span>
      <span class="gl-flex gl-items-center gl-gap-2" data-testid="environment-card-apps">
        <gl-icon name="applications" />
        {{ n__('%d app', '%d apps', appsCount) }}
      </span>
    </div>

    <div
      class="gl-mt-4 gl-flex gl-gap-6 gl-border-t-1 gl-border-t-subtle gl-pt-4 gl-border-t-solid"
    >
      <div>
        <div class="gl-text-xs gl-font-bold gl-uppercase gl-tracking-wider gl-text-subtle">
          {{ s__('ContinuousDeployment|Release') }}
        </div>
        <div class="gl-mt-1 gl-font-monospace gl-text-sm" data-testid="environment-card-release">
          {{ release }}
        </div>
      </div>
      <div>
        <div class="gl-text-xs gl-font-bold gl-uppercase gl-tracking-wider gl-text-subtle">
          {{ s__('ContinuousDeployment|Last deploy') }}
        </div>
        <div
          class="gl-mt-1 gl-font-monospace gl-text-sm"
          data-testid="environment-card-last-deploy"
        >
          <time-ago-tooltip v-if="lastDeployedAt" :time="lastDeployedAt" />
          <template v-else>{{ $options.EMPTY_PLACEHOLDER }}</template>
        </div>
      </div>
      <div class="gl-min-w-0">
        <div class="gl-text-xs gl-font-bold gl-uppercase gl-tracking-wider gl-text-subtle">
          {{ s__('ContinuousDeployment|By') }}
        </div>
        <div
          class="gl-mt-1 gl-truncate gl-font-monospace gl-text-sm"
          data-testid="environment-card-deployed-by"
        >
          {{ deployedBy }}
        </div>
      </div>
    </div>

    <div
      class="gl-mt-4 gl-flex gl-items-center gl-justify-between gl-gap-3 gl-border-t-1 gl-border-t-subtle gl-pt-4 gl-text-sm gl-border-t-solid"
    >
      <span class="gl-text-subtle">{{ s__('ContinuousDeployment|Cluster agent') }}</span>
      <span class="gl-truncate gl-font-monospace" data-testid="environment-card-cluster-agent">{{
        clusterAgentName
      }}</span>
    </div>
  </div>
</template>
