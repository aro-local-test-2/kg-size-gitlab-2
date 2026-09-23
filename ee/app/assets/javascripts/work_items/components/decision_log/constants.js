// Mirrors the limits the storage model enforces, so the form fails before the request does.
// https://gitlab.com/gitlab-org/gitlab/-/work_items/603064#note_3698679976
export const DECISION_TITLE_LENGTH_MAX = 255;
export const DECISION_DESCRIPTION_LENGTH_MAX = 1000;
export const DECISION_RATIONALE_LENGTH_MAX = 800;

// How close to a limit a field has to be before the count is worth showing. Below this the
// count is noise on a form where most entries are nowhere near the limit.
export const DECISION_REMAINING_COUNT_THRESHOLD = 50;

// The card owns the anchor and the panel clears it on close, so both sides read the prefix
// from here.
export const DECISION_ANCHOR_PREFIX = 'decision_';

// Mirrors the `WorkItemDecisionState` GraphQL enum. The state is derived from the timestamps on
// the record, so an archived decision is always a resolved one too.
export const DECISION_STATE_ARCHIVED = 'ARCHIVED';
