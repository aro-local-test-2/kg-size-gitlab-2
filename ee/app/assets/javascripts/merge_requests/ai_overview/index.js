import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';
import App from './components/app.vue';

Vue.use(VueApollo);

// Appended rather than mounted over `el`, because Vue replaces its mount point and the rest of the
// page reads that element to tell whether the overview replacement is active.
export default (el) => {
  // Landing on commits or pipelines mounts here, and switching to Overview then runs
  // `pageBundles.show` too, so a second append would duplicate the app.
  if (el.firstElementChild) return null;

  const { projectPath, iid } = el.dataset;

  const apolloProvider = new VueApollo({
    defaultClient: createDefaultClient(),
  });

  const app = new Vue({
    name: 'MergeRequestAiOverviewRoot',
    apolloProvider,
    provide: {
      projectPath,
      iid,
    },
    render(h) {
      return h(App);
    },
  }).$mount();

  el.appendChild(app.$el);

  return app;
};
