import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import apolloProvider from 'ee/vue_shared/security_configuration/graphql/provider';
import App from './components/app.vue';

export default function init() {
  const el = document.querySelector('#js-secret-detection-configuration');

  if (!el) {
    return undefined;
  }

  const { projectFullPath } = el.dataset;

  return initVueApp({
    el,
    name: 'SecretDetectionConfigurationRoot',
    apolloProvider,
    provide: {
      projectFullPath,
    },
    component: App,
  });
}
