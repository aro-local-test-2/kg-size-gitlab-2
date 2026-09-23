import { RELEASE_STATE_DISPLAY_ORDER } from './constants';

const compareTitles = (a, b) => (a.title || '').localeCompare(b.title || '');

const releaseStateRank = ({ releaseState }) =>
  RELEASE_STATE_DISPLAY_ORDER[releaseState] ?? Number.MAX_SAFE_INTEGER;

export const sortFeatureSettingsByTitle = (featureSettings) =>
  [...featureSettings].sort(compareTitles);

export const sortFeatureSettingsByReleaseStateThenTitle = (featureSettings) =>
  [...featureSettings].sort(
    (a, b) => releaseStateRank(a) - releaseStateRank(b) || compareTitles(a, b),
  );
