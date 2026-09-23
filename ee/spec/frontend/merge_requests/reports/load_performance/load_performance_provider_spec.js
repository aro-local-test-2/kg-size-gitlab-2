import MockAdapter from 'axios-mock-adapter';
import { mount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import {
  HTTP_STATUS_OK,
  HTTP_STATUS_BAD_REQUEST,
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
} from '~/lib/utils/http_status';
import LoadPerformanceProvider from 'ee/merge_requests/reports/load_performance/load_performance_provider.vue';
import {
  headLoadPerformance,
  baseLoadPerformance,
} from 'ee_jest/vue_merge_request_widget/mock_data';

describe('LoadPerformanceProvider', () => {
  let wrapper;
  let mock;

  const loadPerformance = { head_path: '/head.json', base_path: '/base.json' };

  const InjectedChild = {
    inject: ['isLoadPerformanceLoading', 'statusIconName', 'summary', 'sections'],
    template: `
      <div>
        <span data-testid="is-loading">{{ isLoadPerformanceLoading }}</span>
        <span data-testid="status-icon-name">{{ statusIconName }}</span>
        <span data-testid="summary-json">{{ JSON.stringify(summary) }}</span>
        <span data-testid="sections-json">{{ JSON.stringify(sections) }}</span>
      </div>
    `,
  };

  const mockApi = (statusCode, head, base) => {
    mock.onGet(loadPerformance.head_path).reply(statusCode, head, {});
    mock.onGet(loadPerformance.base_path).reply(statusCode, base, {});
  };

  const createComponent = ({ mr = { loadPerformance } } = {}) => {
    wrapper = mount(LoadPerformanceProvider, {
      propsData: { mr },
      slots: { default: InjectedChild },
    });
  };

  const getTextByTestId = (testId) => wrapper.find(`[data-testid="${testId}"]`).text();
  const findIsLoading = () => getTextByTestId('is-loading');
  const findStatusIconName = () => getTextByTestId('status-icon-name');
  const findSummaryTitle = () => JSON.parse(getTextByTestId('summary-json')).title;
  const findSections = () =>
    JSON.parse(getTextByTestId('sections-json')).map(({ header, children }) => ({
      header,
      children: children.map(({ text, icon }) => ({ text, icon: icon.name })),
    }));

  beforeEach(() => {
    mock = new MockAdapter(axios);
    mockApi(HTTP_STATUS_OK, headLoadPerformance, baseLoadPerformance);
  });

  afterEach(() => {
    mock.restore();
  });

  it('provides the metrics grouped by how each one changed', async () => {
    createComponent();
    await waitForPromises();

    expect(findSections()).toEqual([
      {
        header: 'Improved',
        children: [
          { text: 'TTFB P90: %{strong_start}100.60%{strong_end} (-3.50) (-3%)', icon: 'success' },
          { text: 'RPS: %{strong_start}8.99%{strong_end} (1.20) (+15%)', icon: 'success' },
        ],
      },
      {
        header: 'Degraded',
        children: [
          { text: 'TTFB P95: %{strong_start}125.45%{strong_end} (24.23) (+24%)', icon: 'failed' },
        ],
      },
      {
        header: 'No changes',
        children: [{ text: 'Checks: %{strong_start}100.00%%{strong_end}  ', icon: 'neutral' }],
      },
    ]);
    expect(findSummaryTitle()).toBe(
      'Load performance test metrics detected %{strong_start}4%{strong_end} changes',
    );
    expect(findStatusIconName()).toBe('warning');
    expect(findIsLoading()).toBe('false');
  });

  it('reports the success icon when no metric degraded or stayed the same', async () => {
    mockApi(
      HTTP_STATUS_OK,
      { metrics: { http_reqs: { rate: 9 } } },
      { metrics: { http_reqs: { rate: 7 } } },
    );
    createComponent();
    await waitForPromises();

    expect(findStatusIconName()).toBe('success');
  });

  it('does not fetch when the load performance paths are missing', async () => {
    createComponent({ mr: {} });
    await waitForPromises();

    expect(mock.history.get).toHaveLength(0);
    expect(findSummaryTitle()).toBe('Load performance test results are not available');
    expect(findStatusIconName()).toBe('warning');
    expect(findIsLoading()).toBe('false');
  });

  it('shows the status reason when the fetch fails with one', async () => {
    mockApi(HTTP_STATUS_BAD_REQUEST, { status_reason: 'No load performance report found' });
    createComponent();
    await waitForPromises();

    expect(findSummaryTitle()).toBe('No load performance report found');
    expect(findStatusIconName()).toBe('warning');
  });

  it('shows the error icon when the fetch fails without a status reason', async () => {
    mockApi(HTTP_STATUS_INTERNAL_SERVER_ERROR);
    createComponent();
    await waitForPromises();

    expect(findSummaryTitle()).toBe('Load performance test failed to load results');
    expect(findStatusIconName()).toBe('error');
    expect(findSections()).toEqual([]);
  });
});
