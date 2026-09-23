import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createApolloClient from '~/lib/graphql';
import CreditCapsDashboardApp from './components/app.vue';

/**
 * @param {HTMLElement} el
 */
export function initCreditCapsDashboard(el) {
  if (!el) return null;

  const { namespacePath = null } = el.dataset;

  Vue.use(VueApollo);
  const apolloProvider = new VueApollo({
    defaultClient: createApolloClient(),
  });

  return initVueApp({
    el,
    apolloProvider,
    name: 'CreditCapsDashboardRoot',
    provide: {
      namespacePath,
    },
    component: CreditCapsDashboardApp,
  });
}
