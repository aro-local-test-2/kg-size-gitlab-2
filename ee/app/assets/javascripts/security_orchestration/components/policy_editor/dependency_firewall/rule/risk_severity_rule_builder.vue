<script>
import { uniqBy } from 'lodash-es';
import { GlButton, GlCollapsibleListbox, GlFormGroup, GlFormInput } from '@gitlab/ui';
import { s__, __ } from '~/locale';
import { RISK_SEVERITY_LISTBOX_ITEMS, DEFAULT_RISK_SEVERITY_THRESHOLD } from '../constants';
import { enforceIntValue } from '../../utils';
import { exceptionsToLines, ruleWithUpdatedExceptions } from '../utils';
import NameListTextarea from './name_list_textarea.vue';

const stripAllowed = (rule) => {
  const { allowed, ...rest } = rule;
  return rest;
};

export default {
  name: 'RiskSeverityRuleBuilder',
  components: { GlButton, GlCollapsibleListbox, GlFormGroup, GlFormInput, NameListTextarea },
  i18n: {
    thresholdsLabel: s__('SecurityOrchestration|Vulnerability count thresholds'),
    thresholdsDescription: s__(
      'SecurityOrchestration|Deny a package when it has more vulnerabilities at a severity than the threshold allows.',
    ),
    addSeverityText: s__('SecurityOrchestration|Add severity'),
    thresholdPlaceholder: s__('SecurityOrchestration|Threshold'),
    exceptionsLabel: s__('SecurityOrchestration|Exceptions'),
    exceptionsPlaceholder: s__(
      'SecurityOrchestration|Enter vulnerability IDs (e.g. CVEs) or package URLs (PURLs) to exempt, separated by commas',
    ),
    removeLabel: __('Remove'),
  },
  props: {
    initRule: {
      type: Object,
      required: true,
    },
  },
  emits: ['changed'],
  computed: {
    deniedList() {
      return uniqBy(this.initRule.denied || [], 'severity');
    },
    usedSeverities() {
      return this.deniedList.map(({ severity }) => severity);
    },
    availableSeverities() {
      return RISK_SEVERITY_LISTBOX_ITEMS.filter(
        ({ value }) => !this.usedSeverities.includes(value),
      );
    },
    canAddSeverity() {
      return this.availableSeverities.length > 0;
    },
    exceptionLines() {
      return exceptionsToLines(this.initRule.exceptions || []);
    },
  },
  methods: {
    severityLabel(value) {
      return RISK_SEVERITY_LISTBOX_ITEMS.find((item) => item.value === value)?.text ?? value;
    },
    emitDenied(denied) {
      this.$emit('changed', { ...stripAllowed(this.initRule), denied });
    },
    addSeverity(severity) {
      this.emitDenied([
        ...this.deniedList,
        { severity, threshold: DEFAULT_RISK_SEVERITY_THRESHOLD },
      ]);
    },
    normalizeThreshold(value) {
      const parsed = enforceIntValue(value);
      return Number.isNaN(parsed) ? DEFAULT_RISK_SEVERITY_THRESHOLD : Math.max(0, parsed);
    },
    formatThreshold(value) {
      return String(this.normalizeThreshold(value));
    },
    updateThreshold(index, value) {
      const threshold = this.normalizeThreshold(value);
      const updated = this.deniedList.map((entry, i) =>
        i === index ? { ...entry, threshold } : entry,
      );
      this.emitDenied(updated);
    },
    removeSeverity(index) {
      this.emitDenied(this.deniedList.filter((_, i) => i !== index));
    },
    handleExceptionsChange(lines) {
      this.$emit('changed', ruleWithUpdatedExceptions(stripAllowed(this.initRule), lines));
    },
  },
};
</script>

<template>
  <div class="gl-w-full">
    <gl-form-group :label="$options.i18n.thresholdsLabel" class="gl-w-full">
      <p class="gl-text-subtle">{{ $options.i18n.thresholdsDescription }}</p>

      <div
        v-for="(entry, index) in deniedList"
        :key="entry.severity"
        class="gl-mb-3 gl-flex gl-items-center gl-gap-3"
      >
        <span class="gl-w-20">{{ severityLabel(entry.severity) }}</span>
        <gl-form-input
          type="number"
          min="0"
          :value="entry.threshold"
          :formatter="formatThreshold"
          lazy-formatter
          :placeholder="$options.i18n.thresholdPlaceholder"
          :aria-label="severityLabel(entry.severity)"
          class="gl-w-20"
          :data-testid="`risk-severity-threshold-${entry.severity}`"
          @input="updateThreshold(index, $event)"
        />
        <gl-button
          icon="remove"
          category="tertiary"
          :aria-label="`${$options.i18n.removeLabel} ${severityLabel(entry.severity)}`"
          @click="removeSeverity(index)"
        />
      </div>

      <gl-collapsible-listbox
        v-if="canAddSeverity"
        :items="availableSeverities"
        :toggle-text="$options.i18n.addSeverityText"
        @select="addSeverity"
      />
    </gl-form-group>

    <gl-form-group :label="$options.i18n.exceptionsLabel" class="gl-w-full">
      <name-list-textarea
        :items="exceptionLines"
        :placeholder="$options.i18n.exceptionsPlaceholder"
        @input="handleExceptionsChange"
      />
    </gl-form-group>
  </div>
</template>
