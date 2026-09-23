import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import resolvers from 'ee/vue_shared/security_configuration/graphql/resolvers/resolvers';
import { typePolicies } from 'ee/vue_shared/security_configuration/graphql/provider';
import getGroupProjects from 'ee/security_orchestration/graphql/queries/get_group_projects.query.graphql';
import securityPolicyProjectCreated from 'ee/security_orchestration/graphql/queries/security_policy_project_created.subscription.graphql';
import { mockPageInfo } from 'ee_jest/groups/settings/compliance_frameworks/mock_data';
import getSppLinkedProjectsGroups from 'ee/security_orchestration/graphql/queries/get_spp_linked_projects_groups.graphql';
import dastScannerProfilesQuery from 'ee/security_configuration/dast_profiles/graphql/dast_scanner_profiles.query.graphql';
import dastSiteProfilesQuery from 'ee/security_configuration/dast_profiles/graphql/dast_site_profiles.query.graphql';
import { createSppSubscriptionHandler } from './utils';

const getGroupProjectsHandler = () =>
  jest.fn().mockResolvedValue({
    data: {
      id: 1,
      group: {
        id: 2,
        projects: {
          nodes: [],
        },
      },
    },
  });

export const createSppLinkedItemsHandler = ({ projects = [], namespaces = [], groups = [] } = {}) =>
  jest.fn().mockResolvedValue({
    data: {
      project: {
        id: '1',
        securityPolicyProjectLinkedProjects: {
          nodes: projects,
          pageInfo: mockPageInfo(),
        },
        securityPolicyProjectLinkedNamespaces: {
          nodes: namespaces,
          pageInfo: mockPageInfo(),
        },
        securityPolicyProjectLinkedGroups: {
          nodes: groups,
          pageInfo: mockPageInfo(),
        },
      },
    },
  });

const dastProfilesHandler = (profileType) =>
  jest.fn().mockResolvedValue({
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        [profileType]: { nodes: [], pageInfo: mockPageInfo() },
      },
    },
  });

// The DAST profile selector only renders in the scan execution editor, so these
// stay opt-in rather than loading for every policy type.
export const dastProfileHandlers = () => [
  [dastScannerProfilesQuery, dastProfilesHandler('scannerProfiles')],
  [dastSiteProfilesQuery, dastProfilesHandler('siteProfiles')],
];

// mock-apollo-client rejects a duplicate handler, so a caller-supplied one
// replaces the default for the same query rather than being appended to it.
const withOverrides = (defaults, handlers) => {
  const overridden = new Set(handlers.map(([query]) => query));

  return [...defaults.filter(([query]) => !overridden.has(query)), ...handlers];
};

export const createMockApolloProvider = (handlers = []) => {
  Vue.use(VueApollo);
  return createMockApollo(
    withOverrides(
      [
        [getGroupProjects, getGroupProjectsHandler()],
        [getSppLinkedProjectsGroups, createSppLinkedItemsHandler()],
        [securityPolicyProjectCreated, createSppSubscriptionHandler()],
      ],
      handlers,
    ),
    // The DAST profile selector reads client-only security configuration state:
    // typePolicies supply the default sharedData, resolvers its mutations.
    resolvers,
    { typePolicies },
  );
};
