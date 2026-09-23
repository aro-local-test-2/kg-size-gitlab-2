import { s__ } from '~/locale';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';

// Wire values are StatusEnum's (state_machine names upcased by GraphQL), not
// RiskAssessment#status_name. QUEUED and PENDING both mean "not classified yet".
export const STATUS_PENDING = 'PENDING';
export const STATUS_QUEUED = 'QUEUED';
export const STATUS_COMPLETE = 'COMPLETE';
export const STATUS_FAILED = 'FAILED';

// Tracks lifecycle, not the result: pending/queued have nothing to report yet,
// and failed means the classification never reported back. Staleness is read off
// diff_sha instead, so it is deliberately not a status here.
export const STATUS_ICONS = {
  [STATUS_PENDING]: EXTENSION_ICONS.neutral,
  [STATUS_QUEUED]: EXTENSION_ICONS.notice,
  [STATUS_COMPLETE]: EXTENSION_ICONS.success,
  [STATUS_FAILED]: EXTENSION_ICONS.failed,
};

export const TIER_LOW = 'LOW';
export const TIER_MEDIUM = 'MEDIUM';
export const TIER_HIGH = 'HIGH';
export const TIER_CRITICAL = 'CRITICAL';

export const TIER_LABELS = {
  [TIER_LOW]: s__('RiskClassification|Low risk'),
  [TIER_MEDIUM]: s__('RiskClassification|Medium risk'),
  [TIER_HIGH]: s__('RiskClassification|High risk'),
  [TIER_CRITICAL]: s__('RiskClassification|Critical risk'),
};

export const TIER_BADGE_VARIANTS = {
  [TIER_LOW]: 'success',
  [TIER_MEDIUM]: 'warning',
  [TIER_HIGH]: 'danger',
  [TIER_CRITICAL]: 'danger',
};

// confidence_tier runs its score through the same Thresholds.tier_for as the risk
// tier, so the bands are shared and only the polarity differs: HIGH is good here.
export const CONFIDENCE_LABELS = {
  [TIER_LOW]: s__('RiskClassification|Low confidence'),
  [TIER_MEDIUM]: s__('RiskClassification|Medium confidence'),
  [TIER_HIGH]: s__('RiskClassification|High confidence'),
  [TIER_CRITICAL]: s__('RiskClassification|Very high confidence'),
};

export const CONFIDENCE_BADGE_VARIANTS = {
  [TIER_LOW]: 'danger',
  [TIER_MEDIUM]: 'warning',
  [TIER_HIGH]: 'success',
  [TIER_CRITICAL]: 'success',
};

// The widget mounts while the query is still in flight, so it needs every field
// present before the assessment arrives.
export const DEFAULT_RISK_ASSESSMENT = {
  status: null,
  riskTier: null,
  confidenceTier: null,
  rationale: null,
  stale: false,
  duoWorkflowId: null,
  contributingSignals: [],
  missingSignals: [],
};
