import { mount } from '@vue/test-utils';
import MockAdapter from 'axios-mock-adapter';
import { nextTick } from 'vue';
import api from '~/api';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import Widget from '~/vue_merge_request_widget/components/widget/widget.vue';
import BrowserPerformanceWidget from 'ee/vue_merge_request_widget/widgets/browser_performance/index.vue';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { baseBrowserPerformance, headBrowserPerformance } from '../../mock_data';

describe('Browser performance widget', () => {
  let wrapper;
  let mock;

  const DEFAULT_BROWSER_PERFORMANCE = {
    head_path: 'head.json',
    base_path: 'base.json',
  };

  const reportsTabPath = '/root/repo/-/merge_requests/4/reports';

  const findWidget = () => wrapper.findComponent(Widget);

  const createComponent = ({ mrProps = {} } = {}) => {
    wrapper = mount(BrowserPerformanceWidget, {
      propsData: {
        mr: {
          browserPerformance: {
            ...DEFAULT_BROWSER_PERFORMANCE,
          },
          ...mrProps,
        },
      },
    });
  };

  beforeEach(() => {
    jest.spyOn(api, 'trackRedisCounterEvent').mockImplementation(() => {});
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
  });

  it('emits loaded event', async () => {
    mock
      .onGet(DEFAULT_BROWSER_PERFORMANCE.head_path)
      .reply(HTTP_STATUS_OK, headBrowserPerformance, {});
    mock
      .onGet(DEFAULT_BROWSER_PERFORMANCE.base_path)
      .reply(HTTP_STATUS_OK, baseBrowserPerformance, {});

    createComponent();

    await waitForPromises();

    expect(wrapper.emitted('loaded')[1]).toContain(2);
  });

  describe('summary', () => {
    it('should render loading text', () => {
      mock
        .onGet(DEFAULT_BROWSER_PERFORMANCE.head_path)
        .reply(HTTP_STATUS_OK, headBrowserPerformance);
      mock
        .onGet(DEFAULT_BROWSER_PERFORMANCE.base_path)
        .reply(HTTP_STATUS_OK, baseBrowserPerformance);

      createComponent();

      expect(wrapper.text()).toBe('Browser performance test metrics results are being parsed');
    });

    it('should render info', async () => {
      mock
        .onGet(DEFAULT_BROWSER_PERFORMANCE.head_path)
        .reply(HTTP_STATUS_OK, headBrowserPerformance, {});
      mock
        .onGet(DEFAULT_BROWSER_PERFORMANCE.base_path)
        .reply(HTTP_STATUS_OK, baseBrowserPerformance, {});

      createComponent();

      await waitForPromises();

      expect(wrapper.text()).toContain('Browser performance test metrics');
      expect(wrapper.text()).toContain('2 degraded, 1 same, and 1 improved');
    });

    it('should render info about fixed issues', async () => {
      const head = [
        {
          metrics: [
            {
              name: 'Total Score',
              value: 90,
              desiredSize: 'larger',
            },
          ],
        },
      ];

      const base = [
        {
          metrics: [
            {
              name: 'Total Score',
              value: 80,
              desiredSize: 'larger',
            },
          ],
        },
      ];

      mock.onGet(DEFAULT_BROWSER_PERFORMANCE.head_path).reply(HTTP_STATUS_OK, head, {});
      mock.onGet(DEFAULT_BROWSER_PERFORMANCE.base_path).reply(HTTP_STATUS_OK, base, {});

      createComponent();

      await waitForPromises();

      expect(wrapper.text()).toContain('Browser performance test metrics: 1 change');
      expect(wrapper.text()).toContain('1 improved');
    });

    it('should render info about added issues', async () => {
      const head = [
        {
          metrics: [
            {
              name: 'Total Score',
              value: 80,
              desiredSize: 'larger',
            },
          ],
        },
      ];

      const base = [
        {
          metrics: [
            {
              name: 'Total Score',
              value: 90,
              desiredSize: 'larger',
            },
          ],
        },
      ];

      mock.onGet(DEFAULT_BROWSER_PERFORMANCE.head_path).reply(HTTP_STATUS_OK, head, {});
      mock.onGet(DEFAULT_BROWSER_PERFORMANCE.base_path).reply(HTTP_STATUS_OK, base, {});

      createComponent();

      await waitForPromises();

      expect(wrapper.text()).toContain('Browser performance test metrics: 1 change');
      expect(wrapper.text()).toContain('1 degraded');
    });
  });

  describe('expanded data', () => {
    beforeEach(async () => {
      mock
        .onGet(DEFAULT_BROWSER_PERFORMANCE.head_path)
        .reply(HTTP_STATUS_OK, headBrowserPerformance);
      mock
        .onGet(DEFAULT_BROWSER_PERFORMANCE.base_path)
        .reply(HTTP_STATUS_OK, baseBrowserPerformance);

      createComponent();

      await waitForPromises();

      wrapper
        .find('[data-testid="widget-extension"] [data-testid="toggle-button"]')
        .trigger('click');

      await nextTick();
    });

    it('shows the expanded list of text items', () => {
      const listItems = wrapper.findAll('[data-testid="extension-list-item"]');

      expect(listItems.at(0).text()).toBe('Speed Index: 1155 (-10) (-1%) in /some/path');
      expect(listItems.at(1).text()).toBe('Total Score: 80 (-2) (-2%) in /some/path');
      expect(listItems.at(2).text()).toBe('Transfer Size (KB): 1070.09 (5) (+0%) in /some/path');
    });
  });

  describe('"View report" button', () => {
    const { head_path: headPath, base_path: basePath } = DEFAULT_BROWSER_PERFORMANCE;

    beforeEach(() => {
      mock.onGet(headPath).reply(HTTP_STATUS_OK, headBrowserPerformance, {});
      mock.onGet(basePath).reply(HTTP_STATUS_OK, baseBrowserPerformance, {});
    });

    it('is not rendered when the merge request has no reports tab', async () => {
      createComponent();
      await waitForPromises();

      expect(findWidget().props('actionButtons')).toHaveLength(0);
    });

    describe('when the merge request has a reports tab', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();
      const reportPath = `${reportsTabPath}/browser-performance`;

      it('links to the report and navigates to it without a page reload', async () => {
        createComponent({ mrProps: { reportsTabPath } });
        await waitForPromises();

        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
        const pushStateSpy = jest.spyOn(window.history, 'pushState');
        const dispatchEventSpy = jest.spyOn(window, 'dispatchEvent');
        const [button] = findWidget().props('actionButtons');

        expect(button).toMatchObject({ text: 'View report', href: reportPath });
        expect(findWidget().props('isCollapsible')).toBe(false);

        button.onClick(button, { preventDefault: jest.fn() });

        expect(pushStateSpy).toHaveBeenCalledWith(null, null, reportPath);
        expect(dispatchEventSpy).toHaveBeenCalledWith(expect.any(PopStateEvent));
        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_view_report_on_merge_request_widget',
          { label: 'browser_performance' },
          undefined,
        );
      });
    });
  });
});
