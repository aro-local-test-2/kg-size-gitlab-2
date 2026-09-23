<script>
import { GlButton, GlCollapse } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { extractPolicyContent, fromYaml } from 'ee/security_orchestration/components/utils';
import {
  policyBodyToYaml,
  policyToYaml,
} from 'ee/security_orchestration/components/policy_editor/utils';
import {
  EDITOR_MODE_RULE,
  EDITOR_MODE_YAML,
  EDITOR_MODES,
  SECURITY_POLICY_ACTIONS,
  RULE_SECTION_DISABLE_ERROR,
} from '../constants';
import EditorLayout from '../editor_layout.vue';
import DisabledSection from '../disabled_section.vue';
import { DEPENDENCY_FIREWALL_POLICY_TYPE } from '../../constants';
import RuleList from './rule/rule_list.vue';
import EnforcementTypeSelect from './settings/enforcement_type_select.vue';
import BypassSettings from './advanced_settings/bypass_settings.vue';

export const DEFAULT_DEPENDENCY_FIREWALL_POLICY = `dependency_firewall_policy:
  - name: ''
    description: ''
    enabled: true
    # \`enforced\` blocks the download when a rule matches.
    # \`warn\` allows the download and records a warning.
    enforcement_type: warn
    policy_scope:
      projects:
        excluding: []
    # Add at least one rule using "Add new rule" below.
    rules: []
`;

// Pre-phase-2 default: rendered only when `dependency_firewall_phase2` is disabled, so the
// rule-builder UI can roll out incrementally without changing the YAML-only experience.
const LEGACY_DEFAULT_DEPENDENCY_FIREWALL_POLICY = `dependency_firewall_policy:
  - name: Your policy name
    description: Your policy description
    enabled: true
    # \`enforced\` blocks the download when a rule matches.
    # \`warn\` allows the download and records a warning.
    enforcement_type: warn
    policy_scope:
      projects:
        excluding: []
    rules:
      # Deny by SPDX license name. Swap \`denied\` for \`allowed\` to use an allowlist.
      - type: license
        denied:
          - name: SPDX License Name
        # Optional: exempt specific packages from this rule.
        # exceptions:
        #   - purl: pkg:npm/lodash@4.17.21
      # One severity threshold; anything at or above it is denied.
      # One of: critical, high, medium, low, info, unknown
      - type: vulnerability
        denied:
          - severity: high
        # Optional: exempt specific vulnerabilities from this rule.
        # exceptions:
        #   - id: CVE-2021-23337
      # Blocks packages flagged by the malicious packages feed.
      # \`denied\` only - \`allowed\` is not permitted for this type.
      - type: malicious
        denied:
          - is_malicious: true
`;

const YAML_ONLY_MODES = [
  { value: EDITOR_MODE_YAML, text: s__('SecurityOrchestration|.yaml mode') },
];

export default {
  name: 'DependencyFirewallEditorComponent',
  EDITOR_MODE_RULE,
  EDITOR_MODE_YAML,
  EDITOR_MODES,
  YAML_ONLY_MODES,
  SECURITY_POLICY_ACTIONS,
  i18n: {
    RULE_SECTION_DISABLE_ERROR,
    rulesHeader: s__('SecurityOrchestration|Rules'),
    advancedHeader: __('Advanced'),
  },
  components: {
    GlButton,
    GlCollapse,
    EditorLayout,
    DisabledSection,
    RuleList,
    EnforcementTypeSelect,
    BypassSettings,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    existingPolicy: {
      type: Object,
      required: false,
      default: null,
    },
    isCreating: {
      type: Boolean,
      required: true,
    },
    isDeleting: {
      type: Boolean,
      required: true,
    },
    isEditing: {
      type: Boolean,
      required: true,
    },
    selectedPolicyType: {
      type: String,
      required: true,
    },
  },
  emits: ['save'],
  data() {
    let yamlEditorValue;

    if (this.existingPolicy) {
      yamlEditorValue = policyToYaml(this.existingPolicy, this.selectedPolicyType);
    } else if (this.glFeatures.dependencyFirewallPhase2) {
      yamlEditorValue = DEFAULT_DEPENDENCY_FIREWALL_POLICY;
    } else {
      yamlEditorValue = LEGACY_DEFAULT_DEPENDENCY_FIREWALL_POLICY;
    }

    const policy = fromYaml({ manifest: yamlEditorValue, type: DEPENDENCY_FIREWALL_POLICY_TYPE });

    return {
      policy,
      yamlEditorValue,
      isAdvancedExpanded: false,
    };
  },
  computed: {
    phase2Enabled() {
      return Boolean(this.glFeatures.dependencyFirewallPhase2);
    },
    defaultEditorMode() {
      return this.phase2Enabled ? this.$options.EDITOR_MODE_RULE : this.$options.EDITOR_MODE_YAML;
    },
    editorModes() {
      return this.phase2Enabled ? this.$options.EDITOR_MODES : this.$options.YAML_ONLY_MODES;
    },
    parsingError() {
      return Boolean(this.yamlEditorValue) && Object.keys(this.policy).length === 0;
    },
    rules() {
      return this.policy.rules || [];
    },
    enforcementType() {
      return this.policy.enforcement_type || 'warn';
    },
    bypassSettings() {
      return this.policy.bypass_settings || {};
    },
    advancedIcon() {
      return this.isAdvancedExpanded ? 'chevron-down' : 'chevron-right';
    },
  },
  methods: {
    updateYamlEditorValue(policy) {
      this.yamlEditorValue = policyToYaml(policy, this.selectedPolicyType);
    },
    updateRules(rules) {
      this.policy = { ...this.policy, rules };
      this.updateYamlEditorValue(this.policy);
    },
    updateEnforcementType(enforcementType) {
      this.policy = { ...this.policy, enforcement_type: enforcementType };
      this.updateYamlEditorValue(this.policy);
    },
    async handleModifyPolicy(action) {
      const policy = extractPolicyContent({
        manifest: this.yamlEditorValue,
        type: this.selectedPolicyType,
        withType: true,
      });

      this.$emit('save', {
        action,
        policy: policyBodyToYaml(policy),
      });
    },
    handleUpdateYaml(manifest) {
      this.yamlEditorValue = manifest;
      this.policy = fromYaml({ manifest, type: DEPENDENCY_FIREWALL_POLICY_TYPE });
    },
    handleRemoveProperty(property) {
      const { [property]: removedProperty, ...updatedPolicy } = this.policy;
      this.policy = updatedPolicy;
      this.updateYamlEditorValue(this.policy);
    },
    handleUpdateProperty(property, value) {
      // Assign via a new object (not `this.policy[property] = value`): bypass_settings
      // isn't in the default policy, and Vue 2 doesn't react to adding a brand-new
      // property by plain mutation, only to reassigning the object.
      this.policy = { ...this.policy, [property]: value };
      this.updateYamlEditorValue(this.policy);
    },
    toggleAdvanced() {
      this.isAdvancedExpanded = !this.isAdvancedExpanded;
    },
  },
};
</script>
<template>
  <editor-layout
    :default-editor-mode="defaultEditorMode"
    :editor-modes="editorModes"
    :is-editing="isEditing"
    :is-removing-policy="isDeleting"
    :is-updating-policy="isCreating"
    :policy="policy"
    :yaml-editor-value="yamlEditorValue"
    @remove-policy="handleModifyPolicy($options.SECURITY_POLICY_ACTIONS.REMOVE)"
    @save-policy="handleModifyPolicy"
    @remove-property="handleRemoveProperty"
    @update-property="handleUpdateProperty"
    @update-yaml="handleUpdateYaml"
  >
    <template v-if="phase2Enabled" #additional-status>
      <enforcement-type-select
        :enforcement-type="enforcementType"
        @change="updateEnforcementType"
      />
    </template>

    <template v-if="phase2Enabled" #rules>
      <disabled-section :disabled="parsingError" :error="$options.i18n.RULE_SECTION_DISABLE_ERROR">
        <template #title>
          <h4>{{ $options.i18n.rulesHeader }}</h4>
        </template>
        <rule-list :rules="rules" @changed="updateRules" />
      </disabled-section>
    </template>

    <template v-if="phase2Enabled" #settings>
      <gl-button
        class="gl-mt-5"
        variant="link"
        :icon="advancedIcon"
        data-testid="collapse-button"
        @click="toggleAdvanced"
      >
        <h4 class="gl-mr-3">{{ $options.i18n.advancedHeader }}</h4>
      </gl-button>
      <gl-collapse v-model="isAdvancedExpanded" class="gl-ml-7 gl-mt-0">
        <disabled-section
          :disabled="parsingError"
          :error="$options.i18n.RULE_SECTION_DISABLE_ERROR"
        >
          <bypass-settings :bypass-settings="bypassSettings" @changed="handleUpdateProperty" />
        </disabled-section>
      </gl-collapse>
    </template>
  </editor-layout>
</template>
