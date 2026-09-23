import Vue from 'vue';
import VueRouter from 'vue-router';
import VueApollo from 'vue-apollo';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import { getRoutes } from 'ee/groups/settings/work_items/routes';
import AdminWorkItemSettings from './admin_work_item_settings.vue';

Vue.use(VueApollo);

const apolloProvider = new VueApollo({
  defaultClient: createDefaultClient(),
});

export const initAdminWorkItemSettings = () => {
  const el = document.querySelector('#js-admin-work-item-settings');

  if (!el) {
    return false;
  }

  const { basePath } = el.dataset;

  return initVueApp({
    el,
    router: new VueRouter({
      mode: 'history',
      base: basePath,
      routes: getRoutes(''),
    }),
    apolloProvider,
    name: 'AdminWorkItemSettings',
    component: AdminWorkItemSettings,
  });
};
