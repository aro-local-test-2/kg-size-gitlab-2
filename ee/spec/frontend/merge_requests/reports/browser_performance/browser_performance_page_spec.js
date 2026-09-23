import MockAdapter from 'axios-mock-adapter';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';
import StatusIcon from '~/vue_merge_request_widget/components/widget/status_icon.vue';
import BrowserPerformancePage from 'ee/merge_requests/reports/browser_performance/browser_performance_page.vue';
import {
  baseBrowserPerformance,
  headBrowserPerformance,
} from 'ee_jest/vue_merge_request_widget/mock_data';

describe('BrowserPerformancePage', () => {
  let wrapper;
  let mock;

  const headPath = 'head.json';
  const basePath = 'base.json';
  const bothPaths = { head_path: headPath, base_path: basePath };

  const createComponent = async (mr = { browserPerformance: bothPaths }) => {
    wrapper = mountExtended(BrowserPerformancePage, { propsData: { mr } });
    await waitForPromises();
  };

  const findSummary = () => wrapper.findByTestId('summary').text();
  const findStatusIcon = () => wrapper.findComponent(StatusIcon).props('iconName');

  beforeEach(() => {
    mock = new MockAdapter(axios);
    mock.onGet(headPath).reply(HTTP_STATUS_OK, headBrowserPerformance, {});
    mock.onGet(basePath).reply(HTTP_STATUS_OK, baseBrowserPerformance, {});
  });

  afterEach(() => {
    mock.restore();
  });

  it('compares the head and base reports into one section', async () => {
    await createComponent();

    expect(findSummary()).toBe('Browser performance test metrics: 4 changes');
    expect(wrapper.findByTestId('summary-subtitle').text()).toBe(
      '2 degraded, 1 same, and 1 improved',
    );
    expect(wrapper.findAllByTestId('section-item')).toHaveLength(4);
    expect(wrapper.findByTestId('item-text').text()).toBe(
      'Speed Index: 1155 (-10) (-1%) in /some/path',
    );
    expect(findStatusIcon()).toBe('warning');
  });

  it.each([{ head_path: headPath }, undefined])(
    'does not fetch when browserPerformance is %p',
    async (browserPerformance) => {
      await createComponent({ browserPerformance });

      expect(mock.history.get).toHaveLength(0);
      expect(findSummary()).toBe('Browser performance results are not available');
      expect(findStatusIcon()).toBe('warning');
    },
  );

  it('reports an error when a report fails to download', async () => {
    mock.onGet(headPath).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

    await createComponent();

    expect(findSummary()).toBe('Browser performance failed loading results');
    expect(findStatusIcon()).toBe('error');
    expect(wrapper.findAllByTestId('section-item')).toHaveLength(0);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks view_merge_request_report on mount', async () => {
      await createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_merge_request_report',
        { label: 'browser_performance' },
        undefined,
      );
    });
  });
});
