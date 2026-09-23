import { toISODateFormat } from '~/lib/utils/datetime_utility';
import { formatNumber } from '~/locale';
import { DATE_RANGE_OPTION_LAST_30_DAYS } from '~/explore/analytics_dashboards/components/constants';
import { resolveDateRangeFilter } from '~/explore/analytics_dashboards/components/utils';
import { extractQueryResponseFromNamespace } from '~/analytics/shared/utils';
import { calculateRate } from '~/analytics/dashboards/ai_impact/utils';
import { TIER_NAMES, TIER_THRESHOLDS, tierIndexOf } from '~/glql/utils/tier_band';
import { PERCENT_VARIANTS } from '~/analytics/analytics_dashboards/components/visualizations/data_table/calculate_percent.vue';
import DapSessionIntensityByTierQuery from '~/analytics/dashboards/ai_impact/graphql/dap_session_intensity_by_tier.query.graphql';
import { defaultClient } from '../graphql/client';

const shareOfTotal = (numerator, denominator) => ({
  numerator,
  denominator,
  variant: PERCENT_VARIANTS.NUMERATOR_WITH_PERCENT,
});

// Sessions share over users share: above 1 the tier accounts for more of the sessions than its
// share of users would predict, so those users are individually more active.
const buildIntensity = ({ usersCount, totalUsers, totalCount, totalSessions }) => {
  const sessionsShare = calculateRate({
    numerator: totalCount,
    denominator: totalSessions,
    asDecimal: true,
  });
  const usersShare = calculateRate({
    numerator: usersCount,
    denominator: totalUsers,
    asDecimal: true,
  });

  // A zero users share cannot be divided by either, so it fails the same way an invalid one does.
  if (sessionsShare === null || !usersShare) return { value: '-' };

  return {
    value: `${formatNumber(sessionsShare / usersShare, {
      minimumFractionDigits: 1,
      maximumFractionDigits: 1,
    })}×`,
    bold: true,
  };
};

const buildTierRows = (nodes) => {
  const tiers = nodes
    .map((node) => ({ ...node, tierIndex: tierIndexOf(node.dimensions?.userTier) }))
    .filter(({ tierIndex }) => tierIndex !== null)
    .sort((a, b) => b.tierIndex - a.tierIndex);

  // Both shares are proportions of the rows on screen, so the totals come from the response
  // rather than a second, unfiltered request.
  const totalUsers = tiers.reduce((total, { usersCount }) => total + usersCount, 0);
  const totalSessions = tiers.reduce((total, { totalCount }) => total + totalCount, 0);

  return tiers.map(({ tierIndex, usersCount, totalCount }) => ({
    userTier: TIER_NAMES[tierIndex],
    users: shareOfTotal(usersCount, totalUsers),
    sessions: shareOfTotal(totalCount, totalSessions),
    intensity: buildIntensity({ usersCount, totalUsers, totalCount, totalSessions }),
  }));
};

export default async function fetch({
  namespace,
  filters = {},
  setVisualizationOverrides = () => {},
}) {
  const {
    startDate,
    endDate,
    text: subtitle,
  } = resolveDateRangeFilter(filters, DATE_RANGE_OPTION_LAST_30_DAYS);

  setVisualizationOverrides({ visualizationOptionOverrides: { subtitle } });

  const result = await defaultClient.query({
    query: DapSessionIntensityByTierQuery,
    variables: {
      fullPath: namespace,
      startDate: toISODateFormat(startDate, true),
      endDate: toISODateFormat(endDate, true),
      thresholds: TIER_THRESHOLDS,
    },
  });

  const { duoWorkflows } = extractQueryResponseFromNamespace({ result, resultKey: 'analytics' });
  const nodes = buildTierRows(duoWorkflows?.aggregated?.nodes ?? []);

  if (!nodes.length) return {};

  return { nodes };
}
