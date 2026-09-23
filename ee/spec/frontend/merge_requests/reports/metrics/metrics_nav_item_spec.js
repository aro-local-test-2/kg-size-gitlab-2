import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import MetricsNavItem from 'ee/merge_requests/reports/metrics/metrics_nav_item.vue';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

describe('MetricsNavItem', () => {
  let wrapper;

  const findReportListItem = () => wrapper.findComponent(ReportListItem);

  it('renders the metrics route with the injected loading state and icon', () => {
    wrapper = shallowMountExtended(MetricsNavItem, {
      provide: {
        isMetricsLoading: true,
        statusIconName: 'warning',
      },
    });

    expect(findReportListItem().text()).toBe('Metrics');
    expect(findReportListItem().props()).toMatchObject({
      to: 'metrics',
      isLoading: true,
      statusIcon: 'warning',
    });
  });
});
