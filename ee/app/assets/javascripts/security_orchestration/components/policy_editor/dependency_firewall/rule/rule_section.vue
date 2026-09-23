<script>
import { GlAlert } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_VULNERABILITY,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
} from '../constants';
import SectionLayout from '../../section_layout.vue';
import LicenseRuleBuilder from './license_rule_builder.vue';
import VulnerabilityRuleBuilder from './vulnerability_rule_builder.vue';
import MaliciousRuleBuilder from './malicious_rule_builder.vue';
import RiskSeverityRuleBuilder from './risk_severity_rule_builder.vue';

export default {
  name: 'RuleSection',
  components: {
    GlAlert,
    SectionLayout,
    LicenseRuleBuilder,
    VulnerabilityRuleBuilder,
    MaliciousRuleBuilder,
    RiskSeverityRuleBuilder,
  },
  props: {
    initRule: {
      type: Object,
      required: true,
    },
  },
  emits: ['changed', 'remove'],
  i18n: {
    unrecognizedType: s__(
      'SecurityOrchestration|Unrecognized rule type. Switch to YAML mode to edit this rule.',
    ),
    ruleTypeHeadings: {
      [RULE_TYPE_LICENSE]: s__('SecurityOrchestration|License rule'),
      [RULE_TYPE_VULNERABILITY]: s__('SecurityOrchestration|Vulnerability rule'),
      [RULE_TYPE_MALICIOUS]: s__('SecurityOrchestration|Malicious package rule'),
      [RULE_TYPE_RISK_SEVERITY]: s__('SecurityOrchestration|Risk severity rule'),
    },
  },
  computed: {
    isLicense() {
      return this.initRule.type === RULE_TYPE_LICENSE;
    },
    isVulnerability() {
      return this.initRule.type === RULE_TYPE_VULNERABILITY;
    },
    isMalicious() {
      return this.initRule.type === RULE_TYPE_MALICIOUS;
    },
    isRiskSeverity() {
      return this.initRule.type === RULE_TYPE_RISK_SEVERITY;
    },
    isUnrecognized() {
      return !this.isLicense && !this.isVulnerability && !this.isMalicious && !this.isRiskSeverity;
    },
    ruleTypeLabel() {
      return this.$options.i18n.ruleTypeHeadings[this.initRule.type] ?? '';
    },
  },
  methods: {
    updateRule(rule) {
      this.$emit('changed', rule);
    },
  },
};
</script>

<template>
  <div>
    <h5 v-if="ruleTypeLabel" class="gl-mb-3">{{ ruleTypeLabel }}</h5>

    <section-layout @remove="$emit('remove')">
      <template #content>
        <license-rule-builder v-if="isLicense" :init-rule="initRule" @changed="updateRule" />
        <vulnerability-rule-builder
          v-else-if="isVulnerability"
          :init-rule="initRule"
          @changed="updateRule"
        />
        <malicious-rule-builder
          v-else-if="isMalicious"
          :init-rule="initRule"
          @changed="updateRule"
        />
        <risk-severity-rule-builder
          v-else-if="isRiskSeverity"
          :init-rule="initRule"
          @changed="updateRule"
        />
        <gl-alert v-else-if="isUnrecognized" variant="warning" :dismissible="false">
          {{ $options.i18n.unrecognizedType }}
        </gl-alert>
      </template>
    </section-layout>
  </div>
</template>
