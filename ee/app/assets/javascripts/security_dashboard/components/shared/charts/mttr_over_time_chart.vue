<script>
import { camelCase } from 'lodash-es';
import { GlStackedColumnChart, GlChartSeriesLabel } from '@gitlab/ui/src/charts';
import { GL_COLOR_NEUTRAL_300, DATA_VIZ_BLUE_500 } from '@gitlab/ui/src/tokens/build/js/tokens';
import {
  listenSystemColorSchemeChange,
  removeListenerSystemColorSchemeChange,
} from '~/lib/utils/css_utils';
import { s__, n__ } from '~/locale';
import { getSeverityColors } from 'ee/security_dashboard/utils/chart_utils';
import { REPORT_TYPE_COLORS } from 'ee/security_dashboard/components/shared/vulnerability_report/constants';

const COUNT_BAR_COLOR = GL_COLOR_NEUTRAL_300;
const DEFAULT_LINE_COLOR = DATA_VIZ_BLUE_500;

export default {
  name: 'MttrOverTimeChart',
  components: {
    GlStackedColumnChart,
    GlChartSeriesLabel,
  },
  props: {
    mttrSeries: {
      type: Array,
      required: true,
    },
    countSeries: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      severityColors: {},
    };
  },
  computed: {
    lines() {
      return this.mttrSeries.map(({ name, data }) => ({ name, data }));
    },
    secondaryData() {
      return [{ name: this.countSeries.name, data: this.countSeries.data, type: 'bar' }];
    },
    groupBy() {
      return this.countSeries.data.map(([startDate]) => startDate);
    },
    customPalette() {
      // Ordered to match the chart's series: MTTR lines first, then the count bar (secondary axis).
      return [
        ...this.mttrSeries.map(({ id }) => this.seriesColor(id) || DEFAULT_LINE_COLOR),
        COUNT_BAR_COLOR,
      ];
    },
  },
  mounted() {
    this.setSeverityColors();
    listenSystemColorSchemeChange(this.setSeverityColors);
  },
  destroyed() {
    removeListenerSystemColorSchemeChange(this.setSeverityColors);
  },
  methods: {
    setSeverityColors() {
      this.severityColors = getSeverityColors();
    },
    seriesColor(seriesId) {
      const normalizedId = camelCase(seriesId);
      return this.severityColors[normalizedId] || REPORT_TYPE_COLORS[normalizedId];
    },
    isCountRow(seriesName) {
      return seriesName === this.countSeries.name;
    },
    hasNoRemediations(seriesData) {
      // The count bar is the week's filtered total, so zero means no remediation.
      const countEntry = seriesData.find(({ seriesName }) => this.isCountRow(seriesName));
      return countEntry?.value?.[1] === 0;
    },
    tooltipValue(seriesName, value) {
      const number = value?.[1];
      if (number == null) return s__('SecurityReports|None');
      if (this.isCountRow(seriesName)) return number;

      return n__('%d day', '%d days', number);
    },
  },
  chartOptions: {
    animation: false,
    yAxis: [
      {
        // eslint-disable-next-line @gitlab/require-i18n-strings
        axisLabel: { formatter: '{value}d' },
      },
      {
        minInterval: 1,
      },
    ],
    // Note: This is a workaround to remove the extra whitespace when the chart has no title
    // Once https://gitlab.com/gitlab-org/gitlab-services/design.gitlab.com/-/issues/2199 has been fixed, this can be removed
    grid: {
      left: '10px',
      right: '10px',
      bottom: '10px',
      top: '10px',
      containLabel: true,
    },
  },
};
</script>

<template>
  <gl-stacked-column-chart
    :lines="lines"
    :secondary-data="secondaryData"
    :group-by="groupBy"
    :option="$options.chartOptions"
    :custom-palette="customPalette"
    :include-legend-avg-max="false"
    x-axis-title=""
    y-axis-title=""
    presentation="tiled"
    x-axis-type="category"
    responsive
    height="auto"
    class="gl-h-full gl-w-full"
  >
    <template #tooltip-content="{ params }">
      <template v-if="params">
        <p
          v-if="hasNoRemediations(params.seriesData)"
          class="gl-m-0"
          data-testid="mttr-tooltip-no-remediations"
        >
          {{ s__('SecurityReports|No vulnerabilities remediated this week') }}
        </p>
        <div v-else>
          <div
            v-for="{ seriesName, color, borderColor, value } in params.seriesData"
            :key="seriesName"
            class="gl-flex gl-justify-between"
            :class="{ 'gl-border-t gl-mt-3 gl-border-t-default gl-pt-3': isCountRow(seriesName) }"
            data-testid="mttr-tooltip-row"
          >
            <gl-chart-series-label class="gl-mr-7 gl-text-sm" :color="borderColor || color">
              {{ seriesName }}
            </gl-chart-series-label>
            <span class="gl-font-bold">{{ tooltipValue(seriesName, value) }}</span>
          </div>
        </div>
      </template>
    </template>
  </gl-stacked-column-chart>
</template>
