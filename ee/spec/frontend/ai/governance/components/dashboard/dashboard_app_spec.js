import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import AiGovernanceDashboardApp from 'ee/ai/governance/components/dashboard/dashboard_app.vue';
import AuditTrailCard from 'ee/ai/governance/components/dashboard/cards/audit_trail_card.vue';
import AgentInventoryCard from 'ee/ai/governance/components/dashboard/cards/agent_inventory_card.vue';
import getAiGovernanceMetricsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_metrics.query.graphql';

Vue.use(VueApollo);

const GROUP_FULL_PATH = 'gitlab-org';

const point = (c, i) => ({ bucketStart: `2026-07-2${i}T00:00:00Z`, count: c });

const kpi = (count, previousCount, counts) => ({
  count,
  previousCount,
  trend: counts.map(point),
  cumulativeTrend: null,
});

const withCumulativeTrend = (base, counts) => ({ ...base, cumulativeTrend: counts.map(point) });

const metricsResponse = {
  data: {
    group: {
      id: 'gid://gitlab/Group/1',
      aiGovernanceMetrics: {
        agents: kpi(12, 8, [8, 10, 12]),
        sessions: kpi(40, 55, [55, 48, 40]),
      },
    },
  },
};

describe('AiGovernanceDashboardApp', () => {
  let wrapper;

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(metricsResponse),
    glFeatures = { aiGovernanceMcpServerActivity: true, aiGovernanceConnectedAgentsFilter: true },
    provide = {},
  } = {}) => {
    const apolloProvider = createMockApollo([[getAiGovernanceMetricsQuery, handler]]);

    wrapper = shallowMountExtended(AiGovernanceDashboardApp, {
      apolloProvider,
      provide: {
        groupFullPath: GROUP_FULL_PATH,
        projectFullPath: '',
        projectId: null,
        glFeatures,
        ...provide,
      },
    });
  };

  const findSummaryMetric = (key) => wrapper.findComponentByTestId(`summary-metric-${key}`);
  const findCard = (key) => wrapper.findByTestId(`dashboard-card-${key}`);
  const findAgentClassFilter = () => wrapper.findComponentByTestId('agent-class-filter');
  const findTimeframeFilter = () => wrapper.findComponentByTestId('timeframe-filter');

  describe('summary header', () => {
    beforeEach(() => createComponent());

    it.each(['agents', 'sessions'])('renders the %s summary metric', (key) => {
      expect(findSummaryMetric(key).exists()).toBe(true);
    });

    it('does not render a compliance posture tile', () => {
      expect(findSummaryMetric('posture').exists()).toBe(false);
    });
  });

  describe('metrics wiring', () => {
    it('requests group metrics with the default timeframe and agent class', async () => {
      const handler = jest.fn().mockResolvedValue(metricsResponse);
      createComponent({ handler });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({
          groupFullPath: GROUP_FULL_PATH,
          isProject: false,
          timeframe: 'LAST_7_DAYS',
          agentClass: 'ALL',
        }),
      );
    });

    it('re-queries with the selected agent class when the filter changes', async () => {
      const handler = jest.fn().mockResolvedValue(metricsResponse);
      createComponent({ handler });
      await waitForPromises();

      findAgentClassFilter().vm.$emit('input', 'EXTERNAL');
      await waitForPromises();

      expect(handler).toHaveBeenLastCalledWith(expect.objectContaining({ agentClass: 'EXTERNAL' }));
    });

    it.each(['audit-trail', 'agent-inventory', 'developer-activity', 'project-exposure'])(
      'passes the selected agent class down to the %s card',
      async (key) => {
        createComponent();
        await waitForPromises();

        expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('agentClass')).toBe(
          'ALL',
        );

        findAgentClassFilter().vm.$emit('input', 'INTERNAL_DAP');
        await waitForPromises();

        expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('agentClass')).toBe(
          'INTERNAL_DAP',
        );
      },
    );

    describe('date range filter', () => {
      it('offers only the 7 and 30 day windows', () => {
        createComponent();

        expect(findTimeframeFilter().props('options')).toEqual([
          { value: 'LAST_7_DAYS', text: 'Last 7 days' },
          { value: 'LAST_30_DAYS', text: 'Last 30 days' },
        ]);
      });

      it('queries the selected window', async () => {
        const handler = jest.fn().mockResolvedValue(metricsResponse);
        createComponent({ handler });
        await waitForPromises();

        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ timeframe: 'LAST_7_DAYS' }));
      });

      it('re-queries with LAST_30_DAYS when picked', async () => {
        const handler = jest.fn().mockResolvedValue(metricsResponse);
        createComponent({ handler });
        await waitForPromises();

        findTimeframeFilter().vm.$emit('input', 'LAST_30_DAYS');
        await waitForPromises();

        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ timeframe: 'LAST_30_DAYS' }),
        );
      });

      it.each(['developer-activity', 'project-exposure'])(
        'passes the selected window down to the %s card',
        async (key) => {
          createComponent();
          await waitForPromises();

          expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('timeframe')).toBe(
            'LAST_7_DAYS',
          );

          findTimeframeFilter().vm.$emit('input', 'LAST_30_DAYS');
          await waitForPromises();

          expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('timeframe')).toBe(
            'LAST_30_DAYS',
          );
        },
      );

      it('relabels the tile delta for the selected window', async () => {
        createComponent();
        await waitForPromises();

        expect(findSummaryMetric('agents').props('delta')).toBe('+4 this week');

        findTimeframeFilter().vm.$emit('input', 'LAST_30_DAYS');
        await waitForPromises();

        expect(findSummaryMetric('agents').props('delta')).toBe('+4 this month');
      });
    });

    describe('with the connected agents filter disabled', () => {
      const dapOnly = { aiGovernanceMcpServerActivity: true };

      it('offers DAP as the only agent class', () => {
        createComponent({ glFeatures: dapOnly });

        expect(findAgentClassFilter().props('options')).toEqual([
          { value: 'INTERNAL_DAP', text: 'DAP' },
        ]);
      });

      it('queries DAP metrics rather than all agents', async () => {
        const handler = jest.fn().mockResolvedValue(metricsResponse);
        createComponent({ glFeatures: dapOnly, handler });
        await waitForPromises();

        expect(handler).toHaveBeenCalledWith(
          expect.objectContaining({ agentClass: 'INTERNAL_DAP' }),
        );
      });

      it.each(['audit-trail', 'agent-inventory', 'developer-activity', 'project-exposure'])(
        'scopes the %s card to DAP',
        async (key) => {
          createComponent({ glFeatures: dapOnly });
          await waitForPromises();

          expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('agentClass')).toBe(
            'INTERNAL_DAP',
          );
        },
      );
    });

    it('maps a rising KPI to an up delta and a trend sparkline', async () => {
      createComponent();
      await waitForPromises();

      const agents = findSummaryMetric('agents');
      expect(agents.props('value')).toBe('12');
      expect(agents.props('delta')).toBe('+4 this week');
      expect(agents.props('deltaDirection')).toBe('up');

      // No cumulativeTrend in this fixture, so the tile falls back to `trend`.
      const chartData = agents.props('chartData');
      expect(chartData.map((p) => p[1])).toEqual([8, 10, 12]);
      // x-axis is a formatted date label (from bucketStart), not a bare index.
      expect(typeof chartData[0][0]).toBe('string');
    });

    it('charts cumulativeTrend in preference to trend when the backend returns it', async () => {
      const withCumulative = {
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            aiGovernanceMetrics: {
              agents: withCumulativeTrend(kpi(12, 8, [8, 10, 12]), [40, 44, 52]),
              sessions: withCumulativeTrend(kpi(40, 55, [55, 48, 40]), [100, 148, 188]),
            },
          },
        },
      };
      createComponent({ handler: jest.fn().mockResolvedValue(withCumulative) });
      await waitForPromises();

      expect(
        findSummaryMetric('agents')
          .props('chartData')
          .map((p) => p[1]),
      ).toEqual([40, 44, 52]);
      expect(
        findSummaryMetric('sessions')
          .props('chartData')
          .map((p) => p[1]),
      ).toEqual([100, 148, 188]);
    });

    it('falls back to trend when cumulativeTrend comes back empty', async () => {
      const emptyCumulative = {
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            aiGovernanceMetrics: {
              agents: withCumulativeTrend(kpi(12, 8, [8, 10, 12]), []),
              sessions: kpi(40, 55, [55, 48, 40]),
            },
          },
        },
      };
      createComponent({ handler: jest.fn().mockResolvedValue(emptyCumulative) });
      await waitForPromises();

      expect(
        findSummaryMetric('agents')
          .props('chartData')
          .map((p) => p[1]),
      ).toEqual([8, 10, 12]);
    });

    it('maps a falling KPI to a down delta', async () => {
      createComponent();
      await waitForPromises();

      const sessions = findSummaryMetric('sessions');
      expect(sessions.props('value')).toBe('40');
      expect(sessions.props('delta')).toBe('-15 this week');
      expect(sessions.props('deltaDirection')).toBe('down');
    });

    it('falls back to a neutral placeholder when metrics are unavailable', async () => {
      const nullResponse = {
        data: { group: { id: 'gid://gitlab/Group/1', aiGovernanceMetrics: null } },
      };
      createComponent({ handler: jest.fn().mockResolvedValue(nullResponse) });
      await waitForPromises();

      const agents = findSummaryMetric('agents');
      expect(agents.props('value')).toBe('—');
    });
  });

  describe('data-backed cards', () => {
    beforeEach(() => createComponent());

    it('renders the Audit logs card', () => {
      expect(wrapper.findComponent(AuditTrailCard).exists()).toBe(true);
      expect(findCard('audit-trail').exists()).toBe(true);
    });

    it('renders the AI agent inventory card', () => {
      expect(wrapper.findComponent(AgentInventoryCard).exists()).toBe(true);
      expect(findCard('agent-inventory').exists()).toBe(true);
    });

    it('renders the Developer activity card', () => {
      expect(findCard('developer-activity').exists()).toBe(true);
    });

    it('renders the MCP server activity card when its feature flag is on', () => {
      expect(findCard('mcp-server-activity').exists()).toBe(true);
    });

    it('hides the MCP server activity card when its feature flag is off', () => {
      createComponent({ glFeatures: { aiGovernanceMcpServerActivity: false } });

      expect(findCard('mcp-server-activity').exists()).toBe(false);
    });

    it('renders the Project exposure card', () => {
      expect(findCard('project-exposure').exists()).toBe(true);
    });

    it('does not segment the MCP servers card by agent class', () => {
      // The card declares no agentClass prop, so a stray template binding would
      // arrive as an attribute; asserting on props passes either way.
      const mcpCard = wrapper.findComponentByTestId('dashboard-card-mcp-server-activity');

      expect(mcpCard.attributes('agent-class')).toBeUndefined();
    });

    it('renders the SkillGuard card when its feature flag is on', () => {
      createComponent({ glFeatures: { aiGovernanceSkillguardWidget: true } });

      expect(findCard('skillguard').exists()).toBe(true);
    });

    it('hides the SkillGuard card when its feature flag is off', () => {
      createComponent({ glFeatures: { aiGovernanceSkillguardWidget: false } });

      expect(findCard('skillguard').exists()).toBe(false);
    });

    it('renders the SkillGuard card at project scope too', () => {
      createComponent({
        glFeatures: { aiGovernanceSkillguardWidget: true },
        provide: { projectId: '1', projectFullPath: 'gitlab-duo/test' },
      });

      expect(findCard('skillguard').exists()).toBe(true);
    });

    it('renders the MCP server activity card last', () => {
      const order = wrapper
        .findAll('[data-testid^="dashboard-card-"]')
        .wrappers.map((w) => w.attributes('data-testid'));

      expect(order.at(-1)).toBe('dashboard-card-mcp-server-activity');
    });
  });
});
