import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import App from './components/editor/app.vue';
import createApolloProvider from './apollo';

// The page entrypoint supplies namespaceType: each webpack page bundle is
// loaded by exactly one surface's controller, so the bundle itself is the
// source of truth for which surface the editor is mounted on.
export default (el, namespaceType) => {
  if (!el) return null;

  const { namespacePath, organizationId, policyId, listPath } = el.dataset;

  return initVueApp({
    el,
    apolloProvider: createApolloProvider(),
    name: 'PolicyStoreEditorRoot',
    provide: {
      namespacePath: namespacePath || '',
      namespaceType: namespaceType || '',
      organizationId,
      policyId: policyId || '',
      listPath: listPath || '',
    },
    component: App,
  });
};
