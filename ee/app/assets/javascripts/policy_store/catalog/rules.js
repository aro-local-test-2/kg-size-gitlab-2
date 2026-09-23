import { s__ } from '~/locale';
import {
  FIELD_TYPE_CODE,
  FIELD_TYPE_FREEZE_WINDOWS,
  FIELD_TYPE_MULTI_BADGE,
  FIELD_TYPE_TEXT_LIST,
} from '../components/editor/constants';
import { CATEGORY_ADVANCED, CATEGORY_DEPLOYMENT } from './categories';
import { DEPLOYMENT_GATE_REGO } from './rego_templates';

// The deployment tiers `app/models/environment.rb` defines; both deployment
// rules constrain against the same set.
const ENVIRONMENT_TIER_OPTIONS = [
  { id: 'production', label: s__('PolicyStore|Production') },
  { id: 'staging', label: s__('PolicyStore|Staging') },
  { id: 'testing', label: s__('PolicyStore|Testing') },
  { id: 'development', label: s__('PolicyStore|Development') },
  { id: 'other', label: s__('PolicyStore|Other') },
];

// Rules a policy can evaluate. `id` is persisted as the rule object's `type`, so it is the wire
// value, and the ids mirror the backend's catalog (Gitlab::PolicyStore::Rules in the
// gitlab-policy-store gem) exactly — the API supplies which rules exist, this file supplies
// their presentation. `RULE_CUSTOM` in particular is fixed:
// EE::Ci::ProcessBuildService#rego_of looks for `rule['type'] == 'custom'` when reading a
// policy's Rego back at evaluation time.
export const RULE_CUSTOM = 'custom';
export const RULE_CALENDAR = 'calendar';
export const RULE_ENVIRONMENT = 'environment';

export const RULES = [
  {
    id: RULE_CUSTOM,
    category: CATEGORY_ADVANCED,
    label: s__('PolicyStore|Custom Rule (Rego)'),
    description: s__('PolicyStore|Evaluate the event against custom OPA/Rego policy code'),
    icon: 'code',
    fields: [
      {
        key: 'policy',
        type: FIELD_TYPE_CODE,
        label: s__('PolicyStore|Rego policy definition'),
        helpText: s__(
          'PolicyStore|OPA/Rego policy evaluated server-side when the event is received. Maximum 32 KB.',
        ),
        maxLength: 32768,
        // The store cannot compile an empty program and refuses any package
        // other than `governance` (Gitlab::PolicyStore::RuleTranspiler), so
        // the wizard blocks saving either shape (catalog/validation.js).
        required: true,
        // eslint-disable-next-line @gitlab/require-i18n-strings -- Rego syntax, not UI copy
        firstStatement: 'package governance',
        default: DEPLOYMENT_GATE_REGO,
      },
    ],
  },
  {
    id: RULE_CALENDAR,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Freeze Window'),
    description: s__('PolicyStore|Block deployments during configured freeze periods'),
    icon: 'clock',
    // Wire contract lives in Gitlab::PolicyStore::RuleTranspiler (gem, not this repo).
    fields: [
      {
        key: 'windows',
        type: FIELD_TYPE_FREEZE_WINDOWS,
        label: s__('PolicyStore|Freeze windows'),
        required: true,
        helpText: s__(
          'PolicyStore|Deployments to the selected tiers are blocked during each window. Enter the start and end as a date and time with a time zone, using whole seconds only (no decimal fractions), for example 2026-12-24T00:00:00Z or 2026-12-24T01:00:00+01:00. At least one window is required.',
        ),
        options: ENVIRONMENT_TIER_OPTIONS,
      },
    ],
  },
  {
    id: RULE_ENVIRONMENT,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Environment State'),
    description: s__(
      'PolicyStore|When a deployment environment is not in the required operational state',
    ),
    icon: 'deployments',
    // The store validates this rule's value as `{ names: [...], tiers: [...] }`
    // with at least one of the two non-empty (Gitlab::PolicyStore::RuleTranspiler).
    requireOneOf: ['names', 'tiers'],
    fields: [
      {
        key: 'names',
        type: FIELD_TYPE_TEXT_LIST,
        label: s__('PolicyStore|Environment names'),
        placeholder: s__('PolicyStore|e.g. production, staging'),
        helpText: s__(
          'PolicyStore|Comma-separated environment names this rule applies to. At least one name or tier is required.',
        ),
      },
      {
        key: 'tiers',
        type: FIELD_TYPE_MULTI_BADGE,
        label: s__('PolicyStore|Environment tiers'),
        helpText: s__(
          'PolicyStore|Deployment tiers this rule applies to. At least one name or tier is required.',
        ),
        options: ENVIRONMENT_TIER_OPTIONS,
      },
    ],
  },
];
