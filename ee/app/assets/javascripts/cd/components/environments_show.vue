<script>
import { GlButton, GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { TYPENAME_CD_ENVIRONMENT } from 'ee/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import { EMPTY_PLACEHOLDER } from '../constants';
import cdEnvironmentQuery from '../graphql/environments/cd_environment.query.graphql';
import DeploymentDetails from './deployment_details.vue';

export default {
  name: 'EnvironmentsShow',
  components: {
    DeploymentDetails,
    GlButton,
    GlEmptyState,
    GlLoadingIcon,
    PageHeading,
  },
  props: {
    id: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      environment: null,
    };
  },
  apollo: {
    environment: {
      query: cdEnvironmentQuery,
      variables() {
        return { id: this.environmentGid };
      },
      update(data) {
        return data?.organization?.cdEnvironment ?? null;
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    environmentGid() {
      return convertToGraphQLId(TYPENAME_CD_ENVIRONMENT, this.id);
    },
    isLoading() {
      return this.$apollo.queries.environment.loading;
    },
    runningAppsCount() {
      return this.environment?.applicationsCount ?? EMPTY_PLACEHOLDER;
    },
    environmentApplications() {
      return this.environment?.applications?.nodes ?? [];
    },
    environmentsIndexRoute() {
      return { name: 'environments_index_route' };
    },
  },
};
</script>

<template>
  <div>
    <div class="gl-mb-3">
      <gl-button
        variant="link"
        icon="arrow-left"
        :to="environmentsIndexRoute"
        data-testid="back-link"
      >
        {{ s__('ContinuousDeployment|All environments') }}
      </gl-button>
    </div>

    <gl-loading-icon v-if="isLoading" size="lg" class="gl-mt-5" />

    <gl-empty-state
      v-else-if="!environment"
      :title="s__('ContinuousDeployment|Environment not found')"
      :description="
        s__(
          'ContinuousDeployment|The environment may have been removed or you may not have access to it.',
        )
      "
    />

    <template v-else>
      <page-heading :heading="environment.name">
        <template #heading>
          <span data-testid="environment-name">{{ environment.name }}</span>
        </template>
      </page-heading>

      <div class="gl-flex gl-flex-wrap gl-gap-4">
        <div
          class="gl-border gl-min-w-20 gl-rounded-lg gl-border-section gl-p-4"
          data-testid="metadata-tile-running-apps"
        >
          <div class="gl-text-xs gl-font-bold gl-uppercase gl-tracking-wider gl-text-subtle">
            {{ s__('ContinuousDeployment|Running Apps') }}
          </div>
          <div class="gl-mt-1 gl-font-monospace gl-text-sm">
            {{ runningAppsCount }}
          </div>
        </div>
      </div>

      <deployment-details :applications="environmentApplications" />
    </template>
  </div>
</template>
