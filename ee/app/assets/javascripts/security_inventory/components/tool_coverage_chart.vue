<script>
import { GlChart } from '@gitlab/ui/src/charts';
import { TOOL_STATUS_CONFIG, TOOL_NOT_ENABLED } from '../constants';

const CHART_HEIGHT = 140;
const DIMMED_OPACITY = 0.3;

export default {
  name: 'ToolCoverageChart',
  components: {
    GlChart,
  },
  props: {
    segments: {
      type: Array,
      required: true,
      validator: (value) =>
        value.every(({ label, count, color, key }) => {
          return (
            typeof label === 'string' &&
            typeof color === 'string' &&
            Number.isFinite(count) &&
            typeof key === 'string'
          );
        }),
    },
  },
  emits: ['select-status', 'hover-status'],
  data() {
    return { chartInstance: null };
  },
  computed: {
    total() {
      return this.segments.reduce((sum, { count }) => sum + count, 0);
    },
    hasSelection() {
      return this.segments.some(({ isSelected }) => isSelected);
    },
    hoveredSegment() {
      return this.segments.find(({ isHovered }) => isHovered);
    },
    hoveredPercent() {
      if (!this.hoveredSegment || !this.total) return null;
      return `${Math.round((this.hoveredSegment.count / this.total) * 100)}%`;
    },
    chartData() {
      if (!this.total) {
        return [{ value: 1, itemStyle: { color: this.$options.emptyColor } }];
      }

      const hasFocus = this.hasSelection || Boolean(this.hoveredSegment);

      return this.segments
        .filter(({ count }) => count > 0)
        .map(({ key, label, count, color, isSelected, isHovered }) => ({
          key,
          name: label,
          value: count,
          itemStyle: {
            color,
            opacity: hasFocus && !isSelected && !isHovered ? DIMMED_OPACITY : 1,
          },
          // Pin native-hover emphasis to the segment's own colour at full
          // opacity so echarts does not apply its default highlight effect,
          // which caused a flicker when moving between slices. Vue-controlled
          // opacity above still handles the dim-others behaviour.
          emphasis: { itemStyle: { color, opacity: 1 } },
        }));
    },
    chartOptions() {
      return {
        tooltip: { show: false },
        // Always render the graphic with a stable `id`; toggle visibility via
        // the text string. `setOption` defaults to merge, so returning
        // `graphic: []` (or omitting the key) leaves the previous graphic on
        // the canvas — the centre percentage would stick after hover ended.
        graphic: [
          {
            id: 'hover-percent',
            type: 'text',
            left: 'center',
            top: 'middle',
            silent: true,
            style: {
              text: this.hoveredPercent ?? '',
              fontSize: 20,
              fontWeight: 'bold',
              fill: 'var(--gl-text-color-heading)',
              textAlign: 'center',
            },
          },
        ],
        series: [
          {
            type: 'pie',
            radius: ['62%', '92%'],
            padAngle: 2,
            label: { show: false },
            labelLine: { show: false },
            silent: !this.total,
            cursor: this.total ? 'pointer' : 'default',
            data: this.chartData,
          },
        ],
      };
    },
  },
  beforeDestroy() {
    this.chartInstance?.off('mouseover', this.onChartMouseOver);
  },
  methods: {
    selectSegment({ params }) {
      const { key } = this.chartData[params.dataIndex] ?? {};

      if (key) {
        this.$emit('select-status', key);
      }
    },
    chartCreated(chart) {
      this.chartInstance = chart;
      chart.on('mouseover', this.onChartMouseOver);
    },
    onChartMouseOver({ dataIndex }) {
      if (!this.total) return;
      const { key } = this.chartData[dataIndex] ?? {};
      if (key) this.$emit('hover-status', key);
    },
    onContainerMouseLeave() {
      this.$emit('hover-status', null);
    },
  },
  height: CHART_HEIGHT,
  emptyColor: TOOL_STATUS_CONFIG[TOOL_NOT_ENABLED].color,
};
</script>

<template>
  <div
    aria-hidden="true"
    :style="{ width: `${$options.height}px` }"
    data-testid="tool-coverage-chart"
    @mouseleave="onContainerMouseLeave"
  >
    <gl-chart
      :options="chartOptions"
      :height="$options.height"
      width="auto"
      @chart-item-clicked="selectSegment"
      @created="chartCreated"
    />
  </div>
</template>
