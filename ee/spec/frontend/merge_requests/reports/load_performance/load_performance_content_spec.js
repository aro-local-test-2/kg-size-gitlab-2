import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import LoadPerformanceContent from 'ee/merge_requests/reports/load_performance/load_performance_content.vue';
import ReportSection from '~/merge_requests/reports/components/report_section.vue';

describe('LoadPerformanceContent', () => {
  it('passes the injected values to ReportSection', () => {
    const summary = { title: 'Load performance test metrics detected 4 changes' };
    const sections = [{ header: 'Degraded', children: [] }];
    const wrapper = shallowMountExtended(LoadPerformanceContent, {
      provide: {
        isLoadPerformanceLoading: true,
        statusIconName: 'warning',
        summary,
        sections,
      },
    });
    const reportSection = wrapper.findComponent(ReportSection);

    expect(reportSection.props()).toMatchObject({
      isLoading: true,
      loadingText: 'Load performance test metrics results are being parsed',
      statusIconName: 'warning',
      summary,
      sections,
    });
  });
});
