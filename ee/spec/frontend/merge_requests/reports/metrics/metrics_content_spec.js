import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import MetricsContent from 'ee/merge_requests/reports/metrics/metrics_content.vue';
import ReportSection from '~/merge_requests/reports/components/report_section.vue';

describe('MetricsContent', () => {
  let wrapper;

  const MOCK_SECTIONS = [
    {
      header: 'Changed',
      children: [
        { text: 'memory_static_objects_retained_mb: 30.6 (30.5)', icon: { name: 'neutral' } },
      ],
    },
  ];

  const findReportSection = () => wrapper.findComponent(ReportSection);
  const findSummaryTitle = () => findReportSection().props('summary').title;

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMountExtended(MetricsContent, {
      provide: {
        isMetricsLoading: false,
        statusMessage: '',
        numberOfChanges: 2,
        statusIconName: 'warning',
        sections: MOCK_SECTIONS,
        ...provide,
      },
    });
  };

  it('passes the injected loading state, icon, and sections to ReportSection', () => {
    createComponent({ provide: { isMetricsLoading: true } });

    expect(findReportSection().props()).toMatchObject({
      isLoading: true,
      loadingText: 'Metrics reports are loading',
      statusIconName: 'warning',
      sections: MOCK_SECTIONS,
    });
  });

  describe('summary title', () => {
    it.each`
      description                             | provide                                                   | expected
      ${'counts the changes'}                 | ${{ numberOfChanges: 2 }}                                 | ${'Metrics reports: %{strong_start}2%{strong_end} changes'}
      ${'uses the singular form for one'}     | ${{ numberOfChanges: 1 }}                                 | ${'Metrics reports: %{strong_start}1%{strong_end} change'}
      ${'reports no changes when none found'} | ${{ numberOfChanges: 0 }}                                 | ${'Metrics report scanning detected no new changes'}
      ${'shows the status message when set'}  | ${{ statusMessage: 'Metrics reports are not available' }} | ${'Metrics reports are not available'}
    `('$description', ({ provide, expected }) => {
      createComponent({ provide });

      expect(findSummaryTitle()).toBe(expected);
    });
  });
});
