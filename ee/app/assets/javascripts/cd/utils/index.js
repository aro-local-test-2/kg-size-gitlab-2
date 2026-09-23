import {
  ROLLOUT_STATE_VARIANTS,
  ROLLOUT_STATE_LABELS,
  ROLLOUT_STATE_DOT_CLASSES,
  RELEASE_STATUS_LABELS,
  RELEASE_STATUS_VARIANTS,
  RELEASE_STATUS_PENDING,
  RELEASE_STATUS_AVAILABLE,
  ROLLOUT_STATE_COMPLETED,
  NEUTRAL_BG_CLASS,
  ROW_CLASS,
} from '../constants';

export const rolloutStateVariant = (state) => ROLLOUT_STATE_VARIANTS[state] ?? 'neutral';

export const rolloutStateLabel = (state) => ROLLOUT_STATE_LABELS[state] ?? '';

export const rolloutStateDotClass = (state) => ROLLOUT_STATE_DOT_CLASSES[state] ?? NEUTRAL_BG_CLASS;

// `CdVersionSet.status` is `null` for the live release, a never-deployed release, or a
// failed/cancelled rollout. `Available` and `Pending` here are a stopgap derived from the
// latest rollout, until the backend returns a real status for the live release.
const releaseStatus = (release) => {
  if (!release) {
    return null;
  }

  if (release.status) {
    return release.status;
  }

  const latestRolloutState = release.rollouts?.nodes?.[0]?.state;

  if (!latestRolloutState) {
    return RELEASE_STATUS_PENDING;
  }

  return latestRolloutState === ROLLOUT_STATE_COMPLETED ? RELEASE_STATUS_AVAILABLE : null;
};

export const releaseStatusLabel = (release) => RELEASE_STATUS_LABELS[releaseStatus(release)] ?? '';

export const releaseStatusVariant = (release) =>
  RELEASE_STATUS_VARIANTS[releaseStatus(release)] ?? 'neutral';

export const buildRowClass = (id, matchers) => {
  const match = matchers.find(([matchId]) => matchId != null && matchId === id);
  return match ? [ROW_CLASS, match[1]] : ROW_CLASS;
};
