<script>
import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import { s__ } from '~/locale';
import { GRAPHQL_PAGE_SIZE } from '../../../constants';
import getManifestReferrersQuery from '../../../graphql/queries/get_manifest_referrers.query.graphql';
import ReferrersTable from './referrers_table.vue';

export default {
  name: 'ArtifactRegistryReferrersSection',
  components: {
    GlAlert,
    GlSkeletonLoader,
    ReferrersTable,
  },
  inject: ['organizationGid'],
  props: {
    name: {
      type: String,
      required: true,
    },
    artifactId: {
      type: String,
      required: true,
    },
    digest: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      referrers: undefined,
      hasError: false,
    };
  },
  apollo: {
    referrers: {
      query: getManifestReferrersQuery,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.name,
          artifactId: this.artifactId,
          digest: this.digest,
          first: GRAPHQL_PAGE_SIZE,
        };
      },
      update: ({ organization }) =>
        organization?.artifactRegistryRepository?.manifest?.referrers ?? null,
      // Not redundant with `error` below: this query sets no `errorPolicy`, so vue-apollo calls
      // `result` on failure too. Clearing unconditionally here would drop the alert.
      result({ error }) {
        this.hasError = Boolean(error);
      },
      error() {
        this.hasError = true;
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.referrers.loading;
    },
    rows() {
      return this.referrers?.nodes ?? [];
    },
    // An absent connection is a manifest that stopped resolving, not one nothing attests to, so
    // it reads as a failure rather than as an empty list.
    hasFailed() {
      return this.hasError || (!this.isLoading && this.referrers === null);
    },
    isFirstRead() {
      return this.isLoading && !this.rows.length;
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
  },
};
</script>

<template>
  <gl-skeleton-loader v-if="isFirstRead" :lines="3" data-testid="referrers-skeleton" />

  <gl-alert
    v-else-if="hasFailed"
    variant="danger"
    :dismissible="false"
    data-testid="referrers-error"
  >
    {{ $options.i18n.unavailable }}
  </gl-alert>

  <referrers-table
    v-else
    :referrers="rows"
    :name="name"
    :artifact-id="artifactId"
    :subject-digest="digest"
    :is-loading="isLoading"
  />
</template>
