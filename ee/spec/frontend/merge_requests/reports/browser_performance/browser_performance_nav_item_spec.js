import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import BrowserPerformanceNavItem from 'ee/merge_requests/reports/browser_performance/browser_performance_nav_item.vue';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

describe('BrowserPerformanceNavItem', () => {
  let wrapper;

  const findReportListItem = () => wrapper.findComponent(ReportListItem);

  it('renders the browser performance route with the injected loading state and icon', () => {
    wrapper = shallowMountExtended(BrowserPerformanceNavItem, {
      provide: {
        isBrowserPerformanceLoading: true,
        statusIconName: 'warning',
      },
    });

    expect(findReportListItem().text()).toBe('Browser performance');
    expect(findReportListItem().props('to')).toBe('browser-performance');
    expect(findReportListItem().props('isLoading')).toBe(true);
    expect(findReportListItem().props('statusIcon')).toBe('warning');
  });
});
