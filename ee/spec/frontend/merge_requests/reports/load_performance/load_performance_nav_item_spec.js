import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import LoadPerformanceNavItem from 'ee/merge_requests/reports/load_performance/load_performance_nav_item.vue';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

describe('LoadPerformanceNavItem', () => {
  let wrapper;

  const findReportListItem = () => wrapper.findComponent(ReportListItem);

  it('renders the load performance route with the injected loading state and icon', () => {
    wrapper = shallowMountExtended(LoadPerformanceNavItem, {
      provide: {
        isLoadPerformanceLoading: true,
        statusIconName: 'warning',
      },
    });

    expect(findReportListItem().text()).toBe('Load performance');
    expect(findReportListItem().props('to')).toBe('load-performance');
    expect(findReportListItem().props('isLoading')).toBe(true);
    expect(findReportListItem().props('statusIcon')).toBe('warning');
  });
});
