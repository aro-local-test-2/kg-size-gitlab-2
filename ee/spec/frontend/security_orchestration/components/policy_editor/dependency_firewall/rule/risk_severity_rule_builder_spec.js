import { GlButton, GlCollapsibleListbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskSeverityRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/risk_severity_rule_builder.vue';
import NameListTextarea from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/name_list_textarea.vue';

describe('RiskSeverityRuleBuilder', () => {
  let wrapper;

  const createWrapper = (initRule = { type: 'risk_severity', denied: [] }) => {
    wrapper = shallowMountExtended(RiskSeverityRuleBuilder, { propsData: { initRule } });
  };

  const findAddSeverityListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findRemoveButtons = () => wrapper.findAllComponents(GlButton);
  const findThreshold = (severity) =>
    wrapper.findComponentByTestId(`risk-severity-threshold-${severity}`);

  describe('when denied is empty', () => {
    it('renders no rows and offers all four severities', () => {
      createWrapper();

      expect(findRemoveButtons()).toHaveLength(0);
      expect(
        findAddSeverityListbox()
          .props('items')
          .map(({ value }) => value),
      ).toEqual(['critical', 'high', 'medium', 'low']);
    });
  });

  it('adds a severity row with the default threshold', () => {
    createWrapper();
    findAddSeverityListbox().vm.$emit('select', 'high');

    expect(wrapper.emitted('changed')[0][0]).toEqual({
      type: 'risk_severity',
      denied: [{ severity: 'high', threshold: 0 }],
    });
  });

  describe('when a severity is already added', () => {
    beforeEach(() => {
      createWrapper({ type: 'risk_severity', denied: [{ severity: 'high', threshold: 5 }] });
    });

    it('does not offer that severity again', () => {
      const values = findAddSeverityListbox()
        .props('items')
        .map(({ value }) => value);
      expect(values).not.toContain('high');
      expect(values).toEqual(['critical', 'medium', 'low']);
    });

    it('renders a threshold input seeded with the current value', () => {
      expect(findThreshold('high').props('value')).toBe(5);
    });

    it('updates the threshold, coercing to a non-negative integer', () => {
      findThreshold('high').vm.$emit('input', '-3');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'high', threshold: 0 }],
      });
    });

    it('lazily reformats the displayed value on blur so an invalid entry is visibly corrected', () => {
      expect(findThreshold('high').props('lazyFormatter')).toBe(true);
      expect(findThreshold('high').props('formatter')('-3')).toBe('0');
    });

    it('removes the row', () => {
      findRemoveButtons().at(0).vm.$emit('click');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [],
      });
    });
  });

  describe('when all four severities are added', () => {
    beforeEach(() => {
      createWrapper({
        type: 'risk_severity',
        denied: [
          { severity: 'critical', threshold: 0 },
          { severity: 'high', threshold: 0 },
          { severity: 'medium', threshold: 0 },
          { severity: 'low', threshold: 0 },
        ],
      });
    });

    it('does not render the add-severity control', () => {
      expect(findAddSeverityListbox().exists()).toBe(false);
    });
  });

  describe('when the rule has a stray allowed key', () => {
    beforeEach(() => {
      createWrapper({
        type: 'risk_severity',
        allowed: [],
        denied: [{ severity: 'critical', threshold: 10 }],
      });
    });

    it('still reads the denied list rather than treating allowed as authoritative', () => {
      expect(findRemoveButtons()).toHaveLength(1);
      expect(findThreshold('critical').props('value')).toBe(10);
    });

    it('drops allowed when a severity row changes', () => {
      findThreshold('critical').vm.$emit('input', '20');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'critical', threshold: 20 }],
      });
    });

    it('drops allowed when only the exceptions input changes', () => {
      wrapper.findComponent(NameListTextarea).vm.$emit('input', ['CVE-2021-23337']);

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'critical', threshold: 10 }],
        exceptions: [{ id: 'CVE-2021-23337' }],
      });
    });
  });

  describe('when a threshold input produces a non-numeric value', () => {
    it('falls back to the default threshold instead of emitting NaN', () => {
      createWrapper({ type: 'risk_severity', denied: [{ severity: 'high', threshold: 5 }] });
      findThreshold('high').vm.$emit('input', '.5');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'high', threshold: 0 }],
      });
    });
  });

  describe('when the same severity appears twice in the rule', () => {
    it('renders only one row', () => {
      createWrapper({
        type: 'risk_severity',
        denied: [
          { severity: 'high', threshold: 1 },
          { severity: 'high', threshold: 9 },
        ],
      });

      expect(findRemoveButtons()).toHaveLength(1);
    });
  });

  describe('when the exceptions input changes', () => {
    beforeEach(() => {
      createWrapper();
      wrapper.findComponent(NameListTextarea).vm.$emit('input', ['CVE-2021-23337']);
    });

    it('emits changed with exceptions', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [],
        exceptions: [{ id: 'CVE-2021-23337' }],
      });
    });
  });
});
