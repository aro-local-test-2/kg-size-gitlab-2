<script>
import { GlIcon, GlLink, GlSprintf, GlTooltipDirective } from '@gitlab/ui';
import HealthCheckCard from 'ee/vue_shared/components/health_check_card.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { s__, n__ } from '~/locale';
import getVerificationFeatureSettingsQuery from '../../graphql/queries/get_verification_feature_settings.query.graphql';
import AgenticChatVerificationCheck from './agentic_chat_verification_check.vue';
import NamespaceSelector from './namespace_selector.vue';
import {
  AGENTIC_CHAT_FEATURE,
  FUNCTIONAL_VERIFICATION_STATUS,
  MODEL_PROVIDERS,
  NOT_RUN_STATE,
} from './constants';
import { getModelConfigurationPath } from './utils';

export default {
  name: 'FunctionalVerificationsCard',
  components: {
    GlIcon,
    GlLink,
    GlSprintf,
    HealthCheckCard,
    TimeAgoTooltip,
    AgenticChatVerificationCheck,
    NamespaceSelector,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: {
    duoInstanceModelSelectionPath: { default: '' },
  },
  data() {
    return {
      expanded: false,
      agenticChatRun: NOT_RUN_STATE,
      aiFeatureSettings: {},
      selectedNamespace: null,
    };
  },
  apollo: {
    aiFeatureSettings: {
      query: getVerificationFeatureSettingsQuery,
      update(data) {
        const nodes = data.aiFeatureSettings?.nodes ?? [];

        return nodes.reduce((settings, { feature, provider, selfHostedModel }) => {
          let modelInfo;

          switch (provider) {
            case MODEL_PROVIDERS.SELF_HOSTED:
              modelInfo = { provider, name: selfHostedModel?.name ?? '' };
              break;
            case MODEL_PROVIDERS.DISABLED:
              modelInfo = { provider, name: '' };
              break;
            default:
              modelInfo = { provider: MODEL_PROVIDERS.GITLAB_MANAGED, name: '' };
          }

          return { ...settings, [feature]: modelInfo };
        }, {});
      },
      error() {
        this.aiFeatureSettings = null;
      },
    },
  },
  computed: {
    agenticChatModel() {
      return this.aiFeatureSettings?.[AGENTIC_CHAT_FEATURE] ?? null;
    },
    status() {
      return this.agenticChatRun?.state ?? FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN;
    },
    isRunning() {
      return this.status === FUNCTIONAL_VERIFICATION_STATUS.RUNNING;
    },
    isFailed() {
      return this.status === FUNCTIONAL_VERIFICATION_STATUS.FAILED;
    },
    isPassed() {
      return this.status === FUNCTIONAL_VERIFICATION_STATUS.PASSED;
    },
    failedCount() {
      return this.isFailed ? 1 : 0;
    },
    passedCount() {
      return this.isPassed ? 1 : 0;
    },
    lastRunAt() {
      return this.agenticChatRun?.checkedAt ? new Date(this.agenticChatRun.checkedAt) : null;
    },
    isSupportedModel() {
      return this.agenticChatModel?.provider === MODEL_PROVIDERS.SELF_HOSTED;
    },
    modelConfigurationPath() {
      return getModelConfigurationPath(this.duoInstanceModelSelectionPath);
    },

    isNamespaceSelected() {
      return Boolean(this.selectedNamespace);
    },
    collapsedStateUi() {
      if (!this.isNamespaceSelected) {
        return {
          icon: 'group',
          variant: 'subtle',
          message: s__('AiPowered|To get started, select a group'),
        };
      }

      if (!this.isSupportedModel) {
        return {
          icon: 'lock',
          variant: 'subtle',
          message: s__('AiPowered|Verification check supports only self-hosted models'),
        };
      }

      if (this.isRunning) {
        return { icon: 'status-running', variant: 'info', message: s__('AiPowered|Running') };
      }

      if (this.isFailed) {
        return {
          icon: 'error',
          variant: 'danger',
          message: s__('AiPowered|%{scope} · Last run %{timeAgo}'),
          scope: n__('AiPowered|%d check failed', 'AiPowered|%d checks failed', this.failedCount),
        };
      }

      if (this.isPassed) {
        return {
          icon: 'check-circle-filled',
          variant: 'success',
          message: s__('AiPowered|%{scope} · Last run %{timeAgo}'),
          scope: n__('AiPowered|%d check passed', 'AiPowered|%d checks passed', this.passedCount),
        };
      }

      return { icon: 'dash-circle', variant: 'subtle', message: s__('AiPowered|Not run') };
    },
  },
  methods: {
    toggleExpanded() {
      if (!this.isNamespaceSelected) return;

      this.expanded = !this.expanded;
    },
    onNamespaceSelected(namespace) {
      this.selectedNamespace = namespace;
      this.expanded = true;
    },
    onAgenticChatUpdated(run) {
      this.agenticChatRun = run;
    },
  },
};
</script>

<template>
  <health-check-card
    :title="s__('AiPowered|Functional verification checks')"
    :expanded="expanded"
    :expand-disabled="!isNamespaceSelected"
    content-id="functional-verifications-card"
    data-testid="functional-verifications-card"
    @toggle="toggleExpanded"
  >
    <template #expand-text>
      <template v-if="expanded">{{ __('Hide results') }}</template>
      <span v-else class="gl-flex gl-items-center gl-gap-2">
        <gl-icon :name="collapsedStateUi.icon" :variant="collapsedStateUi.variant" :size="14" />
        <gl-sprintf :message="collapsedStateUi.message">
          <template #scope>{{ collapsedStateUi.scope }}</template>
          <template #timeAgo><time-ago-tooltip :time="lastRunAt" /></template>
        </gl-sprintf>
      </span>
    </template>

    <template #actions>
      <namespace-selector
        :selected-namespace-id="selectedNamespace?.id"
        @select="onNamespaceSelected"
      />
      <gl-icon
        v-gl-tooltip="s__('AiPowered|Verifications do not consume GitLab Credits.')"
        name="information-o"
        variant="subtle"
        :size="16"
        data-testid="functional-verifications-credits-hint"
      />
    </template>

    <div
      v-if="!isSupportedModel"
      class="gl-border-b gl-flex gl-items-start gl-gap-3 gl-border-default gl-bg-subtle gl-px-5 gl-py-3 gl-text-sm gl-text-subtle"
      data-testid="self-hosted-only-notice"
    >
      <gl-icon name="lock" variant="subtle" :size="14" class="gl-mt-1 gl-shrink-0" />
      <span>
        <gl-sprintf
          :message="
            s__(
              'AiPowered|Functional verification checks support only self-hosted models. To turn on these checks, %{linkStart}configure a self-hosted model%{linkEnd}.',
            )
          "
        >
          <template #link="{ content }">
            <gl-link :href="modelConfigurationPath">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </span>
    </div>

    <agentic-chat-verification-check
      :model="agenticChatModel"
      :disabled="!isSupportedModel || !isNamespaceSelected"
      @updated="onAgenticChatUpdated"
    />
  </health-check-card>
</template>
