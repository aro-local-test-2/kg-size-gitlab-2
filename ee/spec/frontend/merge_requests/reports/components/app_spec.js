import Vue from 'vue';
import VueRouter from 'vue-router';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import MRWidgetService from 'ee_else_ce/vue_merge_request_widget/services/mr_widget_service';
import App from '~/merge_requests/reports/components/app.vue';
import routes from '~/merge_requests/reports/routes';
import { resetMergeRequestData } from '~/merge_requests/reports/merge_request_data';

jest.mock('ee_else_ce/vue_merge_request_widget/services/mr_widget_service', () => ({
  fetchInitialData: jest.fn().mockReturnValue(new Promise(() => {})),
}));

jest.mock('~/smart_interval');

Vue.use(VueRouter);

describe('Merge request reports App component', () => {
  let wrapper;

  const findSecurityScansProvider = () => wrapper.findComponent({ name: 'SecurityScansProvider' });
  const findLicenseComplianceNavItem = () =>
    wrapper.findComponent({ name: 'LicenseComplianceNavItem' });
  const findLoadPerformanceNavItem = () =>
    wrapper.findComponent({ name: 'LoadPerformanceNavItem' });
  const findMetricsNavItem = () => wrapper.findComponent({ name: 'MetricsNavItem' });
  const findBrowserPerformanceNavItem = () =>
    wrapper.findComponent({ name: 'BrowserPerformanceNavItem' });

  const createComponent = ({ mrWidgetData = {} } = {}) => {
    gl.mrWidgetData = {
      merge_request_cached_widget_path: '/',
      merge_request_widget_path: '/',
      enabled_reports: { license_scanning: true },
      ...mrWidgetData,
    };

    MRWidgetService.fetchInitialData.mockResolvedValue({
      data: {
        current_user: {},
        pipeline: { active: false, iid: 1, details: { status: {} } },
      },
    });

    const router = new VueRouter({ mode: 'history', routes });
    wrapper = shallowMountExtended(App, {
      router,
      provide: { projectPath: 'gitlab-org/gitlab', iid: '1', basePath: '' },
      stubs: {
        SecurityScansProvider: { name: 'SecurityScansProvider', template: '<div><slot /></div>' },
        LicenseComplianceProvider: {
          name: 'LicenseComplianceProvider',
          template: '<div><slot /></div>',
        },
        LicenseComplianceNavItem: { name: 'LicenseComplianceNavItem', template: '<div></div>' },
        LoadPerformanceProvider: {
          name: 'LoadPerformanceProvider',
          template: '<div><slot /></div>',
        },
        LoadPerformanceNavItem: { name: 'LoadPerformanceNavItem', template: '<div></div>' },
        MetricsProvider: { name: 'MetricsProvider', template: '<div><slot /></div>' },
        MetricsNavItem: { name: 'MetricsNavItem', template: '<div></div>' },
        BrowserPerformanceProvider: {
          name: 'BrowserPerformanceProvider',
          template: '<div><slot /></div>',
        },
        BrowserPerformanceNavItem: {
          name: 'BrowserPerformanceNavItem',
          template: '<div></div>',
        },
      },
    });
  };

  afterEach(() => {
    resetMergeRequestData();
    gl.mrWidgetData = {};
  });

  it('renders the license compliance report when enabled_reports allows it', async () => {
    createComponent();
    await waitForPromises();
    findSecurityScansProvider().vm.$emit('enabled-scans-change', false);
    await waitForPromises();

    expect(findLicenseComplianceNavItem().exists()).toBe(true);
    expect(wrapper.vm.$route.name).toBe('license-compliance');
  });

  it('renders the load performance report when the head pipeline has the artifact', async () => {
    createComponent({ mrWidgetData: { load_performance: { head_path: '/head.json' } } });
    await waitForPromises();
    findSecurityScansProvider().vm.$emit('enabled-scans-change', false);
    await waitForPromises();

    expect(findLoadPerformanceNavItem().exists()).toBe(true);
  });

  it('does not render the load performance report without the artifact', async () => {
    createComponent();
    await waitForPromises();
    findSecurityScansProvider().vm.$emit('enabled-scans-change', false);
    await waitForPromises();

    expect(findLoadPerformanceNavItem().exists()).toBe(false);
  });

  it('renders the metrics report when metrics_reports_path is present', async () => {
    createComponent({ mrWidgetData: { metrics_reports_path: 'metrics_reports.json' } });
    await waitForPromises();
    findSecurityScansProvider().vm.$emit('enabled-scans-change', false);
    await waitForPromises();

    expect(findMetricsNavItem().exists()).toBe(true);
  });

  it('renders the browser performance report when the head pipeline has the artifact', async () => {
    createComponent({
      mrWidgetData: { browser_performance: { head_path: '/head.json', base_path: '/base.json' } },
    });
    await waitForPromises();
    findSecurityScansProvider().vm.$emit('enabled-scans-change', false);
    await waitForPromises();

    expect(findBrowserPerformanceNavItem().exists()).toBe(true);
  });

  it('does not render the browser performance report without the artifact', async () => {
    createComponent();
    await waitForPromises();
    findSecurityScansProvider().vm.$emit('enabled-scans-change', false);
    await waitForPromises();

    expect(findBrowserPerformanceNavItem().exists()).toBe(false);
  });
});
