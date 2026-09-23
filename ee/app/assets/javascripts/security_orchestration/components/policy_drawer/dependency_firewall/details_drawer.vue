<script>
import { s__ } from '~/locale';
import {
  DEPENDENCY_FIREWALL_POLICY_TYPE,
  DEPENDENCY_FIREWALL_POLICY_TYPE_HEADER,
} from 'ee/security_orchestration/components/constants';
import { fromYaml } from 'ee/security_orchestration/components/utils';
import { SUMMARY_TITLE } from 'ee/security_orchestration/components/policy_drawer/constants';
import DenyAllowViewList from 'ee/security_orchestration/components/policy_drawer/scan_result/deny_allow_view_list.vue';
import DrawerLayout from '../drawer_layout.vue';
import InfoRow from '../info_row.vue';
import { humanizeRules } from './utils';

const ENFORCEMENT_TYPE_LABELS = {
  enforced: s__('SecurityOrchestration|Enforced'),
  warn: s__('SecurityOrchestration|Advisory'),
};

export default {
  name: 'DependencyFirewallDetailsDrawer',
  i18n: {
    policyType: DEPENDENCY_FIREWALL_POLICY_TYPE_HEADER,
    summary: SUMMARY_TITLE,
    enforcementTypeLabel: s__('SecurityOrchestration|Enforcement type'),
    noRulesMessage: s__('SecurityOrchestration|No rules defined for this policy.'),
  },
  components: {
    DrawerLayout,
    DenyAllowViewList,
    InfoRow,
  },
  props: {
    policy: {
      type: Object,
      required: true,
    },
  },
  computed: {
    parsedYaml() {
      return fromYaml({
        manifest: this.policy.yaml,
        type: DEPENDENCY_FIREWALL_POLICY_TYPE,
      });
    },
    hasValidYaml() {
      return this.parsedYaml && Object.keys(this.parsedYaml).length > 0;
    },
    description() {
      return this.parsedYaml?.description || '';
    },
    enforcementTypeLabel() {
      return ENFORCEMENT_TYPE_LABELS[this.parsedYaml?.enforcement_type] || '';
    },
    rules() {
      return humanizeRules(this.parsedYaml?.rules || []);
    },
    policyScope() {
      return this.policy?.policyScope;
    },
  },
};
</script>

<template>
  <drawer-layout
    key="dependency_firewall_policy"
    :description="description"
    :policy="policy"
    :policy-scope="policyScope"
    :type="$options.i18n.policyType"
  >
    <template v-if="hasValidYaml" #summary>
      <info-row
        v-if="enforcementTypeLabel"
        data-testid="enforcement-type"
        :label="$options.i18n.enforcementTypeLabel"
      >
        {{ enforcementTypeLabel }}
      </info-row>

      <info-row data-testid="policy-summary" :label="$options.i18n.summary">
        <p v-if="!rules.length" data-testid="no-rules-message">
          {{ $options.i18n.noRulesMessage }}
        </p>

        <template v-else>
          <template v-for="rule in rules">
            <p
              v-if="rule.subheader"
              :key="`${rule.key}-subheader`"
              class="gl-mb-0 gl-mt-2 gl-block"
              data-testid="rules-subheader"
            >
              {{ rule.subheader }}
            </p>

            <deny-allow-view-list
              v-if="rule.items && rule.items.length"
              :key="`${rule.key}-items`"
              class="gl-mt-4"
              data-testid="rule"
              :is-denied="rule.isDenied"
              :items="rule.items"
            />

            <ul
              v-else-if="rule.criteriaList && rule.criteriaList.length"
              :key="`${rule.key}-criteria`"
              class="gl-m-0 gl-mt-4"
              data-testid="rule"
            >
              <li v-for="(criteria, idx) in rule.criteriaList" :key="idx">{{ criteria }}</li>
            </ul>
          </template>
        </template>
      </info-row>
    </template>
  </drawer-layout>
</template>
