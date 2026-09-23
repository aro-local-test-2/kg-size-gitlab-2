import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';
import { observable } from '~/lib/utils/observable';
import { injectVueAppBreadcrumbs } from '~/lib/utils/breadcrumbs';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { possibleTypes, typePolicies } from '../graphql/cache_config';
import { mockResolvers } from '../graphql/mock_resolvers';
import { createRouter } from '../router';
import App from './app.vue';
import ArtifactRegistryBreadcrumbs from './artifact_registry_breadcrumbs.vue';

Vue.use(VueApollo);

export const initArtifactRegistryRepositories = () => {
  const el = document.getElementById('js-artifact-registry-repositories');

  if (!el) return false;

  const {
    dataset: { appData },
  } = el;
  const { organizationGid, slug, basePath, clientBaseUrl } = convertObjectPropsToCamelCase(
    JSON.parse(appData),
  );

  const apolloProvider = new VueApollo({
    defaultClient: createDefaultClient(mockResolvers, {
      cacheConfig: { typePolicies, possibleTypes },
    }),
  });

  // The artifact and version segments are both addressed by opaque ids, so each page publishes
  // the name it resolves into its own slot and the trail and the title render those instead.
  const breadCrumbState = observable('artifact_registry_breadcrumb', {
    artifactName: '',
    versionName: '',
    manifestName: '',
    updateArtifactName(value) {
      this.artifactName = value;
    },
    updateVersionName(value) {
      this.versionName = value;
    },
    updateManifestName(value) {
      this.manifestName = value;
    },
  });

  const router = createRouter(basePath, breadCrumbState);

  injectVueAppBreadcrumbs(router, ArtifactRegistryBreadcrumbs, apolloProvider);

  return initVueApp({
    el,
    name: 'ArtifactRegistryRepositoriesRoot',
    router,
    apolloProvider,
    provide: {
      breadCrumbState,
      organizationGid,
      slug,
      clientBaseUrl,
    },
    component: App,
  });
};
