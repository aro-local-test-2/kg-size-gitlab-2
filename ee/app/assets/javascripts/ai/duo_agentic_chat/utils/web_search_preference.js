import { getStorageValue, saveStorageValue } from '~/lib/utils/local_storage';
import { WEB_SEARCH_PREFERENCE_STORAGE_KEY } from '../constants';

// localStorage access throws outright where site data is blocked (Safari private
// browsing), and these helpers do not guard it, so every call is wrapped: losing
// the preference is acceptable, failing to open chat is not.
export const saveWebSearchPreference = (webSearchEnabled) => {
  try {
    saveStorageValue(WEB_SEARCH_PREFERENCE_STORAGE_KEY, webSearchEnabled);
  } catch {
    /* ignore quota and access errors */
  }
};

export const loadWebSearchPreference = () => {
  try {
    const stored = getStorageValue(WEB_SEARCH_PREFERENCE_STORAGE_KEY);

    return stored.exists && stored.value === true;
  } catch {
    return false;
  }
};

// The group grant and the flag gate the control, so they have to gate the stored
// preference too: a `true` saved under a group that allows web search would
// otherwise be restored under one that forbids it, where the toggle is hidden and
// the user can neither see nor undo it.
export const isWebSearchAvailable = (glFeatures, webSearchAllowedForGroup) =>
  Boolean(glFeatures?.dapWebSearch) && Boolean(webSearchAllowedForGroup);
