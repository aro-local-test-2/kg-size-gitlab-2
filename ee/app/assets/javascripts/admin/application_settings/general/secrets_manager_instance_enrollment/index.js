import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import SecretsManagerInstanceSettings from './components/secrets_manager_instance_settings.vue';

Vue.use(VueApollo);

export const initSecretsManagerInstanceEnrollment = () => {
  const el = document.getElementById('js-secrets-manager-instance-enrollment');

  if (!el) return false;

  const apolloProvider = new VueApollo({
    defaultClient: createDefaultClient(),
  });

  return initVueApp({
    el,
    name: 'SecretsManagerInstanceSettingsRoot',
    apolloProvider,
    provide: {
      subscriptionsUrl: gon.subscriptions_url,
    },
    component: SecretsManagerInstanceSettings,
  });
};
