import { s__, sprintf } from '~/locale';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_VULNERABILITY,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/constants';

const humanizeExceptions = (exceptions) =>
  (exceptions || []).map((exception) => exception.purl || exception.id).filter(Boolean);

const exceptionsCriteria = (exceptions) =>
  exceptions.length
    ? [
        sprintf(s__('SecurityOrchestration|Except for: %{exceptions}.'), {
          exceptions: exceptions.join(', '),
        }),
      ]
    : [];

const buildLicenseRule = (rule) => {
  const isDenied = Boolean(rule.denied?.length);
  const licenses = isDenied ? rule.denied : rule.allowed || [];
  const exceptions = humanizeExceptions(rule.exceptions);

  return {
    subheader: s__(
      'SecurityOrchestration|This policy applies when the license for a dependency matches any of the following criteria:',
    ),
    isDenied,
    items: licenses.map((license) => ({
      license: { text: license.name, value: license.name },
      exceptions,
    })),
  };
};

const buildMaliciousRule = (rule) => {
  const exceptions = humanizeExceptions(rule.exceptions);

  return {
    subheader: exceptions.length
      ? sprintf(
          s__(
            'SecurityOrchestration|This policy applies when a dependency is flagged as malicious, except for: %{exceptions}.',
          ),
          { exceptions: exceptions.join(', ') },
        )
      : s__('SecurityOrchestration|This policy applies when a dependency is flagged as malicious.'),
  };
};

const buildRiskSeverityRule = (rule) => {
  const criteriaList = (rule.denied || []).map(({ severity, threshold }) =>
    sprintf(
      s__(
        'SecurityOrchestration|Risk severity is %{severity} with a risk score of more than %{threshold}.',
      ),
      { severity, threshold },
    ),
  );

  return {
    subheader: s__(
      'SecurityOrchestration|This policy applies when the risk severity for a dependency matches any of the following criteria:',
    ),
    criteriaList: [...criteriaList, ...exceptionsCriteria(humanizeExceptions(rule.exceptions))],
  };
};

const buildVulnerabilityRule = (rule) => {
  const isDenied = Boolean(rule.denied?.length);
  const list = isDenied ? rule.denied : rule.allowed || [];

  const criteriaList = list.map(({ severity }) =>
    sprintf(
      isDenied
        ? s__('SecurityOrchestration|Denied severity: %{severity}.')
        : s__('SecurityOrchestration|Allowed severity: %{severity}.'),
      { severity },
    ),
  );

  return {
    subheader: s__(
      'SecurityOrchestration|This policy applies when the vulnerability severity for a dependency matches any of the following criteria:',
    ),
    criteriaList: [...criteriaList, ...exceptionsCriteria(humanizeExceptions(rule.exceptions))],
  };
};

export const humanizeRule = (rule) => {
  switch (rule.type) {
    case RULE_TYPE_MALICIOUS:
      return buildMaliciousRule(rule);
    case RULE_TYPE_RISK_SEVERITY:
      return buildRiskSeverityRule(rule);
    case RULE_TYPE_VULNERABILITY:
      return buildVulnerabilityRule(rule);
    case RULE_TYPE_LICENSE:
    case null:
    case undefined:
      return buildLicenseRule(rule);
    default:
      return {
        subheader: s__(
          "SecurityOrchestration|This policy applies to a rule type that can't be displayed yet.",
        ),
      };
  }
};

export const humanizeRules = (rules) => {
  let lastSubheaderShown;

  return (rules || []).map((rule, index) => {
    const humanized = { key: `${index}-${JSON.stringify(rule)}`, ...humanizeRule(rule) };

    const hasVisibleContent = humanized.items?.length || humanized.criteriaList?.length;

    if (hasVisibleContent && humanized.subheader === lastSubheaderShown) {
      humanized.subheader = '';
    } else {
      lastSubheaderShown = humanized.subheader;
    }

    return humanized;
  });
};
