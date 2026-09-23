import { uniqueId } from 'lodash-es';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_VULNERABILITY,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
  RULE_TYPE_LISTBOX_ITEMS,
  RISK_SEVERITY_RULE_TYPE_ITEM,
  DEFAULT_SEVERITY,
  DEFAULT_RISK_SEVERITY_THRESHOLD,
} from './constants';

export const buildEmptyRule = () => ({ id: uniqueId('rule_'), type: '' });

export const buildDefaultRuleForType = (type) => {
  const id = uniqueId('rule_');

  switch (type) {
    case RULE_TYPE_LICENSE:
      return { id, type: RULE_TYPE_LICENSE, denied: [] };
    case RULE_TYPE_VULNERABILITY:
      return { id, type: RULE_TYPE_VULNERABILITY, denied: [{ severity: DEFAULT_SEVERITY }] };
    case RULE_TYPE_MALICIOUS:
      return { id, type: RULE_TYPE_MALICIOUS, denied: [{ is_malicious: true }] };
    case RULE_TYPE_RISK_SEVERITY:
      return {
        id,
        type: RULE_TYPE_RISK_SEVERITY,
        denied: [{ severity: DEFAULT_SEVERITY, threshold: DEFAULT_RISK_SEVERITY_THRESHOLD }],
      };
    default:
      return buildEmptyRule();
  }
};

// riskSeverityEnabled comes from dependency_firewall_risk_severity_rule; once that flag
// is removed, delete the branch below and return RULE_TYPE_LISTBOX_ITEMS with
// RISK_SEVERITY_RULE_TYPE_ITEM merged in permanently.
export const getAddRuleTypeItems = (riskSeverityEnabled) => {
  if (!riskSeverityEnabled) {
    return RULE_TYPE_LISTBOX_ITEMS;
  }

  return RULE_TYPE_LISTBOX_ITEMS.map((item) =>
    item.value === RULE_TYPE_VULNERABILITY ? RISK_SEVERITY_RULE_TYPE_ITEM : item,
  );
};

export const getRuleListKey = (rule) => (Array.isArray(rule.allowed) ? 'allowed' : 'denied');

export const getRuleList = (rule) => rule[getRuleListKey(rule)] || [];

export const isRuleEmpty = (rule) => getRuleList(rule).length === 0;

export const toggleRuleListKey = (rule, newKey) => {
  const { denied, allowed, ...rest } = rule;
  const list = denied || allowed || [];

  return { ...rest, [newKey]: list };
};

export const namesToItems = (names = []) => names.map((name) => ({ name }));

export const itemsToNames = (items = []) => items.map(({ name }) => name);

export const exceptionsToLines = (exceptions = []) =>
  exceptions.map((exception) => exception.purl || exception.id).filter(Boolean);

export const linesToExceptions = (lines = []) =>
  // eslint-disable-next-line @gitlab/require-i18n-strings -- PURL prefix, not UI text
  lines.map((line) => (line.startsWith('pkg:') ? { purl: line } : { id: line }));

export const ruleWithUpdatedExceptions = (rule, lines) => {
  const exceptions = linesToExceptions(lines);
  const updatedRule = { ...rule };

  if (exceptions.length) {
    updatedRule.exceptions = exceptions;
  } else {
    delete updatedRule.exceptions;
  }

  return updatedRule;
};
