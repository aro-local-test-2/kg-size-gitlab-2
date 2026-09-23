import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import ReportNotConfiguredProject from 'ee/security_dashboard/components/project/report_not_configured_project.vue';
import ReportNotConfiguredGroup from 'ee/security_dashboard/components/group/report_not_configured_group.vue';
import ReportNotConfiguredInstance from 'ee/security_dashboard/components/instance/report_not_configured_instance.vue';
import {
  DASHBOARD_TYPE_GROUP,
  DASHBOARD_TYPE_INSTANCE,
  DASHBOARD_TYPE_ORGANIZATION,
  DASHBOARD_TYPE_PROJECT,
} from 'ee/security_dashboard/constants';
import { convertObjectPropsToCamelCase, parseBoolean } from '~/lib/utils/common_utils';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_SECURITY_PROJECT_TRACKED_CONTEXT } from 'ee/graphql_shared/constants';
import groupVulnerabilityGradesQuery from 'ee/security_dashboard/graphql/queries/group_vulnerability_grades.query.graphql';
import groupVulnerabilityHistoryQuery from 'ee/security_dashboard/graphql/queries/group_vulnerability_history.query.graphql';
import instanceVulnerabilityGradesQuery from 'ee/security_dashboard/graphql/queries/instance_vulnerability_grades.query.graphql';
import instanceVulnerabilityHistoryQuery from 'ee/security_dashboard/graphql/queries/instance_vulnerability_history.query.graphql';
import apolloProvider from './graphql/provider';

export default async (el, dashboardType) => {
  if (!el) {
    return null;
  }

  const {
    emptyStateSvgPath,
    groupFullPath,
    projectFullPath,
    securityConfigurationPath,
    securityDashboardEmptySvgPath,
    instanceDashboardSettingsPath,
    vulnerabilitiesPdfExportEndpoint,
    newVulnerabilityPath,
    groupSecurityVulnerabilitiesPath,
    projectSecurityVulnerabilitiesPath,
    manageDuoSettingsPath,
    defaultBranchContext,
  } = el.dataset;

  const hasProjects = parseBoolean(el.dataset.hasProjects);
  const hasVulnerabilities = parseBoolean(el.dataset.hasVulnerabilities);
  const canAdminVulnerability = parseBoolean(el.dataset.canAdminVulnerability);
  const provide = {
    emptyStateSvgPath,
    groupFullPath,
    projectFullPath,
    securityConfigurationPath,
    securityDashboardEmptySvgPath,
    instanceDashboardSettingsPath,
    vulnerabilitiesPdfExportEndpoint,
    canAdminVulnerability,
    newVulnerabilityPath,
    manageDuoSettingsPath,
    dashboardType,
    securityVulnerabilitiesPath: null,
  };

  let props = {};
  let component;

  const hasAccessAdvancedVulnerabilityManagement =
    gon.abilities?.accessAdvancedVulnerabilityManagement;

  if (dashboardType === DASHBOARD_TYPE_GROUP) {
    if (!hasProjects) {
      component = ReportNotConfiguredGroup;
    } else if (hasAccessAdvancedVulnerabilityManagement) {
      const { default: GroupSecurityDashboard } =
        await import('./components/shared/group_security_dashboard.vue');
      provide.securityVulnerabilitiesPath = groupSecurityVulnerabilitiesPath;
      provide.fullPath = groupFullPath;
      component = GroupSecurityDashboard;
    } else {
      const { default: LegacySecurityDashboard } =
        await import('./components/legacy/legacy_security_dashboard.vue');
      component = LegacySecurityDashboard;
    }

    props = {
      historyQuery: groupVulnerabilityHistoryQuery,
      gradesQuery: groupVulnerabilityGradesQuery,
      showExport: true,
    };
  } else if (dashboardType === DASHBOARD_TYPE_INSTANCE) {
    if (hasProjects) {
      const { default: LegacySecurityDashboard } =
        await import('./components/legacy/legacy_security_dashboard.vue');
      component = LegacySecurityDashboard;
    } else {
      component = ReportNotConfiguredInstance;
    }
    props = {
      historyQuery: instanceVulnerabilityHistoryQuery,
      gradesQuery: instanceVulnerabilityGradesQuery,
    };
  } else if (dashboardType === DASHBOARD_TYPE_PROJECT) {
    if (!hasVulnerabilities) {
      component = ReportNotConfiguredProject;
    } else if (hasAccessAdvancedVulnerabilityManagement) {
      provide.securityVulnerabilitiesPath = projectSecurityVulnerabilitiesPath;
      provide.fullPath = projectFullPath;

      if (defaultBranchContext) {
        const parsed = convertObjectPropsToCamelCase(JSON.parse(defaultBranchContext));
        provide.defaultBranchContext = {
          ...parsed,
          id: convertToGraphQLId(TYPENAME_SECURITY_PROJECT_TRACKED_CONTEXT, parsed.id),
        };
      }
      const { default: ProjectSecurityDashboard } =
        await import('./components/shared/project_security_dashboard.vue');

      component = ProjectSecurityDashboard;
    } else {
      const { default: LegacyProjectSecurityDashboard } =
        await import('./components/legacy/legacy_project_security_dashboard.vue');
      component = LegacyProjectSecurityDashboard;
    }
    props = { projectFullPath };
  } else if (dashboardType === DASHBOARD_TYPE_ORGANIZATION) {
    const { default: OrganizationSecurityDashboard } =
      await import('./components/shared/organization_security_dashboard.vue');

    component = OrganizationSecurityDashboard;
  }

  return initVueApp({
    el,
    name: 'SecurityDashboardRoot',
    pinia,
    apolloProvider,
    provide,
    component,
    props,
  });
};
