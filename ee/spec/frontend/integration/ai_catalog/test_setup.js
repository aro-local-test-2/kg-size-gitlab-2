import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';
import { assignRouter, fullMount } from 'ee_jest/integration/helpers/test_helpers';
import { createRouter } from 'ee/ai/catalog/router';
import { NAMESPACE_EXPLORE, NAMESPACE_PROJECT } from 'ee/ai/catalog/constants';

Vue.use(VueApollo);

beforeEach(() => {
  window.gon = {
    ...window.gon,
    features: { ...window.gon?.features },
  };
});

afterEach(() => {
  document.getElementById('gl-toaster')?.remove();
});

// Mirrors ee/app/assets/javascripts/ai/catalog/index.js
export const EXPLORE_PROVIDE = {
  namespace: NAMESPACE_EXPLORE,
  isGlobalNamespace: true,
  isProjectNamespace: false,
  isGroupNamespace: false,
  aiImpactDashboardEnabled: false,
  instanceBetaFeaturesEnabled: false,
  showLegalDisclaimer: false,
};

// Mirrors ee/app/assets/javascripts/ai/duo_agents_platform/index.js
// + namespace/project/index.js
export const PROJECT_PROVIDE = {
  namespace: NAMESPACE_PROJECT,
  isGlobalNamespace: false,
  isProjectNamespace: true,
  isGroupNamespace: false,
  projectId: '1',
  projectPath: 'gitlab-org/gitlab',
  rootGroupId: null,
  aiImpactDashboardEnabled: false,
  aiImpactDashboardPath: null,
  instanceBetaFeaturesEnabled: false,
};

const createAiCatalogRouter = () => createRouter('/');

export function mountAiCatalogComponent({
  component,
  routePath,
  apolloProvider,
  provide,
  propsData,
}) {
  if (!provide) {
    throw new Error(
      'mountAiCatalogComponent requires a `provide` argument. Use PROJECT_PROVIDE or EXPLORE_PROVIDE.',
    );
  }

  const router = assignRouter(createAiCatalogRouter, { routerPath: routePath });

  return fullMount(component, {
    router,
    apolloProvider,
    provide,
    propsData,
  });
}

export function createApolloProvider() {
  return new VueApollo({ defaultClient: createDefaultClient() });
}
