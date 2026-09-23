<script>
import ExtendedDashboardPanel from '~/vue_shared/components/customizable_dashboard/extended_dashboard_panel.vue';
import { s__, __ } from '~/locale';
import { formatDate } from '~/lib/utils/datetime_utility';
import {
  getStartOfWeek,
  nDaysAfter,
  nWeeksBefore,
} from '~/lib/utils/datetime/date_calculation_utility';
import { readFromUrl, writeToUrl } from 'ee/security_dashboard/utils/panel_state_url_sync';
import { formatMttrOverTimeSeries } from 'ee/security_dashboard/utils/chart_utils';
import projectMttrOverTime from 'ee/security_dashboard/graphql/queries/project_mttr_over_time.query.graphql';
import groupMttrOverTime from 'ee/security_dashboard/graphql/queries/group_mttr_over_time.query.graphql';
import organizationMttrOverTime from 'ee/security_dashboard/graphql/queries/organization_mttr_over_time.query.graphql';
import MttrOverTimeChart from './charts/mttr_over_time_chart.vue';
import PanelSeverityFilter from './panel_severity_filter.vue';
import PanelGroupBy from './panel_group_by.vue';

const PANEL_ID = 'mttrOverTime';
const GROUP_BY_DEFAULT = 'all';

const WEEKS_TO_SHOW = 12;

const NAMESPACE_CONFIG = {
  project: {
    query: projectMttrOverTime,
    pageLevelFilters: ['reportType', 'trackedRefIds'],
  },
  group: {
    query: groupMttrOverTime,
    pageLevelFilters: ['reportType', 'projectId', 'securityAttributesFilters'],
  },
  organization: {
    query: organizationMttrOverTime,
    pageLevelFilters: ['reportType', 'projectId'],
  },
};

export default {
  name: 'MttrOverTimePanel',
  components: {
    ExtendedDashboardPanel,
    MttrOverTimeChart,
    PanelSeverityFilter,
    PanelGroupBy,
  },
  inject: { fullPath: { default: null } },
  props: {
    namespace: {
      type: String,
      required: true,
      validator: (value) => Object.keys(NAMESPACE_CONFIG).includes(value),
    },
    filters: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      hasFetchError: false,
      mttrOverTime: [],
      severity: readFromUrl({
        panelId: PANEL_ID,
        paramName: 'severity',
        defaultValue: [],
      }),
      groupedBy: readFromUrl({
        panelId: PANEL_ID,
        paramName: 'groupBy',
        defaultValue: GROUP_BY_DEFAULT,
      }),
    };
  },
  apollo: {
    mttrOverTime: {
      query() {
        return this.config.query;
      },
      variables() {
        return this.baseQueryVariables;
      },
      update(data) {
        return data.namespace?.securityMetrics?.mttrOverTime || [];
      },
      error() {
        this.hasFetchError = true;
      },
      watchLoading(isLoading) {
        if (isLoading) {
          this.hasFetchError = false;
        }
      },
    },
  },
  computed: {
    config() {
      return NAMESPACE_CONFIG[this.namespace];
    },
    hasData() {
      return this.mttrOverTime.length > 0;
    },
    chartSeries() {
      return formatMttrOverTimeSeries(this.mttrOverTime, { groupBy: this.groupedBy });
    },
    baseQueryVariables() {
      const variables = {
        severity: this.severity,
        fullPath: this.fullPath,
        ...this.dateRange(),
      };

      this.config.pageLevelFilters
        .filter((filterKey) => this.filters[filterKey] !== undefined)
        .forEach((filterKey) => {
          variables[filterKey] = this.filters[filterKey];
        });

      return variables;
    },
  },
  watch: {
    severity(value) {
      writeToUrl({
        panelId: PANEL_ID,
        paramName: 'severity',
        value,
        defaultValue: [],
      });
    },
    groupedBy(value) {
      writeToUrl({
        panelId: PANEL_ID,
        paramName: 'groupBy',
        value,
        defaultValue: GROUP_BY_DEFAULT,
      });
    },
  },
  methods: {
    dateRange() {
      const startOfCurrentWeek = getStartOfWeek(new Date());

      return {
        startDate: formatDate(nWeeksBefore(startOfCurrentWeek, WEEKS_TO_SHOW - 1), 'isoDate'),
        endDate: formatDate(nDaysAfter(startOfCurrentWeek, 6), 'isoDate'),
      };
    },
  },
  i18n: {
    title: s__('SecurityReports|MTTR over time'),
    error: __('Something went wrong. Please try again.'),
    empty: __('No results found'),
  },
  tooltip: {
    description: s__(
      'SecurityReports|Mean time to remediation (MTTR) for vulnerabilities, shown as a weekly trend from Monday to Sunday. A vulnerability is remediated when it is resolved or no longer detected. The most recent week might be incomplete.',
    ),
  },
};
</script>

<template>
  <extended-dashboard-panel
    :title="$options.i18n.title"
    :loading="$apollo.queries.mttrOverTime.loading"
    :show-alert-state="hasFetchError"
    :tooltip="$options.tooltip"
  >
    <template #filters>
      <panel-severity-filter v-model="severity" class="gl-mr-2" />
      <panel-group-by v-model="groupedBy" show-all />
    </template>
    <template #body>
      <mttr-over-time-chart
        v-if="hasData"
        class="gl-h-full gl-w-full gl-p-2"
        :mttr-series="chartSeries.mttrSeries"
        :count-series="chartSeries.countSeries"
      />
      <p
        v-else
        class="gl-m-0 gl-flex gl-h-full gl-w-full gl-items-center gl-justify-center gl-p-0 gl-text-center"
        data-testid="mttr-over-time-empty-state"
      >
        <template v-if="hasFetchError">{{ $options.i18n.error }}</template>
        <template v-else>{{ $options.i18n.empty }}</template>
      </p>
    </template>
  </extended-dashboard-panel>
</template>
