import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '~/lib/utils/common_utils';
import createDefaultClient from '~/lib/graphql';
import DependencyFirewallDashboardApp from './components/app.vue';

Vue.use(VueApollo);

const apolloProvider = new VueApollo({
  defaultClient: createDefaultClient(),
});

export default (el) => {
  if (!el) return null;

  const { fullPath, namespaceType, newPolicyPath, disableNewPolicy } = el.dataset;

  return new Vue({
    el,
    name: 'DependencyFirewallDashboardRoot',
    apolloProvider,
    render(createElement) {
      return createElement(DependencyFirewallDashboardApp, {
        props: {
          fullPath,
          namespaceType,
          newPolicyPath,
          disableNewPolicy: parseBoolean(disableNewPolicy),
        },
      });
    },
  });
};
