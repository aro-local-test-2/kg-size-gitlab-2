import { joinPaths } from '~/lib/utils/url_utility';

// The model selection page is a Vue router app; `features` is its feature list route.
export const getModelConfigurationPath = (duoModelSelectionPath) => {
  return duoModelSelectionPath ? joinPaths(duoModelSelectionPath, 'features') : '';
};
