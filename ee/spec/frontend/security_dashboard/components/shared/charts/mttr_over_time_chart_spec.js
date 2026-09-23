import { nextTick } from 'vue';
import { GlStackedColumnChart } from '@gitlab/ui/src/charts';
import { GL_COLOR_NEUTRAL_300, DATA_VIZ_BLUE_500 } from '@gitlab/ui/src/tokens/build/js/tokens';
import { shallowMount } from '@vue/test-utils';
import { stubComponent } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import MttrOverTimeChart from 'ee/security_dashboard/components/shared/charts/mttr_over_time_chart.vue';
import * as ChartUtils from 'ee/security_dashboard/utils/chart_utils';
import {
  listenSystemColorSchemeChange,
  removeListenerSystemColorSchemeChange,
} from '~/lib/utils/css_utils';
import { REPORT_TYPE_COLORS } from 'ee/security_dashboard/components/shared/vulnerability_report/constants';

const mockSeverityColors = {
  critical: '#000000',
  high: '#111111',
  medium: '#222222',
  low: '#333333',
  info: '#444444',
  unknown: '#555555',
};
jest.mock('~/lib/utils/css_utils');

describe('MttrOverTimeChart', () => {
  let wrapper;

  const mockMttrSeries = [{ id: 'all', name: 'MTTR', data: [['2022-04-18', 20]] }];
  const mockCountSeries = {
    id: 'count',
    name: 'Remediations',
    data: [
      ['2022-04-18', 5],
      ['2022-04-25', 0],
    ],
  };

  const findChart = () => wrapper.findComponent(GlStackedColumnChart);

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMount(MttrOverTimeChart, {
      propsData: {
        mttrSeries: mockMttrSeries,
        countSeries: mockCountSeries,
        ...props,
      },
    });
  };

  beforeEach(() => {
    jest.spyOn(ChartUtils, 'getSeverityColors').mockImplementation(() => mockSeverityColors);
  });

  it('renders a stacked column chart', () => {
    createComponent();

    expect(findChart().exists()).toBe(true);
  });

  it('passes the MTTR series as lines on the primary axis', () => {
    createComponent();

    expect(findChart().props('lines')).toEqual([{ name: 'MTTR', data: [['2022-04-18', 20]] }]);
  });

  it('passes the count series as bars on the secondary axis', () => {
    createComponent();

    expect(findChart().props('secondaryData')).toEqual([
      { name: 'Remediations', data: mockCountSeries.data, type: 'bar' },
    ]);
  });

  it('groups by the weekly start dates', () => {
    createComponent();

    expect(findChart().props('groupBy')).toEqual(['2022-04-18', '2022-04-25']);
  });

  it('disables chart animations', () => {
    createComponent();

    expect(findChart().props('option').animation).toBe(false);
  });

  it('formats the primary (MTTR) y-axis in days and configures the count axis', () => {
    createComponent();

    const [primaryAxis, secondaryAxis] = findChart().props('option').yAxis;

    expect(primaryAxis.axisLabel.formatter).toBe('{value}d');
    expect(secondaryAxis.minInterval).toBe(1);
  });

  describe('custom palette', () => {
    it('colors the "all" line with the fallback color and the count bars grey', async () => {
      createComponent();
      // Colors are resolved on mount, so the chart re-renders on the next tick.
      await nextTick();

      expect(findChart().props('customPalette')).toEqual([DATA_VIZ_BLUE_500, GL_COLOR_NEUTRAL_300]);
    });

    it.each([
      ['Critical', 'CRITICAL', mockSeverityColors.critical],
      ['High', 'HIGH', mockSeverityColors.high],
      ['Sast', 'SAST', REPORT_TYPE_COLORS.sast],
      ['Dast', 'DAST', REPORT_TYPE_COLORS.dast],
    ])('colors the %s line with its own color', async (name, id, expectedColor) => {
      createComponent({ props: { mttrSeries: [{ id, name, data: [] }] } });
      await nextTick();

      expect(findChart().props('customPalette')).toEqual([expectedColor, GL_COLOR_NEUTRAL_300]);
    });
  });

  describe('tooltip content', () => {
    const findRows = () => wrapper.findAllByTestId('mttr-tooltip-row');
    const rowTexts = () => findRows().wrappers.map((row) => row.text().replace(/\s+/g, ' '));
    const findNoRemediations = () => wrapper.findByTestId('mttr-tooltip-no-remediations');

    const createComponentWithTooltip = ({ mttrSeries, seriesData }) => {
      wrapper = shallowMountExtended(MttrOverTimeChart, {
        propsData: { mttrSeries, countSeries: mockCountSeries },
        stubs: {
          GlStackedColumnChart: stubComponent(GlStackedColumnChart, {
            data() {
              return { params: { seriesData } };
            },
            template: `<div><slot name="tooltip-content" :params="params"></slot></div>`,
          }),
        },
      });
    };

    describe('when grouped by "all"', () => {
      it('shows the MTTR and remediation count for a week with remediations', () => {
        createComponentWithTooltip({
          mttrSeries: mockMttrSeries,
          seriesData: [
            { seriesName: 'MTTR', color: '#111', value: ['2022-04-18', 20] },
            { seriesName: 'Remediations', color: '#222', value: ['2022-04-18', 5] },
          ],
        });

        expect(findNoRemediations().exists()).toBe(false);
        expect(rowTexts()).toEqual(['MTTR 20 days', 'Remediations 5']);
      });

      it.each`
        mttr    | expected
        ${0.6}  | ${'0.6 days'}
        ${1}    | ${'1 day'}
        ${1.1}  | ${'1.1 days'}
        ${20.4} | ${'20.4 days'}
      `('formats an MTTR of $mttr as "$expected"', ({ mttr, expected }) => {
        createComponentWithTooltip({
          mttrSeries: mockMttrSeries,
          seriesData: [
            { seriesName: 'MTTR', color: '#111', value: ['2022-04-18', mttr] },
            { seriesName: 'Remediations', color: '#222', value: ['2022-04-18', 5] },
          ],
        });

        expect(rowTexts()).toEqual([`MTTR ${expected}`, 'Remediations 5']);
      });

      it('explains that nothing was remediated in a week without remediations', () => {
        createComponentWithTooltip({
          mttrSeries: mockMttrSeries,
          seriesData: [
            { seriesName: 'MTTR', color: '#111', value: ['2022-04-25', null] },
            { seriesName: 'Remediations', color: '#222', value: ['2022-04-25', 0] },
          ],
        });

        expect(findRows()).toHaveLength(0);
        expect(findNoRemediations().text()).toBe('No vulnerabilities remediated this week');
      });
    });

    describe('when grouped by severity or report type', () => {
      it('explains that nothing was remediated when every line is empty that week', () => {
        createComponentWithTooltip({
          mttrSeries: [
            { id: 'CRITICAL', name: 'Critical', data: [] },
            { id: 'HIGH', name: 'High', data: [] },
          ],
          seriesData: [
            { seriesName: 'Critical', color: '#111', value: ['2022-04-25', null] },
            { seriesName: 'High', color: '#222', value: ['2022-04-25', null] },
            { seriesName: 'Remediations', color: '#333', value: ['2022-04-25', 0] },
          ],
        });

        expect(findRows()).toHaveLength(0);
        expect(findNoRemediations().text()).toBe('No vulnerabilities remediated this week');
      });

      it('shows "None" for a line without remediations instead of hiding the row', () => {
        createComponentWithTooltip({
          mttrSeries: [
            { id: 'CRITICAL', name: 'Critical', data: [] },
            { id: 'HIGH', name: 'High', data: [] },
          ],
          seriesData: [
            { seriesName: 'Critical', color: '#111', value: ['2022-04-25', 12] },
            { seriesName: 'High', color: '#222', value: ['2022-04-25', null] },
            { seriesName: 'Remediations', color: '#333', value: ['2022-04-25', 3] },
          ],
        });

        expect(findNoRemediations().exists()).toBe(false);
        expect(rowTexts()).toEqual(['Critical 12 days', 'High None', 'Remediations 3']);
      });
    });
  });

  describe('dark mode', () => {
    it('listens for color scheme changes on mount', () => {
      createComponent();

      expect(listenSystemColorSchemeChange).toHaveBeenCalled();
    });

    it('removes the color scheme listener when destroyed', () => {
      createComponent();
      wrapper.destroy();

      expect(removeListenerSystemColorSchemeChange).toHaveBeenCalled();
    });
  });
});
