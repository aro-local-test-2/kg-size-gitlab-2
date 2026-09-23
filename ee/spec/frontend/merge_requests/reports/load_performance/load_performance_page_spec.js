import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import LoadPerformancePage from 'ee/merge_requests/reports/load_performance/load_performance_page.vue';
import LoadPerformanceProvider from 'ee/merge_requests/reports/load_performance/load_performance_provider.vue';
import LoadPerformanceContent from 'ee/merge_requests/reports/load_performance/load_performance_content.vue';

describe('LoadPerformancePage', () => {
  let wrapper;

  const DEFAULT_MR_PROP = { id: 1 };

  const findProvider = () => wrapper.findComponent(LoadPerformanceProvider);

  const createComponent = () => {
    wrapper = shallowMountExtended(LoadPerformancePage, {
      propsData: {
        mr: DEFAULT_MR_PROP,
      },
    });
  };

  it('renders LoadPerformanceContent inside a provider given the mr prop', () => {
    createComponent();

    expect(findProvider().props('mr')).toBe(DEFAULT_MR_PROP);
    expect(findProvider().findComponent(LoadPerformanceContent).exists()).toBe(true);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks view_merge_request_report on mount', () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_merge_request_report',
        { label: 'load_performance' },
        undefined,
      );
    });
  });
});
