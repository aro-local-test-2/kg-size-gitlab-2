import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import apolloProvider from 'ee/security_dashboard/graphql/provider';
import { fromHaml } from 'ee/vulnerabilities/components/vulnerability_details_enrichment/adapters/from_haml';
import { parseBoolean } from '~/lib/utils/common_utils';
import { DISMISSAL_REASON_DESCRIPTIONS } from 'ee/vulnerabilities/constants';
import VulnerabilityDetailsEnrichment from 'ee/vulnerabilities/components/vulnerability_details_enrichment/index.vue';

const initVulnerabilityDetails = (el) => {
  // Reshape the HAML payload into the GraphQL query response shape so the page
  // is already built against the eventual GraphQL contract (see the adapter).
  // `viewLayerPaths` are the help-doc paths, route URLs, and REST endpoints the
  // reused Related section components (related_issues.vue, related_jira_issues.vue,
  // create_jira_issue.vue) and the header actions (vulnerability_actions.vue,
  // `createMrUrl`) read via inject. They are view-layer values GraphQL is
  // unlikely to expose, so they stay sourced from the payload rather than the
  // reshaped `vulnerability`, and are read off the same payload the adapter already
  // parsed so we don't parse `el.dataset.vulnerability` a second time (#601897).
  const { vulnerability, viewLayerPaths } = fromHaml(el.dataset);
  const {
    projectFullPath,
    defaultBranch,
    commitPathTemplate,
    canViewFalsePositive,
    duoAgentPlatformAvailable,
    duoSecretDetectionFpEnabled,
    duoSastFalsePositiveDetectionEnabled,
  } = el.dataset;

  return initVueApp({
    el,
    name: 'VulnerabilityDetails',
    apolloProvider,
    provide: {
      // Declared on the FE rather than injected from HAML; mirrors the backend
      // enum descriptions and reuses the shared `.po` catalog.
      dismissalDescriptions: DISMISSAL_REASON_DESCRIPTIONS,
      projectFullPath,
      defaultBranch,
      // Read by the Evidence panel's `commit` generic-report node to build its
      // commit link (generic_report/types/report_type_commit.vue).
      commitPathTemplate,
      // View-layer paths legacy bridge (#601897); carries the Related section
      // endpoints and the header actions' `createMrUrl`. `vulnerabilityId` and
      // `canModifyRelatedIssues` are intentionally absent: index.vue owns the
      // normalized numeric id (provided once for the inject-based subtrees) and
      // the `userPermissions.adminVulnerabilityIssueLink` permission, and threads
      // both down as props.
      ...viewLayerPaths,
      canViewFalsePositive: parseBoolean(canViewFalsePositive),
      customizeJiraIssueEnabled: parseBoolean(el.dataset.customizeJiraIssueEnabled),
      duoAgentPlatformAvailable: parseBoolean(duoAgentPlatformAvailable),
      duoSecretDetectionFpEnabled: parseBoolean(duoSecretDetectionFpEnabled),
      duoSastFalsePositiveDetectionEnabled: parseBoolean(duoSastFalsePositiveDetectionEnabled),
    },
    component: VulnerabilityDetailsEnrichment,
    props: { vulnerability },
  });
};

export default (el) => {
  if (!el) {
    return null;
  }

  return initVulnerabilityDetails(el);
};
