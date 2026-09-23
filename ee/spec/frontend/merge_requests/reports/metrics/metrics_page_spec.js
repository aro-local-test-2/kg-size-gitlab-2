import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import MetricsPage from 'ee/merge_requests/reports/metrics/metrics_page.vue';
import MetricsProvider from 'ee/merge_requests/reports/metrics/metrics_provider.vue';
import MetricsContent from 'ee/merge_requests/reports/metrics/metrics_content.vue';

describe('MetricsPage', () => {
  const DEFAULT_MR_PROP = { id: 1 };

  it('renders MetricsContent inside MetricsProvider', () => {
    const wrapper = shallowMountExtended(MetricsPage, {
      propsData: { mr: DEFAULT_MR_PROP },
    });
    const provider = wrapper.findComponent(MetricsProvider);

    expect(provider.props('mr')).toBe(DEFAULT_MR_PROP);
    expect(provider.findComponent(MetricsContent).exists()).toBe(true);
  });
});
