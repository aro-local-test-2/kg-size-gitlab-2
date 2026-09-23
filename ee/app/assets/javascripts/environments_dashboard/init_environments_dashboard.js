import createStore from 'ee/vue_shared/dashboards/store';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import EnvironmentDashboardComponent from './components/dashboard/dashboard.vue';

export function initEnvironmentsDashboard() {
  const el = document.querySelector('#js-environments');

  if (!el) {
    return null;
  }

  const {
    addPath,
    listPath,
    emptyDashboardSvgPath,
    emptyDashboardHelpPath,
    environmentsDashboardHelpPath,
  } = el.dataset;

  return initVueApp({
    el,
    name: 'EnvironmentDashboardComponentRoot',
    store: createStore(),
    component: EnvironmentDashboardComponent,
    props: {
      addPath,
      listPath,
      emptyDashboardSvgPath,
      emptyDashboardHelpPath,
      environmentsDashboardHelpPath,
    },
  });
}
