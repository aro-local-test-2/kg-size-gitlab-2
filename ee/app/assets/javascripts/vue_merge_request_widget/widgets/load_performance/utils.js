import { __, n__, s__, sprintf } from '~/locale';
import { formattedChangeInPercent } from '~/lib/utils/number_utils';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';

const formatScore = (value) => {
  if (Number(value) && !Number.isInteger(value)) {
    return (Math.floor(parseFloat(value) * 100) / 100).toFixed(2);
  }
  return value;
};

const prepareMetricData = (metricData, icon) => {
  const preparedMetricData = metricData;

  const prefix = metricData.score ? `${metricData.name}:` : metricData.name;
  const score = metricData.score
    ? `%{strong_start}${formatScore(metricData.score)}%{strong_end}`
    : '';
  const delta = metricData.delta ? `(${formatScore(metricData.delta)})` : '';
  let deltaPercent = '';

  if (metricData.delta && metricData.score) {
    const oldScore = parseFloat(metricData.score) - metricData.delta;
    deltaPercent = `(${formattedChangeInPercent(oldScore, metricData.score)})`;
  }

  preparedMetricData.icon = icon;
  preparedMetricData.text = `${prefix} ${score} ${delta} ${deltaPercent}`;

  return preparedMetricData;
};

const normalizeLoadPerformanceMetrics = (loadPerformanceData) => {
  if (!loadPerformanceData || !('metrics' in loadPerformanceData)) return {};

  const { metrics } = loadPerformanceData;
  const indexedMetrics = {};

  Object.keys(metrics).forEach((metric) => {
    switch (metric) {
      case 'http_reqs':
        indexedMetrics[s__('ciReport|RPS')] = metrics.http_reqs.rate;
        break;
      case 'http_req_waiting':
        indexedMetrics[s__('ciReport|TTFB P90')] = metrics.http_req_waiting['p(90)'];
        indexedMetrics[s__('ciReport|TTFB P95')] = metrics.http_req_waiting['p(95)'];
        break;
      case 'checks':
        indexedMetrics[s__('ciReport|Checks')] = `${(
          (metrics.checks.passes / (metrics.checks.passes + metrics.checks.fails)) *
          100.0
        ).toFixed(2)}%`;
        break;
      default:
        break;
    }
  });

  return indexedMetrics;
};

export const compareLoadPerformanceMetrics = (headMetrics, baseMetrics) => {
  const headMetricsIndexed = normalizeLoadPerformanceMetrics(headMetrics);
  const baseMetricsIndexed = normalizeLoadPerformanceMetrics(baseMetrics);
  const improved = [];
  const degraded = [];
  const same = [];

  Object.keys(headMetricsIndexed).forEach((metric) => {
    if (!(metric in baseMetricsIndexed)) return;

    const metricData = {
      name: metric,
      score: headMetricsIndexed[metric],
      delta: parseFloat(
        (parseFloat(headMetricsIndexed[metric]) - parseFloat(baseMetricsIndexed[metric])).toFixed(
          2,
        ),
      ),
    };

    if (metricData.delta === 0.0) {
      same.push(prepareMetricData(metricData, { name: EXTENSION_ICONS.neutral }));
      return;
    }

    const isImproved = [s__('ciReport|RPS'), s__('ciReport|Checks')].includes(metric)
      ? metricData.delta > 0
      : metricData.delta < 0;

    if (isImproved) {
      improved.push(prepareMetricData(metricData, { name: EXTENSION_ICONS.success }));
    } else {
      degraded.push(prepareMetricData(metricData, { name: EXTENSION_ICONS.failed }));
    }
  });

  return { improved, degraded, same };
};

export const loadPerformanceSummary = ({ improved = [], degraded = [], same = [] }) => {
  const changesFound = improved.length + degraded.length + same.length;

  return {
    title: sprintf(
      n__(
        'ciReport|Load performance test metrics detected %{strong_start}%{changesFound}%{strong_end} change',
        'ciReport|Load performance test metrics detected %{strong_start}%{changesFound}%{strong_end} changes',
        changesFound,
      ),
      { changesFound },
    ),
    subtitle: sprintf(
      s__(
        'ciReport|%{danger_start}%{degradedNum} degraded%{danger_end}, %{same_start}%{sameNum} same%{same_end}, and %{success_start}%{improvedNum} improved%{success_end}',
      ),
      {
        degradedNum: degraded.length,
        sameNum: same.length,
        improvedNum: improved.length,
      },
    ),
  };
};

export const loadPerformanceStatusIcon = ({ degraded = [], same = [] }) =>
  degraded.length > 0 || same.length > 0 ? EXTENSION_ICONS.warning : EXTENSION_ICONS.success;

export const loadPerformanceSections = ({ improved = [], degraded = [], same = [] }) =>
  [
    { header: __('Improved'), children: improved },
    { header: __('Degraded'), children: degraded },
    { header: __('No changes'), children: same },
  ].filter(({ children }) => children.length > 0);
