<script>
import { GlTableLite } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { s__ } from '~/locale';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import { EMPTY_PLACEHOLDER, TD_CLASS, TH_CLASS } from '../constants';

const FIELDS = [
  {
    key: 'name',
    label: s__('ContinuousDeployment|Application'),
    tdClass: TD_CLASS,
    thClass: TH_CLASS,
  },
  {
    key: 'release',
    label: s__('ContinuousDeployment|Release'),
    tdClass: TD_CLASS,
    thClass: TH_CLASS,
  },
  {
    key: 'servicesCount',
    label: s__('ContinuousDeployment|Services'),
    tdClass: TD_CLASS,
    thClass: TH_CLASS,
  },
  {
    key: 'lastDeployedAt',
    label: s__('ContinuousDeployment|Last deployed'),
    tdClass: `${TD_CLASS} gl-whitespace-nowrap !gl-text-secondary`,
    thClass: `${TH_CLASS} gl-whitespace-nowrap`,
  },
];

export default {
  name: 'DeploymentDetails',
  components: {
    GlTableLite,
    TimeAgo,
  },
  props: {
    applications: {
      type: Array,
      required: true,
    },
  },
  computed: {
    applicationRows() {
      return this.applications
        .filter(({ application }) => application)
        .map((environmentApplication) => {
          const { application, servicesCount } = environmentApplication;

          return {
            id: application.id,
            name: application.name,
            route: {
              name: 'applications_show_route',
              params: { id: String(getIdFromGraphQLId(application.id)) },
            },
            release: this.latestVersionName(environmentApplication),
            servicesCount,
            lastDeployedAt: application.lastDeployedAt,
          };
        });
    },
  },
  methods: {
    // Services of one application can sit on different versions mid-rollout,
    // so the newest deployed version stands in for the application's release.
    latestVersionName(environmentApplication) {
      const versions = (environmentApplication.serviceEnvironmentHealths?.nodes ?? []).flatMap(
        (serviceHealth) => serviceHealth.deployedVersions?.nodes ?? [],
      );

      const latest = versions.reduce(
        (newest, version) =>
          !newest || new Date(version.createdAt) > new Date(newest.createdAt) ? version : newest,
        null,
      );

      return latest?.name ?? null;
    },
  },
  fields: FIELDS,
  EMPTY_PLACEHOLDER,
};
</script>

<template>
  <section>
    <h2 class="gl-mb-4 gl-mt-6 gl-text-lg" data-testid="deployed-applications-heading">
      {{ s__('ContinuousDeployment|Deployed applications') }}
    </h2>

    <p v-if="!applicationRows.length" class="gl-text-subtle" data-testid="no-applications">
      {{ s__('ContinuousDeployment|No applications are deployed to this environment.') }}
    </p>

    <gl-table-lite
      v-else
      :items="applicationRows"
      :fields="$options.fields"
      stacked="sm"
      data-testid="deployed-applications-table"
    >
      <template #cell(name)="{ item }">
        <router-link :to="item.route" data-testid="application-link">
          {{ item.name }}
        </router-link>
      </template>
      <template #cell(release)="{ item }">
        <span v-if="item.release" class="gl-font-monospace" data-testid="release-version">
          {{ item.release }}
        </span>
        <span v-else class="gl-text-subtle">{{ $options.EMPTY_PLACEHOLDER }}</span>
      </template>
      <template #cell(lastDeployedAt)="{ item }">
        <time-ago v-if="item.lastDeployedAt" :time="item.lastDeployedAt" />
        <span v-else class="gl-text-subtle">{{ $options.EMPTY_PLACEHOLDER }}</span>
      </template>
    </gl-table-lite>
  </section>
</template>
