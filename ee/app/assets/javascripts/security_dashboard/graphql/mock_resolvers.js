import { getStartOfDay, nDaysAfter } from '~/lib/utils/datetime/date_calculation_utility';
import { formatDate } from '~/lib/utils/datetime_utility';
import {
  SEVERITY_LEVELS_GRAPHQL,
  REPORT_TYPES_DEFAULT_KEYS,
} from 'ee/security_dashboard/constants';

const REPORT_TYPES_GRAPHQL = REPORT_TYPES_DEFAULT_KEYS.map((key) => key.toUpperCase());
const MOCK_LATENCY_MS = 300;
// Zero-based week with no remediations at all, so the "All" view also shows a gap and its tooltip.
const EMPTY_WEEK_INDEX = 3;

// Pause before resolving so the panel renders its loading state.
const delay = () =>
  new Promise((resolve) => {
    setTimeout(resolve, MOCK_LATENCY_MS);
  });

// Deterministic 0–1 pseudo-random, so a given week/series always mocks the same numbers.
const seeded = (n) => {
  const value = Math.sin(n) * 10000;
  return value - Math.floor(value);
};

const round1 = (value) => Math.round(value * 10) / 10;

const toLocalDate = (isoDate) => {
  const [year, month, day] = isoDate.split('-').map(Number);
  return new Date(year, month - 1, day);
};

const mttrOf = (sumDays, count) => (count ? round1(sumDays / count) : null);

const metricFor = (weekIndex, seriesIndex) => {
  if (weekIndex === EMPTY_WEEK_INDEX) return { count: 0, sumDays: 0, mttr: null };

  const count = Math.round(seeded(weekIndex * 7 + seriesIndex + 1) * 12);
  const avgDays = 5 + seeded(weekIndex * 13 + seriesIndex + 2) * 40;
  const sumDays = round1(count * avgDays);
  return { count, sumDays, mttr: mttrOf(sumDays, count) };
};

const buildBucket = ({ weekIndex, weekStart, weekEnd, severities }) => {
  const bySeverity = severities.map((severity, seriesIndex) => ({
    __typename: 'MttrOverTimeBySeverity',
    severity,
    ...metricFor(weekIndex, seriesIndex),
  }));

  const byReportType = REPORT_TYPES_GRAPHQL.map((reportType, seriesIndex) => ({
    __typename: 'MttrOverTimeByReportType',
    reportType,
    ...metricFor(weekIndex, seriesIndex + 100),
  }));

  const count = bySeverity.reduce((sum, { count: c }) => sum + c, 0);
  const sumDays = round1(bySeverity.reduce((sum, { sumDays: s }) => sum + s, 0));

  return {
    __typename: 'MttrOverTimeBucket',
    startDate: formatDate(weekStart, 'isoDate'),
    endDate: formatDate(weekEnd, 'isoDate'),
    count,
    sumDays,
    mttr: mttrOf(sumDays, count),
    bySeverity,
    byReportType,
  };
};

const mttrOverTime = async (_securityMetrics, { startDate, endDate, severity }) => {
  await delay();

  // An empty/absent severity filter means all severities.
  const severities = severity?.length ? severity : SEVERITY_LEVELS_GRAPHQL;
  const rangeEnd = toLocalDate(endDate);
  const today = getStartOfDay(new Date());

  const buckets = [];
  let weekStart = toLocalDate(startDate);
  let weekIndex = 0;

  while (weekStart <= rangeEnd) {
    const weekEnd = nDaysAfter(weekStart, 6);
    // Cap the final week at today, so the most recent bucket may be partial.
    buckets.push(
      buildBucket({ weekIndex, weekStart, weekEnd: weekEnd > today ? today : weekEnd, severities }),
    );
    weekStart = nDaysAfter(weekStart, 7);
    weekIndex += 1;
  }

  return buckets;
};

export const mockResolvers = {
  SecurityMetrics: {
    mttrOverTime,
  },
};
