<script>
import { GlPopover } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import { itemValidator, aggregateAnalyzerStatuses } from 'ee/security_inventory/utils';
import { SCANNER_TYPES, SCANNER_POPOVER_GROUPS, TOOL_STATUS_CONFIG } from '../constants';
import GroupToolCoverageDetails from './group_tool_coverage_details.vue';
import SegmentedBar from './segmented_bar.vue';

export default {
  name: 'GroupToolCoverageIndicator',
  components: {
    GroupToolCoverageDetails,
    SegmentedBar,
    GlPopover,
  },
  props: {
    item: {
      type: Object,
      required: true,
      validator: (value) => itemValidator(value),
    },
  },
  computed: {
    scannerSegments() {
      return Object.fromEntries(
        Object.entries(this.$options.SCANNER_POPOVER_GROUPS).map(([key, value]) => [
          key,
          this.buildCoverageSegments(value),
        ]),
      );
    },
  },
  methods: {
    buildCoverageSegments(value) {
      const aggregatedData = this.aggregateScannerData(value);
      return Object.values(TOOL_STATUS_CONFIG).map(({ color, fieldKey }) => ({
        color,
        count: aggregatedData[fieldKey] || 0,
      }));
    },
    getLabel(key) {
      return SCANNER_TYPES[key].textLabel;
    },
    getToolCoverageTitle() {
      return s__('ToolCoverage|Project coverage');
    },
    getCalculatedCoverage(scannerTypes) {
      const aggregatedData = this.aggregateScannerData(scannerTypes);
      return `${aggregatedData.success + aggregatedData.failure} ${__('of')} ${aggregatedData.notConfigured}`;
    },
    aggregateScannerData(scannerTypes) {
      return aggregateAnalyzerStatuses(this.item.analyzerStatuses, scannerTypes);
    },
  },
  SCANNER_POPOVER_GROUPS,
};
</script>

<template>
  <div class="gl-flex gl-flex-row gl-flex-wrap gl-gap-2">
    <div v-for="(value, key) in $options.SCANNER_POPOVER_GROUPS" :key="key" class="gl-w-8">
      <segmented-bar
        :id="`${key}-${item.path}-bar`"
        :aria-labelledby="`${key}-${item.path}-label`"
        :segments="scannerSegments[key]"
        class="gl-mb-1"
        :data-testid="`${key}-${item.path}-bar`"
      />
      <span
        :id="`${key}-${item.path}-label`"
        class="gl-text-sm gl-text-status-neutral"
        :data-testid="`${key}-${item.path}-label`"
      >
        {{ getLabel(key) }}
        <span class="gl-sr-only">
          {{
            sprintf(s__('SecurityInventory|Tool coverage: %{coverage}'), {
              coverage: getCalculatedCoverage(value),
            })
          }}
        </span>
      </span>
      <gl-popover
        :title="getToolCoverageTitle()"
        :target="`${key}-${item.path}-bar`"
        :data-testid="`popover-${key}-bar`"
        show-close-button
      >
        <group-tool-coverage-details :security-scanner="aggregateScannerData(value)" />
      </gl-popover>
    </div>
  </div>
</template>
