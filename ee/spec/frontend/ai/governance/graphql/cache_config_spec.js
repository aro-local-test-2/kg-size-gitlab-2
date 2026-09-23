import { InMemoryCache } from '@apollo/client/core';
import { cacheConfig } from 'ee/ai/governance/graphql/cache_config';
import getAiGovernanceMetricsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_metrics.query.graphql';
import getDeveloperActivityQuery from 'ee/ai/governance/graphql/queries/get_developer_activity.query.graphql';
import getProjectExposureQuery from 'ee/ai/governance/graphql/queries/get_project_exposure.query.graphql';

const sharedVariables = {
  groupFullPath: 'gitlab-duo',
  projectFullPath: '',
  isProject: false,
  agentClass: 'ALL',
  timeframe: 'LAST_7_DAYS',
};

const kpi = (count) => ({
  __typename: 'AiGovernanceKpi',
  count,
  previousCount: count - 1,
  trend: [{ __typename: 'AiGovernanceKpiTrendPoint', bucketStart: '2026-09-17T00:00:00Z', count }],
  cumulativeTrend: [
    { __typename: 'AiGovernanceKpiTrendPoint', bucketStart: '2026-09-17T00:00:00Z', count },
  ],
});

const group = (metrics) => ({
  group: {
    __typename: 'Group',
    id: 'gid://gitlab/Group/1',
    aiGovernanceMetrics: { __typename: 'AiGovernanceMetrics', ...metrics },
  },
});

const metricsData = group({ agents: kpi(20), sessions: kpi(110) });

const developerActivityData = group({
  topUsers: [
    {
      __typename: 'AiGovernanceUserActivity',
      sessionCount: 63,
      user: {
        __typename: 'UserCore',
        id: 'gid://gitlab/User/1',
        name: 'User 1',
        username: 'user1',
        avatarUrl: '/avatar.png',
        webUrl: '/user1',
      },
    },
  ],
});

const projectExposureData = group({
  topProjects: [
    {
      __typename: 'AiGovernanceProjectActivity',
      sessionCount: 23,
      project: {
        __typename: 'Project',
        id: 'gid://gitlab/Project/1',
        name: 'project-1',
        fullPath: 'acme/project-1',
        nameWithNamespace: 'Acme / project-1',
        webUrl: '/acme/project-1',
      },
    },
  ],
});

// AiGovernanceMetrics has no `id`, so Apollo cannot normalize it. All three
// dashboard queries select it on the same Group with the same arguments, which
// means one cache entry holding three disjoint field sets.
describe('AI Governance Apollo cache config', () => {
  let cache;

  const writeAll = () => {
    cache.writeQuery({
      query: getAiGovernanceMetricsQuery,
      variables: sharedVariables,
      data: metricsData,
    });
    cache.writeQuery({
      query: getDeveloperActivityQuery,
      variables: { ...sharedVariables, limit: 5 },
      data: developerActivityData,
    });
    cache.writeQuery({
      query: getProjectExposureQuery,
      variables: { ...sharedVariables, limit: 5 },
      data: projectExposureData,
    });
  };

  describe('when all three dashboard queries have written to the cache', () => {
    beforeEach(() => {
      cache = new InMemoryCache(cacheConfig);
      writeAll();
    });

    it('keeps the summary metrics readable', () => {
      const result = cache.readQuery({
        query: getAiGovernanceMetricsQuery,
        variables: sharedVariables,
      });

      expect(result.group.aiGovernanceMetrics.agents.count).toBe(20);
      expect(result.group.aiGovernanceMetrics.sessions.count).toBe(110);
    });

    it('keeps the developer activity ranking readable', () => {
      const result = cache.readQuery({
        query: getDeveloperActivityQuery,
        variables: { ...sharedVariables, limit: 5 },
      });

      expect(result.group.aiGovernanceMetrics.topUsers).toHaveLength(1);
      expect(result.group.aiGovernanceMetrics.topUsers[0].sessionCount).toBe(63);
    });

    it('keeps the project exposure ranking readable', () => {
      const result = cache.readQuery({
        query: getProjectExposureQuery,
        variables: { ...sharedVariables, limit: 5 },
      });

      expect(result.group.aiGovernanceMetrics.topProjects).toHaveLength(1);
      expect(result.group.aiGovernanceMetrics.topProjects[0].sessionCount).toBe(23);
    });
  });
});
