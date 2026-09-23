import MockAdapter from 'axios-mock-adapter';
import { mount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  HTTP_STATUS_OK,
  HTTP_STATUS_NO_CONTENT,
  HTTP_STATUS_BAD_REQUEST,
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
} from '~/lib/utils/http_status';
import MetricsProvider from 'ee/merge_requests/reports/metrics/metrics_provider.vue';
import { metricsResponse } from 'ee_jest/vue_merge_request_widget/widgets/metrics/mock_data';

describe('MetricsProvider', () => {
  let wrapper;
  let mock;

  const endpoint = '/metrics_reports';

  const InjectedChild = {
    inject: ['isMetricsLoading', 'statusMessage', 'statusIconName', 'numberOfChanges', 'sections'],
    template: `
      <div>
        <span data-testid="is-loading">{{ isMetricsLoading }}</span>
        <span data-testid="status-message">{{ statusMessage }}</span>
        <span data-testid="status-icon-name">{{ statusIconName }}</span>
        <span data-testid="number-of-changes">{{ numberOfChanges }}</span>
        <span data-testid="sections-json">{{ JSON.stringify(sections) }}</span>
      </div>
    `,
  };

  const mockApi = (statusCode, data) => {
    mock.onGet(endpoint).reply(statusCode, data, {});
  };

  const createComponent = ({ mr = { metricsReportsPath: endpoint } } = {}) => {
    wrapper = mount(MetricsProvider, {
      propsData: { mr },
      slots: { default: InjectedChild },
    });
  };

  const getTextByTestId = (testId) => wrapper.find(`[data-testid="${testId}"]`).text();
  const findIsLoading = () => getTextByTestId('is-loading');
  const findStatusMessage = () => getTextByTestId('status-message');
  const findStatusIconName = () => getTextByTestId('status-icon-name');
  const findNumberOfChanges = () => getTextByTestId('number-of-changes');
  const findSections = () => JSON.parse(getTextByTestId('sections-json'));

  beforeEach(() => {
    mock = new MockAdapter(axios);
    mockApi(HTTP_STATUS_OK, metricsResponse);
    jest.spyOn(Sentry, 'captureException').mockImplementation(() => {});
  });

  afterEach(() => {
    mock.restore();
  });

  it('provides sections grouped by change type, with changed metrics sorted by delta', async () => {
    createComponent();
    await waitForPromises();

    expect(findSections()).toEqual([
      {
        header: 'New',
        children: [
          { text: 'gem_size_mb{name=pg}: 3.0', icon: { name: 'neutral' } },
          { text: 'memory_static_objects_retained_items: 258835', icon: { name: 'neutral' } },
        ],
      },
      {
        header: 'Removed',
        children: [
          { text: 'gem_size_mb{name=charlock_holmes}: 2.7', icon: { name: 'neutral' } },
          { text: 'gem_size_mb{name=omniauth-auth0}: 0.5', icon: { name: 'neutral' } },
        ],
      },
      {
        header: 'Changed',
        children: [
          { text: 'memory_static_objects_allocated_items: 1 (1552382)', icon: { name: 'neutral' } },
          { text: 'memory_static_objects_retained_mb: 30.6 (30.5)', icon: { name: 'neutral' } },
        ],
      },
      {
        header: 'No changes',
        children: [
          { text: 'gem_total_size_mb: 194.8', icon: { name: 'neutral' } },
          { text: 'memory_static_objects_allocated_mb: 163.7', icon: { name: 'neutral' } },
        ],
      },
    ]);
    expect(findNumberOfChanges()).toBe('6');
    expect(findStatusIconName()).toBe('warning');
    expect(findStatusMessage()).toBe('');
    expect(findIsLoading()).toBe('false');
  });

  it('drops empty groups and reports the success icon when nothing changed', async () => {
    mockApi(HTTP_STATUS_OK, { existing_metrics: [{ name: 'gem_total_size_mb', value: '194.8' }] });
    createComponent();
    await waitForPromises();

    expect(findSections()).toEqual([
      {
        header: 'No changes',
        children: [{ text: 'gem_total_size_mb: 194.8', icon: { name: 'neutral' } }],
      },
    ]);
    expect(findNumberOfChanges()).toBe('0');
    expect(findStatusIconName()).toBe('success');
  });

  it('does not fetch when the metrics endpoint is missing', async () => {
    createComponent({ mr: {} });
    await waitForPromises();

    expect(mock.history.get).toHaveLength(0);
    expect(findStatusMessage()).toBe('Metrics reports results are not available');
    expect(findStatusIconName()).toBe('warning');
    expect(findIsLoading()).toBe('false');
  });

  it('shows the status reason when the fetch fails with one', async () => {
    mockApi(HTTP_STATUS_BAD_REQUEST, { status_reason: 'No metrics reports found' });
    createComponent();
    await waitForPromises();

    expect(findStatusMessage()).toBe('No metrics reports found');
    expect(findStatusIconName()).toBe('warning');
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('shows the error icon and logs to Sentry when the fetch fails without a status reason', async () => {
    mockApi(HTTP_STATUS_INTERNAL_SERVER_ERROR);
    createComponent();
    await waitForPromises();

    expect(findStatusMessage()).toBe('Metrics reports failed to load results');
    expect(findStatusIconName()).toBe('error');
    expect(findSections()).toEqual([]);
    expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
  });

  it('keeps polling while the report is generating, then stops once it resolves', async () => {
    mock.reset();
    mock.onGet(endpoint).replyOnce(HTTP_STATUS_NO_CONTENT, '', { 'poll-interval': '1' });
    mockApi(HTTP_STATUS_OK, metricsResponse);
    createComponent();
    await waitForPromises();

    expect(findIsLoading()).toBe('true');

    jest.runOnlyPendingTimers();
    await waitForPromises();

    expect(findIsLoading()).toBe('false');
    expect(findNumberOfChanges()).toBe('6');
    expect(mock.history.get).toHaveLength(2);

    jest.runOnlyPendingTimers();
    await waitForPromises();

    expect(mock.history.get).toHaveLength(2);
  });
});
