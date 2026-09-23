import { __ } from '~/locale';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';

const isChanged = (metric) => Boolean(metric?.previous_value);

const metricDelta = (metric) => {
  const delta = Math.abs(parseFloat(metric.value) - parseFloat(metric.previous_value));

  // Non-numeric metrics get an infinite delta so that they sort first.
  return Number.isNaN(delta) ? Infinity : delta;
};

const metricText = (metric, withPreviousValue) =>
  withPreviousValue
    ? `${metric.name}: ${metric.value} (${metric.previous_value})`
    : `${metric.name}: ${metric.value}`;

const metricGroups = (data) => {
  const existingMetrics = data?.existing_metrics || [];

  return [
    { header: __('New'), metrics: data?.new_metrics || [] },
    { header: __('Removed'), metrics: data?.removed_metrics || [] },
    {
      header: __('Changed'),
      metrics: existingMetrics.filter(isChanged).sort((a, b) => metricDelta(b) - metricDelta(a)),
      withPreviousValue: true,
    },
    { header: __('No changes'), metrics: existingMetrics.filter((metric) => !isChanged(metric)) },
  ];
};

export const metricChangeCount = (data) =>
  (data?.new_metrics?.length || 0) +
  (data?.removed_metrics?.length || 0) +
  (data?.existing_metrics?.filter(isChanged).length || 0);

export const metricSections = (data) =>
  metricGroups(data)
    .filter(({ metrics }) => metrics.length)
    .map(({ header, metrics, withPreviousValue }) => ({
      header,
      children: metrics.map((metric) => ({
        text: metricText(metric, withPreviousValue),
        icon: { name: EXTENSION_ICONS.neutral },
      })),
    }));

export const metricWidgetItems = (data) =>
  metricSections(data).flatMap(({ header, children }) =>
    children.map((child, index) => ({ ...child, header: index === 0 ? header : '' })),
  );
