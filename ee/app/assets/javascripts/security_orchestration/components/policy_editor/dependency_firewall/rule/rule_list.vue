<script>
import { GlAlert, GlTooltipDirective } from '@gitlab/ui';
import { n__, s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { ADD_RULE_LABEL, MAX_ALLOWED_RULES_LENGTH } from '../../constants';
import { buildDefaultRuleForType, getAddRuleTypeItems } from '../utils';
import RuleSection from './rule_section.vue';
import RuleTypeSelect from './rule_type_select.vue';

export default {
  name: 'RuleList',
  ADD_RULE_LABEL,
  components: { GlAlert, RuleSection, RuleTypeSelect },
  directives: { GlTooltip: GlTooltipDirective },
  mixins: [glFeatureFlagsMixin()],
  i18n: {
    noRulesMessage: s__(
      'SecurityOrchestration|This policy has no rules yet. Add at least one rule below for it to take effect.',
    ),
  },
  props: {
    rules: {
      type: Array,
      required: true,
    },
  },
  emits: ['changed'],
  computed: {
    hasNoRules() {
      return this.rules.length === 0;
    },
    addRuleTypeItems() {
      return getAddRuleTypeItems(this.glFeatures.dependencyFirewallRiskSeverityRule);
    },
    canAddRule() {
      return this.rules.length < MAX_ALLOWED_RULES_LENGTH;
    },
    addRuleTooltip() {
      return this.canAddRule
        ? ''
        : n__(
            'SecurityOrchestration|You can add up to %d rule',
            'SecurityOrchestration|You can add up to %d rules',
            MAX_ALLOWED_RULES_LENGTH,
          );
    },
  },
  methods: {
    addRule(type) {
      this.$emit('changed', [...this.rules, buildDefaultRuleForType(type)]);
    },
    removeRule(index) {
      this.$emit(
        'changed',
        this.rules.filter((_, i) => i !== index),
      );
    },
    updateRule(index, rule) {
      const updated = [...this.rules];
      updated.splice(index, 1, rule);
      this.$emit('changed', updated);
    },
  },
};
</script>

<template>
  <div>
    <gl-alert v-if="hasNoRules" :dismissible="false" variant="info" class="gl-mb-4">
      {{ $options.i18n.noRulesMessage }}
    </gl-alert>

    <rule-section
      v-for="(rule, index) in rules"
      :key="rule.id"
      :init-rule="rule"
      class="gl-mb-4"
      @changed="updateRule(index, $event)"
      @remove="removeRule(index)"
    />

    <div class="security-policies-bg-subtle gl-rounded-base gl-p-5">
      <span
        v-gl-tooltip="{ disabled: canAddRule, title: addRuleTooltip }"
        data-testid="add-rule-wrapper"
      >
        <rule-type-select
          :items="addRuleTypeItems"
          :toggle-text="$options.ADD_RULE_LABEL"
          :disabled="!canAddRule"
          @select="addRule"
        />
      </span>
    </div>
  </div>
</template>
