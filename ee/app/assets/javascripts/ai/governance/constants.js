import { s__ } from '~/locale';

// AiToolActionType GraphQL enum values. Used by the AI tool rules search filter.
export const ACTION_TYPE_READ = 'READ';
export const ACTION_TYPE_WRITE = 'WRITE';
export const ACTION_TYPE_DESTROY = 'DESTROY';

// Filtered-search token type for the action filter.
export const TOKEN_TYPE_ACTION = 'action';

// Static options for the action token, mapping a human title to the enum value.
export const ACTION_TOKEN_OPTIONS = [
  { value: ACTION_TYPE_READ, title: s__('AiGovernance|Read') },
  { value: ACTION_TYPE_WRITE, title: s__('AiGovernance|Write') },
  { value: ACTION_TYPE_DESTROY, title: s__('AiGovernance|Destroy') },
];

// AiGovernanceAgentClass GraphQL enum values. Drives the dashboard agent-class
// filter and every card query that segments by it.
export const AGENT_CLASS_ALL = 'ALL';
export const AGENT_CLASS_INTERNAL_DAP = 'INTERNAL_DAP';
export const AGENT_CLASS_EXTERNAL = 'EXTERNAL';

// AiGovernanceMetricsTimeframe GraphQL enum values. The enum also accepts
// LAST_24_HOURS, which needs an hourly chart axis before it can be offered.
export const TIMEFRAME_LAST_SEVEN_DAYS = 'LAST_7_DAYS';
export const TIMEFRAME_LAST_THIRTY_DAYS = 'LAST_30_DAYS';

// SkillGuard publishes as a SAST report, so `report_type` cannot distinguish it.
// The scanner `external_id` is the discriminator, and the project-scope deep-link param.
export const SKILLGUARD_SCANNER_ID = 'skillguard';

// Group-scope deep-link param: the group Vulnerability Report offers an identifier
// token but no scanner one. Matches `primaryIdentifierName` in the analyzer's convert.go.
export const SKILLGUARD_IDENTIFIER_NAME = 'SkillGuard Skill Analysis';

// Most severe first.
export const SKILLGUARD_SEVERITIES = ['critical', 'high', 'medium', 'low', 'unknown', 'info'];

// Severity-to-verdict mapping agreed on #629070, and the single source of truth for it.
// The analyzer publishes severity only, never the verdict, so this is a product
// convention rather than data. HIGH also covers the analyzer's DANGEROUS verdict, and
// severities absent here keep their own name instead of being guessed at.
export const SKILLGUARD_VERDICT_LABELS = {
  critical: s__('AiGovernance|malicious'),
  high: s__('AiGovernance|suspicious'),
};
