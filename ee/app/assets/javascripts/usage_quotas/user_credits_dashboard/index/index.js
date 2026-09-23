import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createApolloClient from '~/lib/graphql';
import UserCreditsDashboardApp from './components/app.vue';

/**
 * @param {HTMLElement} el
 */
export function initUserCreditsDashboard(el) {
  if (!el) return null;

  const { groupsWithGitlabCredits } = el.dataset;

  Vue.use(VueApollo);
  const apolloProvider = new VueApollo({
    defaultClient: createApolloClient(),
  });

  return new Vue({
    el,
    apolloProvider,
    name: 'UserCreditsDashboardRoot',
    provide: {
      groups: JSON.parse(groupsWithGitlabCredits),
    },
    render(createElement) {
      return createElement(UserCreditsDashboardApp);
    },
  });
}
