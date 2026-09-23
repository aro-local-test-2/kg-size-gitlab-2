<script>
import { GlBreadcrumb } from '@gitlab/ui';
import { TYPENAME_CD_APPLICATION, TYPENAME_CD_ENVIRONMENT } from 'ee/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import cdApplicationNameQuery from 'ee/cd/graphql/applications/cd_application_name.query.graphql';
import cdEnvironmentNameQuery from 'ee/cd/graphql/environments/cd_environment_name.query.graphql';
import { RESOURCE_APPLICATION, RESOURCE_ENVIRONMENT } from '../router/constants';

export default {
  name: 'CdBreadcrumbs',
  components: {
    GlBreadcrumb,
  },
  // injectVueAppBreadcrumbs also passes a `staticBreadcrumbs` prop we don't declare;
  // without this it serializes onto the rendered element as a stray attribute.
  inheritAttrs: false,
  props: {
    allStaticBreadcrumbs: {
      required: true,
      type: Array,
    },
  },
  data() {
    return {
      applicationName: null,
      environmentName: null,
    };
  },
  apollo: {
    applicationName: {
      query: cdApplicationNameQuery,
      variables() {
        return { id: this.resourceId };
      },
      update(data) {
        return data?.organization?.cdApplication?.name ?? null;
      },
      skip() {
        return this.resource !== RESOURCE_APPLICATION;
      },
    },
    environmentName: {
      query: cdEnvironmentNameQuery,
      variables() {
        return { id: this.resourceId };
      },
      update(data) {
        return data?.organization?.cdEnvironment?.name ?? null;
      },
      skip() {
        return this.resource !== RESOURCE_ENVIRONMENT;
      },
    },
  },
  computed: {
    routeId() {
      return this.$route.params.id;
    },
    resource() {
      const idRoute = this.$route.matched.find((route) => route.meta?.useId);
      return idRoute?.meta?.resource;
    },
    resourceId() {
      if (!this.routeId) return null;

      const typename =
        this.resource === RESOURCE_ENVIRONMENT ? TYPENAME_CD_ENVIRONMENT : TYPENAME_CD_APPLICATION;

      return convertToGraphQLId(typename, this.routeId);
    },
    resolvedName() {
      if (this.resource === RESOURCE_APPLICATION) {
        return this.applicationName;
      }
      if (this.resource === RESOURCE_ENVIRONMENT) {
        return this.environmentName;
      }
      return null;
    },
    crumbs() {
      const matchedRoutes = this.$route.matched
        .map((route) => {
          const name = route.name || route.meta?.defaultRoute;

          return {
            text: this.crumbText(route),
            to: name ? { name } : { path: route.path },
          };
        })
        .filter((r) => r.text);

      return [...this.allStaticBreadcrumbs, ...matchedRoutes];
    },
  },
  watch: {
    routeId() {
      this.applicationName = null;
      this.environmentName = null;
    },
  },
  methods: {
    crumbText(route) {
      if (route.meta?.useId) {
        return this.resolvedName || this.routeId;
      }

      return route.meta?.text;
    },
  },
};
</script>
<template>
  <gl-breadcrumb :items="crumbs" :auto-resize="false" />
</template>
