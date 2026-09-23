import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RuleSection from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_section.vue';
import SectionLayout from 'ee/security_orchestration/components/policy_editor/section_layout.vue';
import LicenseRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/license_rule_builder.vue';
import VulnerabilityRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/vulnerability_rule_builder.vue';
import MaliciousRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/malicious_rule_builder.vue';
import RiskSeverityRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/risk_severity_rule_builder.vue';

describe('RuleSection', () => {
  let wrapper;

  const createWrapper = (initRule) => {
    wrapper = shallowMountExtended(RuleSection, { propsData: { initRule } });
  };

  it.each`
    type               | component                   | label                       | others
    ${'license'}       | ${LicenseRuleBuilder}       | ${'License rule'}           | ${[VulnerabilityRuleBuilder, MaliciousRuleBuilder, RiskSeverityRuleBuilder]}
    ${'vulnerability'} | ${VulnerabilityRuleBuilder} | ${'Vulnerability rule'}     | ${[LicenseRuleBuilder, MaliciousRuleBuilder, RiskSeverityRuleBuilder]}
    ${'malicious'}     | ${MaliciousRuleBuilder}     | ${'Malicious package rule'} | ${[LicenseRuleBuilder, VulnerabilityRuleBuilder, RiskSeverityRuleBuilder]}
    ${'risk_severity'} | ${RiskSeverityRuleBuilder}  | ${'Risk severity rule'}     | ${[LicenseRuleBuilder, VulnerabilityRuleBuilder, MaliciousRuleBuilder]}
  `(
    'renders exactly $component with heading "$label" for a $type rule',
    ({ type, component, label, others }) => {
      createWrapper({ type, denied: [] });
      expect(wrapper.findComponent(component).exists()).toBe(true);
      expect(wrapper.find('h5').text()).toBe(label);
      others.forEach((otherComponent) => {
        expect(wrapper.findComponent(otherComponent).exists()).toBe(false);
      });
    },
  );

  it('renders an alert with no heading for an unrecognized rule type', () => {
    createWrapper({ type: 'unknown' });
    expect(wrapper.findComponent(GlAlert).exists()).toBe(true);
    expect(wrapper.find('h5').exists()).toBe(false);
    expect(wrapper.findComponent(LicenseRuleBuilder).exists()).toBe(false);
    expect(wrapper.findComponent(VulnerabilityRuleBuilder).exists()).toBe(false);
    expect(wrapper.findComponent(MaliciousRuleBuilder).exists()).toBe(false);
    expect(wrapper.findComponent(RiskSeverityRuleBuilder).exists()).toBe(false);
  });

  it('bubbles up changed events from the active rule builder', () => {
    createWrapper({ type: 'license', denied: [] });
    wrapper
      .findComponent(LicenseRuleBuilder)
      .vm.$emit('changed', { type: 'license', denied: [{ name: 'MIT' }] });
    expect(wrapper.emitted('changed')[0][0]).toEqual({
      type: 'license',
      denied: [{ name: 'MIT' }],
    });
  });

  it('emits remove when the section layout emits remove', () => {
    createWrapper({ type: 'license', denied: [] });
    wrapper.findComponent(SectionLayout).vm.$emit('remove');
    expect(wrapper.emitted('remove')).toEqual([[]]);
  });
});
