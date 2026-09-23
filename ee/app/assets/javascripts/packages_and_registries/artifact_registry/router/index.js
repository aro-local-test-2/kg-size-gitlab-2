import Vue from 'vue';
import VueRouter from 'vue-router';
import SpaRouterView from '~/vue_shared/spa/components/router_view.vue';
import NotFound from '../components/not_found.vue';
import {
  ARTIFACT_VERSIONS_ROUTE_NAME,
  MANIFEST_DETAIL_ROUTE_NAME,
  NOT_FOUND_ROUTE_NAME,
  PAGE_NOT_FOUND_TITLE,
  REPOSITORIES_LIST_ROUTE_NAME,
  REPOSITORIES_LIST_TITLE,
  REPOSITORY_DETAIL_ROUTE_NAME,
  REPOSITORY_EDIT_CRUMB,
  REPOSITORY_EDIT_ROUTE_NAME,
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_NEW_TITLES,
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_KIND_VIRTUAL,
  REPOSITORY_NEW_HOSTED_ROUTE_NAME,
  REPOSITORY_NEW_REMOTE_ROUTE_NAME,
  REPOSITORY_NEW_VIRTUAL_ROUTE_NAME,
  VERSION_DETAIL_ROUTE_NAME,
} from '../constants';
import RepositoriesList from '../repositories/list/repositories_list.vue';
import RepositoriesCreateForm from '../repositories/create/repositories_create_form.vue';
import RepositoryDetail from '../repositories/detail/repository_detail.vue';
import RepositoriesEditForm from '../repositories/edit/repositories_edit_form.vue';
import VersionList from '../repositories/versions/version_list.vue';
import VersionDetail from '../repositories/versions/detail/version_detail.vue';
import ManifestDetail from '../repositories/versions/detail/manifest_detail.vue';

Vue.use(VueRouter);

export const createRouter = (base, breadCrumbState = {}) => {
  const router = new VueRouter({
    base,
    mode: 'history',
    // The breadcrumb trail comes from `$route.matched`, which holds ancestors only, so a
    // crumb every page trails behind lives on a node they all descend from rather than on
    // the page that crumb links to.
    routes: [
      {
        path: '/',
        component: SpaRouterView,
        // This node renders no view of its own, so it hands its name to the list child
        // and names that child in `defaultRoute` for the crumb to link to. `skipTitle`
        // keeps the crumb out of the document title: the node is matched on every route,
        // and the Rails view already sets `page_title` to Repositories, so folding the
        // text in would name the page twice.
        meta: {
          text: REPOSITORIES_LIST_TITLE,
          defaultRoute: REPOSITORIES_LIST_ROUTE_NAME,
          skipTitle: true,
        },
        children: [
          {
            path: '',
            name: REPOSITORIES_LIST_ROUTE_NAME,
            component: RepositoriesList,
          },
          {
            path: 'new/hosted',
            name: REPOSITORY_NEW_HOSTED_ROUTE_NAME,
            component: RepositoriesCreateForm,
            meta: {
              text: REPOSITORY_KIND_NEW_TITLES[REPOSITORY_KIND_HOSTED],
              kind: REPOSITORY_KIND_HOSTED,
            },
          },
          {
            path: 'new/remote',
            name: REPOSITORY_NEW_REMOTE_ROUTE_NAME,
            component: RepositoriesCreateForm,
            meta: {
              text: REPOSITORY_KIND_NEW_TITLES[REPOSITORY_KIND_REMOTE],
              kind: REPOSITORY_KIND_REMOTE,
            },
          },
          {
            path: 'new/virtual',
            name: REPOSITORY_NEW_VIRTUAL_ROUTE_NAME,
            component: RepositoriesCreateForm,
            meta: {
              text: REPOSITORY_KIND_NEW_TITLES[REPOSITORY_KIND_VIRTUAL],
              kind: REPOSITORY_KIND_VIRTUAL,
            },
          },
          {
            path: 'new',
            redirect: { name: REPOSITORY_NEW_HOSTED_ROUTE_NAME },
          },
          // A repository name is a lone path segment, so this node claims every one the
          // create routes above have not already reserved. It renders no view of its own:
          // it is the repository the pages below it act on, and `meta.useId` is what makes
          // its crumb the name in the current route. It hands its name to the detail child
          // so that crumb has a page to link to.
          {
            path: ':id',
            component: SpaRouterView,
            meta: { useId: true, defaultRoute: REPOSITORY_DETAIL_ROUTE_NAME },
            children: [
              // Spelled absolute rather than as the empty default child: vue-router
              // joins a relative child onto its parent, so an empty path would record
              // this page at `/:id/` and the repository crumb above would link to a
              // trailing-slash URL rather than the one the list links to.
              {
                path: '/:id',
                name: REPOSITORY_DETAIL_ROUTE_NAME,
                component: RepositoryDetail,
              },
              {
                path: 'edit',
                name: REPOSITORY_EDIT_ROUTE_NAME,
                component: RepositoriesEditForm,
                // The kind that would name this page in full arrives with the prefill,
                // after the route resolves, so the trail's Edit crumb names it instead.
                meta: { text: REPOSITORY_EDIT_CRUMB },
              },
              // Declared last for the same reason `:id` is declared after the create routes: a
              // bare parameter claims every repository-scoped segment above it has not
              // reserved. `idParam` is what keeps its crumb off the ancestor's `id`.
              //
              // The segment is an opaque id, so `nameGenerator` is where the route says
              // what it is really called. The view resolves that name and publishes it;
              // until then the id stands in.
              {
                path: ':artifactId',
                component: SpaRouterView,
                meta: {
                  useId: true,
                  idParam: 'artifactId',
                  defaultRoute: ARTIFACT_VERSIONS_ROUTE_NAME,
                  nameGenerator: () => breadCrumbState.artifactName,
                },
                children: [
                  {
                    path: '/:id/:artifactId',
                    name: ARTIFACT_VERSIONS_ROUTE_NAME,
                    component: VersionList,
                  },
                  // Both lead with a literal, so neither claims the other's segment and order
                  // between them is free. The `edit` route above does depend on declaration
                  // order; these do not.
                  {
                    path: 'manifests/:digest',
                    name: MANIFEST_DETAIL_ROUTE_NAME,
                    component: ManifestDetail,
                    meta: {
                      useId: true,
                      idParam: 'digest',
                      nameGenerator: () => breadCrumbState.manifestName,
                    },
                  },
                  {
                    path: 'versions/:versionId',
                    name: VERSION_DETAIL_ROUTE_NAME,
                    component: VersionDetail,
                    meta: {
                      useId: true,
                      idParam: 'versionId',
                      nameGenerator: () => breadCrumbState.versionName,
                    },
                  },
                ],
              },
            ],
          },
          {
            path: '*',
            name: NOT_FOUND_ROUTE_NAME,
            component: NotFound,
            meta: { text: PAGE_NOT_FOUND_TITLE },
          },
        ],
      },
    ],
  });

  return router;
};
