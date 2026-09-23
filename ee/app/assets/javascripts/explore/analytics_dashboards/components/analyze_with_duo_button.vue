<script>
import { s__, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_USER } from '~/graphql_shared/constants';
import {
  dateRangeVariables,
  interpolate,
  previousDateRange,
} from '~/analytics/analytics_dashboards/data_sources/glql';
import { resolveDateRangeFilter } from '~/explore/analytics_dashboards/components/utils';
import { DATE_RANGE_OPTION_LAST_30_DAYS } from '~/explore/analytics_dashboards/components/constants';
import {
  DASHBOARD_CONTEXT_CATEGORY,
  registerExternalContextProvider,
} from 'ee/ai/duo_agentic_chat/context/external_context_store';
import OpenAgenticChatButton from 'ee/ai/shared/widgets/open_agentic_chat_button.vue';

// eslint-disable-next-line @gitlab/require-i18n-strings
const DATA_ANALYST_AGENT = { name: 'Data Analyst' };

const BUTTON_OPTIONS = { category: 'secondary', variant: 'confirm' };

const TRACKING_EVENT_CLICK = 'click_analyze_with_duo_on_analytics_dashboard';

/* eslint-disable @gitlab/require-i18n-strings */
const CONTEXT_INSTRUCTIONS =
  'You are helping the user analyse the current dashboard. ' +
  'Use the panel queries above as your primary data source when answering questions if possible. ' +
  "When drilling into a number a panel shows, reuse that panel's filters verbatim, change only the aggregation, and mention which panel query you used. " +
  'If the question is not answerable by any of the queries, build your own query and communicate it to the user.';
/* eslint-enable @gitlab/require-i18n-strings */

export default {
  name: 'AnalyzeWithDuoButton',
  components: {
    OpenAgenticChatButton,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    namespaceFullPath: {
      type: String,
      required: false,
      default: '',
    },
    filters: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    panels: {
      type: Array,
      required: false,
      default: () => [],
    },
    isProject: {
      type: Boolean,
      required: false,
      default: false,
    },
    configPrompts: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  computed: {
    resourceId() {
      const { current_user_id: userId } = window.gon ?? {};

      return userId ? convertToGraphQLId(TYPENAME_USER, userId) : null;
    },
    dateRange() {
      return resolveDateRangeFilter(this.filters, DATE_RANGE_OPTION_LAST_30_DAYS);
    },
    dateVariables() {
      return dateRangeVariables(this.dateRange);
    },
    previousDateVariables() {
      return dateRangeVariables(previousDateRange(this.dateRange));
    },
    resolvedPanels() {
      return this.panels
        .map(({ title, visualization }) => ({
          title,
          glql: visualization?.data?.query?.glql,
        }))
        .filter(({ glql }) => Boolean(glql))
        .map(({ title, glql }) => ({ title, glql: interpolate(glql, this.dateVariables) }));
    },
    hasContext() {
      return Boolean(
        this.resourceId &&
        this.namespaceFullPath &&
        this.resolvedPanels.length &&
        this.configPrompts.length,
      );
    },
    predefinedPrompts() {
      const namespace = this.namespaceFullPath;

      return this.configPrompts.map((prompt) => sprintf(prompt, { namespace }, false));
    },
    dashboardContext() {
      if (!this.hasContext) return null;

      return {
        dashboard_scope: {
          full_path: this.namespaceFullPath,
          type: this.isProject ? 'project' : 'group',
        },
        date_range: {
          option: this.filters?.dateRangeOption ?? null,
          start_date: this.dateVariables.startDate,
          end_date: this.dateVariables.endDate,
          previous: {
            start_date: this.previousDateVariables.startDate,
            end_date: this.previousDateVariables.endDate,
          },
        },
        panels: this.resolvedPanels,
        additional_instructions: CONTEXT_INSTRUCTIONS,
      };
    },
  },
  mounted() {
    this.disposeContextProvider = registerExternalContextProvider(
      DASHBOARD_CONTEXT_CATEGORY,
      () => this.dashboardContext,
    );
  },
  beforeDestroy() {
    this.disposeContextProvider?.();
  },
  methods: {
    trackClick() {
      this.trackEvent(TRACKING_EVENT_CLICK, {
        label: this.isProject ? 'project' : 'group',
        value: this.resolvedPanels.length,
      });
    },
  },
  i18n: {
    buttonLabel: s__('AnalyticsDashboards|Analyze with Duo'),
    welcomeMessage: s__('AnalyticsDashboards|Ask me about the data on this dashboard.'),
  },
  DATA_ANALYST_AGENT,
  BUTTON_OPTIONS,
};
</script>
<template>
  <open-agentic-chat-button
    v-if="hasContext"
    :button-text="$options.i18n.buttonLabel"
    :resource-id="resourceId"
    :agent="$options.DATA_ANALYST_AGENT"
    :welcome-message="$options.i18n.welcomeMessage"
    :predefined-prompts="predefinedPrompts"
    :predefined-prompt-tracking-labels="configPrompts"
    :button-options="$options.BUTTON_OPTIONS"
    icon="duo-chat"
    @click="trackClick"
  />
</template>
