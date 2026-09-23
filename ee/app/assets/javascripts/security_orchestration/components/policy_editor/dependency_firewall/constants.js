import { s__ } from '~/locale';

export const RULE_TYPE_LICENSE = 'license';
export const RULE_TYPE_VULNERABILITY = 'vulnerability';
export const RULE_TYPE_MALICIOUS = 'malicious';
export const RULE_TYPE_RISK_SEVERITY = 'risk_severity';

export const RULE_TYPE_LISTBOX_ITEMS = [
  { value: RULE_TYPE_LICENSE, text: s__('SecurityOrchestration|License') },
  { value: RULE_TYPE_VULNERABILITY, text: s__('SecurityOrchestration|Vulnerability') },
  { value: RULE_TYPE_MALICIOUS, text: s__('SecurityOrchestration|Malicious package') },
];

export const RISK_SEVERITY_RULE_TYPE_ITEM = {
  value: RULE_TYPE_RISK_SEVERITY,
  text: s__('SecurityOrchestration|Risk severity'),
};

export const DEFAULT_SEVERITY = 'high';

export const SEVERITY_LISTBOX_ITEMS = [
  { value: 'critical', text: s__('SecurityOrchestration|Critical') },
  { value: 'high', text: s__('SecurityOrchestration|High') },
  { value: 'medium', text: s__('SecurityOrchestration|Medium') },
  { value: 'low', text: s__('SecurityOrchestration|Low') },
  { value: 'info', text: s__('SecurityOrchestration|Info') },
  { value: 'unknown', text: s__('SecurityOrchestration|Unknown') },
];

// Matches the backend's risk_severity JSON schema enum exactly (critical/high/medium/low
// only), rather than excluding info/unknown, so a future SEVERITY_LISTBOX_ITEMS addition
// can't silently become a schema-invalid option here.
export const RISK_SEVERITY_LISTBOX_ITEMS = SEVERITY_LISTBOX_ITEMS.filter(({ value }) =>
  ['critical', 'high', 'medium', 'low'].includes(value),
);

export const DEFAULT_RISK_SEVERITY_THRESHOLD = 0;

export const ENFORCEMENT_ENFORCED = 'enforced';
export const ENFORCEMENT_WARN = 'warn';

export const ENFORCEMENT_TYPE_ITEMS = [
  {
    value: ENFORCEMENT_ENFORCED,
    text: s__('SecurityOrchestration|Enforce'),
    description: s__('SecurityOrchestration|Hard enforcement. Violations are blocked as defined.'),
    icon: 'status-failed',
    iconClass: 'gl-text-danger',
  },
  {
    value: ENFORCEMENT_WARN,
    text: s__('SecurityOrchestration|Warn'),
    description: s__(
      'SecurityOrchestration|Advisory mode. Violations are flagged but progress is not blocked.',
    ),
    icon: 'status-alert',
    iconClass: 'gl-text-warning',
  },
];
