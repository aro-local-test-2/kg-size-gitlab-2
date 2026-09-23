import { within } from '@testing-library/dom';
import initSecurityDashboard from 'ee/security_dashboard/security_dashboard_init';
import { unmountVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import {
  DASHBOARD_TYPE_GROUP,
  DASHBOARD_TYPE_INSTANCE,
  DASHBOARD_TYPE_ORGANIZATION,
  DASHBOARD_TYPE_PROJECT,
} from 'ee/security_dashboard/constants';
import setWindowLocation from 'helpers/set_window_location_helper';
import { TEST_HOST } from 'helpers/test_constants';

const EMPTY_DIV = document.createElement('div');

const TEST_DATASET = {
  link: '/test/link',
  svgPath: '/test/no_changes_state.svg',
  emptyStateSvgPath: '/test/empty_state.svg',
  hasProjects: 'true',
};

describe('Security Dashboard', () => {
  let vm;
  let root;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);

    setWindowLocation(`${TEST_HOST}/-/security/dashboard`);

    window.gon.features = {};

    // Set up abilities
    window.gon.abilities = {
      accessAdvancedVulnerabilityManagement: false,
    };
  });

  afterEach(() => {
    unmountVueApp(vm);
    root.remove();
  });

  const createComponent = async ({ data, type }) => {
    const el = document.createElement('div');
    Object.assign(el.dataset, { ...TEST_DATASET, ...data });
    root.appendChild(el);
    vm = await initSecurityDashboard(el, type);
  };

  const createEmptyComponent = async () => {
    vm = await initSecurityDashboard(null, null);
  };

  const getByTestId = (testId) => within(root).getByTestId(testId);

  const findGroupDashboard = () => getByTestId('group-security-dashboard');
  const findProjectDashboard = () => getByTestId('project-security-dashboard');
  const findLegacySecurityDashboard = () => getByTestId('legacy-security-dashboard');
  const findLegacyProjectDashboard = () => getByTestId('legacy-project-security-dashboard');
  const findNotConfiguredGroup = () => getByTestId('report-not-configured-group');
  const findNotConfiguredProject = () => getByTestId('report-not-configured-project');
  const findNotConfiguredInstance = () => getByTestId('report-not-configured-instance');
  const findOrganizationDashboard = () => getByTestId('organization-security-dashboard');

  describe('group level', () => {
    const GROUP_OPTIONS = { data: { groupFullPath: '/test/' }, type: DASHBOARD_TYPE_GROUP };

    it('shows not configured component if there are no projects', async () => {
      await createComponent({
        ...GROUP_OPTIONS,
        data: { ...GROUP_OPTIONS.data, hasProjects: 'false' },
      });
      expect(findNotConfiguredGroup()).toBeInstanceOf(HTMLElement);
    });

    it('shows old security dashboard if there are projects and advanced vulnerability management is disabled', async () => {
      await createComponent(GROUP_OPTIONS);
      expect(findLegacySecurityDashboard()).toBeInstanceOf(HTMLElement);
    });

    it('shows new security dashboard when advanced vulnerability management is enabled', async () => {
      window.gon.abilities.accessAdvancedVulnerabilityManagement = true;
      await createComponent(GROUP_OPTIONS);
      expect(findGroupDashboard()).toBeInstanceOf(HTMLElement);
    });
  });

  describe('project level', () => {
    const PROJECT_OPTIONS = {
      data: {
        projectFullPath: '/test/project',
        hasVulnerabilities: 'true',
        securityConfigurationPath: '/test/configuration',
        newVulnerabilityPath: '/vulnerabilities/new',
        canAdminVulnerability: 'true',
      },
      type: DASHBOARD_TYPE_PROJECT,
    };

    it('shows not configured component if there are no vulnerabilities', async () => {
      await createComponent({
        ...PROJECT_OPTIONS,
        data: { ...PROJECT_OPTIONS.data, hasVulnerabilities: false },
      });
      expect(findNotConfiguredProject()).toBeInstanceOf(HTMLElement);
    });

    it('shows old security dashboard if there are vulnerabilities and advanced vulnerability management is disabled', async () => {
      await createComponent(PROJECT_OPTIONS);
      expect(findLegacyProjectDashboard()).toBeInstanceOf(HTMLElement);
    });

    it('sets up new dashboard when advanced search is enabled', async () => {
      window.gon.abilities.accessAdvancedVulnerabilityManagement = true;
      await createComponent(PROJECT_OPTIONS);
      expect(findProjectDashboard()).toBeInstanceOf(HTMLElement);
    });
  });

  describe('instance level', () => {
    const INSTANCE_OPTIONS = {
      data: { instanceDashboardSettingsPath: '/instance/settings_page' },
      type: DASHBOARD_TYPE_INSTANCE,
    };

    it('shows not configured component if there are no projects', async () => {
      await createComponent({
        ...INSTANCE_OPTIONS,
        data: { ...INSTANCE_OPTIONS.data, hasProjects: false },
      });
      expect(findNotConfiguredInstance()).toBeInstanceOf(HTMLElement);
    });

    it('shows security dashboard if there are projects', async () => {
      await createComponent(INSTANCE_OPTIONS);
      expect(findLegacySecurityDashboard()).toBeInstanceOf(HTMLElement);
    });
  });

  describe('organization level', () => {
    const ORGANIZATION_OPTIONS = { data: {}, type: DASHBOARD_TYPE_ORGANIZATION };

    it('shows the new security dashboard', async () => {
      await createComponent(ORGANIZATION_OPTIONS);

      expect(findOrganizationDashboard()).toBeInstanceOf(HTMLElement);
    });

    it('shows the new security dashboard even when advanced vulnerability management is disabled', async () => {
      window.gon.abilities.accessAdvancedVulnerabilityManagement = false;

      await createComponent(ORGANIZATION_OPTIONS);

      expect(findOrganizationDashboard()).toBeInstanceOf(HTMLElement);
    });

    it('shows the new security dashboard when there are no projects', async () => {
      await createComponent({
        ...ORGANIZATION_OPTIONS,
        data: { hasProjects: 'false' },
      });

      expect(findOrganizationDashboard()).toBeInstanceOf(HTMLElement);
    });
  });

  describe('error states', () => {
    it('does not have an element', async () => {
      await createEmptyComponent();

      expect(root).toStrictEqual(EMPTY_DIV);
    });
  });
});
