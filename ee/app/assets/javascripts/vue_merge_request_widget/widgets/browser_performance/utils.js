import { n__, s__, sprintf } from '~/locale';
import { formattedChangeInPercent } from '~/lib/utils/number_utils';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';

const formatScore = (value) => {
  if (Number(value) && !Number.isInteger(value)) {
    return (Math.floor(parseFloat(value) * 100) / 100).toFixed(2);
  }

  return value;
};

const prepareMetricData = (metricData, iconName) => {
  const prefix = metricData.score ? `${metricData.name}:` : metricData.name;
  const score = metricData.score ? `${formatScore(metricData.score)}` : '';
  const delta = metricData.delta ? `(${formatScore(metricData.delta)})` : '';
  const { path } = metricData;
  let deltaPercent = '';

  if (metricData.delta && metricData.score) {
    const oldScore = parseFloat(metricData.score) - metricData.delta;
    deltaPercent = `(${formattedChangeInPercent(oldScore, metricData.score)})`;
  }

  const text = sprintf(
    s__(
      'ciReport|%{prefix} %{strong_start}%{score}%{strong_end} %{delta} %{deltaPercent} in %{path}',
    ),
    {
      prefix,
      score,
      delta,
      deltaPercent,
      path,
    },
    false,
  );

  return { ...metricData, icon: { name: iconName }, text };
};

const normalizeBrowserPerformanceMetrics = (browserPerformanceData) => {
  const indexedSubjects = {};

  if (!Array.isArray(browserPerformanceData)) return indexedSubjects;

  browserPerformanceData.forEach(({ subject, metrics }) => {
    const indexedMetrics = {};

    metrics.forEach(({ name, ...data }) => {
      indexedMetrics[name] = data;
    });

    indexedSubjects[subject] = indexedMetrics;
  });

  return indexedSubjects;
};

export const compareBrowserPerformanceMetrics = (headMetrics = [], baseMetrics = []) => {
  const headMetricsIndexed = normalizeBrowserPerformanceMetrics(headMetrics);
  const baseMetricsIndexed = normalizeBrowserPerformanceMetrics(baseMetrics);
  const improved = [];
  const degraded = [];
  const same = [];

  Object.keys(headMetricsIndexed).forEach((subject) => {
    const subjectMetrics = headMetricsIndexed[subject];

    Object.keys(subjectMetrics).forEach((metric) => {
      const headMetricData = subjectMetrics[metric];

      if (baseMetricsIndexed[subject] && baseMetricsIndexed[subject][metric]) {
        const baseMetricData = baseMetricsIndexed[subject][metric];
        const metricData = {
          name: metric,
          path: subject,
          score: headMetricData.value,
          delta: headMetricData.value - baseMetricData.value,
        };

        if (metricData.delta !== 0) {
          const isImproved =
            headMetricData.desiredSize === 'smaller' ? metricData.delta < 0 : metricData.delta > 0;

          if (isImproved) {
            improved.push(prepareMetricData(metricData, EXTENSION_ICONS.success));
          } else {
            degraded.push(prepareMetricData(metricData, EXTENSION_ICONS.failed));
          }
        } else {
          same.push(prepareMetricData(metricData, EXTENSION_ICONS.neutral));
        }
      }
    });
  });

  return { improved, degraded, same };
};

export const browserPerformanceStatusIcon = ({ degraded = [], same = [] }) =>
  degraded.length > 0 || same.length > 0 ? EXTENSION_ICONS.warning : EXTENSION_ICONS.success;

export const browserPerformanceSummary = ({ improved = [], degraded = [], same = [] }) => {
  const changesFound = improved.length + degraded.length + same.length;

  return {
    title: sprintf(
      n__(
        'ciReport|Browser performance test metrics: %{strong_start}%{changesFound}%{strong_end} change',
        'ciReport|Browser performance test metrics: %{strong_start}%{changesFound}%{strong_end} changes',
        changesFound,
      ),
      {
        changesFound,
      },
      false,
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
