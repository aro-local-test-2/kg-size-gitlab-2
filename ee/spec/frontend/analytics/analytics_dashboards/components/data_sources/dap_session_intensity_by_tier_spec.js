import dapSessionIntensityByTier from 'ee/analytics/analytics_dashboards/data_sources/dap_session_intensity_by_tier';
import { defaultClient } from 'ee/analytics/analytics_dashboards/graphql/client';
import {
  DATE_RANGE_OPTION_LAST_7_DAYS,
  DATE_RANGE_OPTION_LAST_30_DAYS,
} from '~/explore/analytics_dashboards/components/constants';

describe('`DAP session intensity by tier` data source', () => {
  let res;

  const namespace = 'test-namespace';
  const setVisualizationOverrides = jest.fn();

  // 200 users running 4000 sessions, weighted so each tier gets a distinct intensity.
  const mockNodes = [
    { dimensions: { userTier: 'tier_0' }, usersCount: 120, totalCount: 260 },
    { dimensions: { userTier: 'tier_1' }, usersCount: 60, totalCount: 800 },
    { dimensions: { userTier: 'tier_2' }, usersCount: 16, totalCount: 1500 },
    { dimensions: { userTier: 'tier_3' }, usersCount: 4, totalCount: 1440 },
  ];

  const mockResponse = (nodes = mockNodes) => ({
    data: {
      project: null,
      group: {
        id: 'gid://gitlab/Group/1',
        analytics: {
          duoWorkflows: {
            aggregated: { nodes },
          },
        },
      },
    },
  });

  const mockResolvedQuery = (response = mockResponse()) =>
    jest.spyOn(defaultClient, 'query').mockResolvedValue(response);

  const fetch = async (args = {}) => {
    res = await dapSessionIntensityByTier({
      namespace,
      setVisualizationOverrides,
      ...args,
    });
  };

  const expectQueryWithVariables = (variables) =>
    expect(defaultClient.query).toHaveBeenCalledWith(
      expect.objectContaining({
        variables: expect.objectContaining(variables),
      }),
    );

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('with data available', () => {
    beforeEach(() => {
      mockResolvedQuery();

      return fetch();
    });

    it('makes a single request with the static thresholds and the default date range', () => {
      expect(defaultClient.query).toHaveBeenCalledTimes(1);
      expectQueryWithVariables({
        fullPath: namespace,
        startDate: '2020-06-06',
        endDate: '2020-07-06',
        thresholds: [5, 25, 100],
      });
    });

    it('returns a row per tier, most active first', () => {
      expect(res).toEqual({
        nodes: [
          {
            userTier: 'Power (100+)',
            users: {
              numerator: 4,
              denominator: 200,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            sessions: {
              numerator: 1440,
              denominator: 4000,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            intensity: { value: '18.0×', bold: true },
          },
          {
            userTier: 'Heavy (25–99)',
            users: {
              numerator: 16,
              denominator: 200,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            sessions: {
              numerator: 1500,
              denominator: 4000,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            intensity: { value: '4.7×', bold: true },
          },
          {
            userTier: 'Regular (5–24)',
            users: {
              numerator: 60,
              denominator: 200,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            sessions: {
              numerator: 800,
              denominator: 4000,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            intensity: { value: '0.7×', bold: true },
          },
          {
            userTier: 'Light (1–4)',
            users: {
              numerator: 120,
              denominator: 200,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            sessions: {
              numerator: 260,
              denominator: 4000,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            intensity: { value: '0.1×', bold: true },
          },
        ],
      });
    });

    it('sets the subtitle from the date range', () => {
      expect(setVisualizationOverrides).toHaveBeenCalledWith({
        visualizationOptionOverrides: { subtitle: 'Last 30 days' },
      });
    });
  });

  describe('with a date range filter', () => {
    beforeEach(() => {
      mockResolvedQuery();

      return fetch({ filters: { dateRangeOption: DATE_RANGE_OPTION_LAST_7_DAYS } });
    });

    it('queries the selected range', () => {
      expectQueryWithVariables({ startDate: '2020-06-29', endDate: '2020-07-06' });
    });

    it('sets the subtitle from the selected range', () => {
      expect(setVisualizationOverrides).toHaveBeenCalledWith({
        visualizationOptionOverrides: { subtitle: 'Last 7 days' },
      });
    });
  });

  describe('with a custom date range filter', () => {
    beforeEach(() => {
      mockResolvedQuery();

      return fetch({
        filters: {
          dateRangeOption: DATE_RANGE_OPTION_LAST_30_DAYS,
          startDate: new Date('2020-01-01'),
          endDate: new Date('2020-02-01'),
        },
      });
    });

    it('queries the supplied bounds', () => {
      expectQueryWithVariables({ startDate: '2020-01-01', endDate: '2020-02-01' });
    });
  });

  describe('with a project namespace', () => {
    beforeEach(() => {
      const { data } = mockResponse();
      mockResolvedQuery({ data: { group: null, project: data.group } });

      return fetch();
    });

    it('reads the response from the project', () => {
      expect(res.nodes).toHaveLength(4);
    });
  });

  describe('with unrecognised tiers in the response', () => {
    beforeEach(() => {
      mockResolvedQuery(
        mockResponse([
          { dimensions: { userTier: null }, usersCount: 5, totalCount: 5 },
          { dimensions: { userTier: 'not_a_tier' }, usersCount: 5, totalCount: 5 },
          { dimensions: { userTier: 'tier_0' }, usersCount: 10, totalCount: 20 },
        ]),
      );

      return fetch();
    });

    it('drops them, and excludes their counts from the totals', () => {
      expect(res).toEqual({
        nodes: [
          {
            userTier: 'Light (1–4)',
            users: {
              numerator: 10,
              denominator: 10,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            sessions: {
              numerator: 20,
              denominator: 20,
              variant: 'NUMERATOR_WITH_PERCENT',
            },
            intensity: { value: '1.0×', bold: true },
          },
        ],
      });
    });
  });

  describe('when a tier reports no users and no sessions', () => {
    beforeEach(() => {
      mockResolvedQuery(
        mockResponse([{ dimensions: { userTier: 'tier_0' }, usersCount: 0, totalCount: 0 }]),
      );

      return fetch();
    });

    it('renders a placeholder intensity rather than dividing by zero', () => {
      expect(res.nodes[0].intensity).toEqual({ value: '-' });
    });
  });

  it('returns no data when the response has no nodes', async () => {
    mockResolvedQuery(mockResponse([]));

    await fetch();

    expect(res).toEqual({});
  });

  it('returns no data when no node has a recognised tier', async () => {
    mockResolvedQuery(
      mockResponse([{ dimensions: { userTier: 'not_a_tier' }, usersCount: 5, totalCount: 5 }]),
    );

    await fetch();

    expect(res).toEqual({});
  });
});
