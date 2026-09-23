import { s__ } from '~/locale';

// Predefined Rego starting points offered from the "Browse templates" modal on
// custom Rego fields. `rego` is inserted verbatim into the editor when picked.
// Every template must declare `package governance` as its first statement:
// Gitlab::PolicyStore::RuleTranspiler rejects a custom rule without it.
/* eslint-disable @gitlab/require-i18n-strings -- Rego snippets are code, not translatable copy */
export const DEPLOYMENT_GATE_REGO = `package governance

deny contains msg if {
  input.environment.name == "production"
  msg := "Production deployment blocked"
}`;

export const REGO_TEMPLATES = [
  {
    id: 'blank',
    name: s__('PolicyStore|Blank Template'),
    description: s__('PolicyStore|Start from scratch'),
    icon: 'doc-text',
    rego: 'package governance\n\ndefault allow := false\n',
  },
  {
    id: 'deployment_gate',
    name: s__('PolicyStore|Deployment Gate'),
    description: s__('PolicyStore|Validate deployment prerequisites'),
    icon: 'doc-text',
    rego: DEPLOYMENT_GATE_REGO,
  },
];
/* eslint-enable @gitlab/require-i18n-strings */
