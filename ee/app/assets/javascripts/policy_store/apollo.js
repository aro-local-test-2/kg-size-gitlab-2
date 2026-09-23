import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';

Vue.use(VueApollo);

let client;

// Shared with plain modules (policies.js) that query outside a component tree.
// Lazy so importing the module does not build a client on pages that never query.
export const gqlClient = () => {
  // The policies and catalogs queries run concurrently and both write
  // organization.policyStore, which has no id to normalize on — without
  // merge, Apollo replaces the earlier write and drops its fields.
  client ??= createDefaultClient(
    {},
    {
      cacheConfig: {
        typePolicies: { Organization: { fields: { policyStore: { merge: true } } } },
      },
    },
  );
  return client;
};

export default () => new VueApollo({ defaultClient: gqlClient() });
