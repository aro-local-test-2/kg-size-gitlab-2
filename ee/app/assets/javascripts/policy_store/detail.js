import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import App from './components/detail/app.vue';
import createApolloProvider from './apollo';

export default (el) => {
  if (!el) return null;

  const { organizationId, namespacePath, namespaceType, policyId, listPath, editPath } = el.dataset;

  return initVueApp({
    el,
    apolloProvider: createApolloProvider(),
    name: 'PolicyStoreDetailRoot',
    provide: {
      organizationId,
      namespacePath: namespacePath || '',
      namespaceType: namespaceType || '',
      policyId,
      listPath: listPath || '',
      editPath: editPath || '',
    },
    component: App,
  });
};
