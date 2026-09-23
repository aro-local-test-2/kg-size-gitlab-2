import { GlChart } from '@gitlab/ui/src/charts';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ToolCoverageChart from 'ee/security_inventory/components/tool_coverage_chart.vue';

describe('ToolCoverageChart', () => {
  let wrapper;

  const segments = [
    { key: 'SUCCESS', label: 'Enabled', count: 788, color: 'var(--green-500)' },
    { key: 'FAILED', label: 'Failed', count: 299, color: 'var(--red-500)' },
    { key: 'STALE', label: 'Stale', count: 0, color: 'var(--gl-color-neutral-600)' },
    {
      key: 'NOT_CONFIGURED',
      label: 'Not enabled',
      count: 127,
      color: 'var(--gl-color-neutral-200)',
    },
  ];

  const findChart = () => wrapper.findComponent(GlChart);
  const findSeries = () => findChart().props('options').series[0];
  const findSeriesData = () => findSeries().data;
  const findGraphic = () => findChart().props('options').graphic;
  const clickSlice = (dataIndex) =>
    findChart().vm.$emit('chart-item-clicked', { params: { dataIndex } });

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(ToolCoverageChart, {
      propsData: { segments, ...propsData },
    });
  };

  it('renders a donut chart with an inner radius', () => {
    createComponent();

    expect(findSeries()).toMatchObject({
      type: 'pie',
      radius: ['62%', '92%'],
    });
  });

  it('renders one slice per non-empty segment', () => {
    createComponent();

    expect(findSeriesData()).toEqual([
      {
        key: 'SUCCESS',
        name: 'Enabled',
        value: 788,
        itemStyle: { color: 'var(--green-500)', opacity: 1 },
        emphasis: { itemStyle: { color: 'var(--green-500)', opacity: 1 } },
      },
      {
        key: 'FAILED',
        name: 'Failed',
        value: 299,
        itemStyle: { color: 'var(--red-500)', opacity: 1 },
        emphasis: { itemStyle: { color: 'var(--red-500)', opacity: 1 } },
      },
      {
        key: 'NOT_CONFIGURED',
        name: 'Not enabled',
        value: 127,
        itemStyle: { color: 'var(--gl-color-neutral-200)', opacity: 1 },
        emphasis: { itemStyle: { color: 'var(--gl-color-neutral-200)', opacity: 1 } },
      },
    ]);
  });

  it('sets emphasis color per slice to avoid flicker', () => {
    createComponent();

    expect(findSeriesData().map(({ emphasis }) => emphasis.itemStyle)).toEqual([
      { color: 'var(--green-500)', opacity: 1 },
      { color: 'var(--red-500)', opacity: 1 },
      { color: 'var(--gl-color-neutral-200)', opacity: 1 },
    ]);
  });

  it('hides the chart from assistive technology', () => {
    createComponent();

    expect(wrapper.findByTestId('tool-coverage-chart').attributes('aria-hidden')).toBe('true');
  });

  it('emits the status for a clicked slice', () => {
    createComponent();

    clickSlice(1);

    expect(wrapper.emitted('select-status')).toEqual([['FAILED']]);
  });

  describe('when a segment is selected', () => {
    beforeEach(() => {
      createComponent({
        segments: segments.map((segment) => ({
          ...segment,
          isSelected: segment.key === 'FAILED',
        })),
      });
    });

    it('applies dimming to the unselected slices', () => {
      expect(findSeriesData().map(({ key, itemStyle: { opacity } }) => [key, opacity])).toEqual([
        ['SUCCESS', 0.3],
        ['FAILED', 1],
        ['NOT_CONFIGURED', 0.3],
      ]);
    });

    it('does not render a visible centre percentage on selection alone', () => {
      // The graphic element stays alive (echarts merges options, so removing
      // it would leave the previous text stuck), but its text is empty.
      expect(findGraphic()).toEqual([
        expect.objectContaining({
          id: 'hover-percent',
          style: expect.objectContaining({ text: '' }),
        }),
      ]);
    });
  });

  describe('when a segment is hovered', () => {
    beforeEach(() => {
      createComponent({
        segments: segments.map((segment) => ({
          ...segment,
          isHovered: segment.key === 'FAILED',
        })),
      });
    });

    it('applies dimming to the unhovered slices', () => {
      expect(findSeriesData().map(({ key, itemStyle: { opacity } }) => [key, opacity])).toEqual([
        ['SUCCESS', 0.3],
        ['FAILED', 1],
        ['NOT_CONFIGURED', 0.3],
      ]);
    });

    it('renders the hovered percentage in the ring centre', () => {
      // 299 / (788 + 299 + 0 + 127) = 0.246 -> 25%
      expect(findGraphic()).toEqual([
        expect.objectContaining({
          type: 'text',
          left: 'center',
          top: 'middle',
          style: expect.objectContaining({ text: '25%', fontWeight: 'bold' }),
        }),
      ]);
    });
  });

  it('reports the status behind a hovered slice via the chart mouseover event', () => {
    createComponent();

    // Simulate what chartCreated wires up: chart.on('mouseover', onChartMouseOver)
    wrapper.vm.onChartMouseOver({ dataIndex: 1 });

    expect(wrapper.emitted('hover-status')).toEqual([['FAILED']]);
  });

  it('clears the hover state when the pointer leaves the chart container', async () => {
    createComponent();

    await wrapper.findByTestId('tool-coverage-chart').trigger('mouseleave');

    expect(wrapper.emitted('hover-status')).toEqual([[null]]);
  });

  describe('when every segment is empty', () => {
    beforeEach(() => {
      createComponent({ segments: segments.map((segment) => ({ ...segment, count: 0 })) });
    });

    it('renders a single unclickable placeholder ring', () => {
      expect(findSeriesData()).toEqual([
        { value: 1, itemStyle: { color: 'var(--gl-color-neutral-200)' } },
      ]);
      expect(findSeries().silent).toBe(true);

      clickSlice(0);

      expect(wrapper.emitted('select-status')).toBeUndefined();
    });
  });
});
