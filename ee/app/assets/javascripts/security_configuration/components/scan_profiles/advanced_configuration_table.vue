<script>
import { GlButton, GlTableLite } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { SCAN_TRIGGER_DEFINITIONS } from '~/security_configuration/constants';

export default {
  name: 'AdvancedConfigurationTable',
  components: {
    GlButton,
    GlTableLite,
  },
  props: {
    caption: {
      type: String,
      required: true,
    },
    rows: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  data() {
    return {
      expandedVariables: [],
    };
  },
  computed: {
    items() {
      return this.rows.map((row) => ({
        ...row,
        _showDetails: this.isExpanded(row.setting),
      }));
    },
  },
  methods: {
    isExpanded(setting) {
      return this.expandedVariables.includes(setting);
    },
    toggleVariable(setting) {
      this.expandedVariables = this.isExpanded(setting)
        ? this.expandedVariables.filter((expanded) => expanded !== setting)
        : [...this.expandedVariables, setting];
    },
    triggerTitle(triggerType) {
      return SCAN_TRIGGER_DEFINITIONS[triggerType]?.title ?? triggerType;
    },
    toggleLabel(setting) {
      return sprintf(s__('ScanProfiles|Show %{variable} for each trigger'), { variable: setting });
    },
  },
  fields: [
    { key: 'toggle', label: '', thClass: 'gl-w-8', tdClass: '!gl-pt-4' },
    { key: 'variable', label: s__('ScanProfiles|Variable'), thClass: 'gl-w-8/20' },
    { key: 'value', label: s__('ScanProfiles|Value') },
  ],
};
</script>
<template>
  <gl-table-lite
    v-if="rows.length"
    :items="items"
    :fields="$options.fields"
    fixed
    stacked="sm"
    table-class="gl-mb-0"
    details-td-class="!gl-p-0"
    :aria-label="caption"
    data-testid="advanced-configuration-table"
  >
    <template #cell(toggle)="{ item }">
      <gl-button
        category="tertiary"
        size="small"
        :icon="isExpanded(item.setting) ? 'chevron-down' : 'chevron-right'"
        :aria-expanded="isExpanded(item.setting).toString()"
        :aria-label="toggleLabel(item.setting)"
        @click="toggleVariable(item.setting)"
      />
    </template>
    <template #cell(variable)="{ item }">
      <code>{{ item.setting }}</code>
    </template>
    <template #cell(value)="{ item }">
      <gl-button v-if="item.varies" variant="link" @click="toggleVariable(item.setting)">
        {{ s__('ScanProfiles|Differs by trigger') }}
      </gl-button>
      <span v-else class="gl-break-anywhere">{{ item.value }}</span>
    </template>
    <template #row-details="{ item }">
      <div class="gl-py-3" data-testid="trigger-values">
        <div
          v-for="triggerValue in item.triggerValues"
          :key="triggerValue.triggerType"
          class="gl-flex"
        >
          <div class="gl-w-8"></div>
          <span class="gl-w-8/20 gl-p-4 gl-text-subtle">{{
            triggerTitle(triggerValue.triggerType)
          }}</span>
          <span class="gl-w-1/2 gl-p-4 gl-break-anywhere">{{ triggerValue.value }}</span>
        </div>
      </div>
    </template>
  </gl-table-lite>
</template>
