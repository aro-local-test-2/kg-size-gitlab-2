<script>
import { GlAlert, GlKeysetPagination, GlTable } from '@gitlab/ui';
import { groupBy, mapValues, sortBy } from 'lodash-es';
import { DEFAULT_PER_PAGE } from '~/api';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { s__ } from '~/locale';
import { TIERS } from 'ee/cd/constants';
import cdApplicationServiceVersionsQuery from 'ee/cd/graphql/applications/releases/cd_application_service_versions.query.graphql';
import VersionsDropdown from './versions_dropdown.vue';

export default {
  name: 'ServicesSelector',
  components: {
    GlAlert,
    GlKeysetPagination,
    GlTable,
    VersionsDropdown,
  },
  props: {
    applicationId: {
      type: String,
      required: true,
    },
  },
  emits: ['change', 'changed-count'],
  data() {
    return {
      services: [],
      pageInfo: {},
      selections: {},
      initialVersionIds: {},
      hasError: false,
      createError: '',
      pagination: {
        first: DEFAULT_PER_PAGE,
        after: null,
        last: null,
        before: null,
      },
    };
  },
  apollo: {
    services: {
      query: cdApplicationServiceVersionsQuery,
      variables() {
        return { applicationId: this.applicationId, ...this.pagination };
      },
      update(data) {
        return (data.organization?.cdApplication?.services?.nodes ?? []).map((service) => {
          const environments = this.environmentsByVersionId(service);

          return {
            id: service.id,
            name: service.name,
            sources: (service.artifactSources?.nodes ?? []).map((source) => {
              const versions = this.sortVersionsByNewest(source.versions?.nodes ?? []);
              return {
                id: source.id,
                serviceId: service.id,
                sourceRef: source.sourceRef ?? '',
                versionItems: versions.map((version) => ({
                  value: version.id,
                  text: version.name,
                  verified: version.verified,
                  environments: environments[version.id] ?? [],
                })),
              };
            }),
          };
        });
      },
      result({ data }) {
        const application = data?.organization?.cdApplication;
        this.pageInfo = application?.services?.pageInfo ?? {};
        const presetVersions = application?.versionSets?.nodes?.[0]?.versionSetEntries?.nodes ?? [];
        this.preselectVersions(presetVersions.map((entry) => entry.version?.id).filter(Boolean));
      },
      error() {
        this.hasError = true;
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.services.loading;
    },
    allSources() {
      return this.services.flatMap((service) => service.sources);
    },
    tableRows() {
      return this.services.flatMap((service) => {
        const serviceLabelId = this.labelId('service', service.id);
        if (service.sources.length > 1) {
          return [
            {
              key: service.id,
              type: 'header',
              serviceName: service.name,
              serviceLabelId,
              sources: service.sources,
            },
            ...service.sources.map((source) => ({
              key: source.id,
              type: 'source',
              serviceName: service.name,
              serviceLabelId,
              sourceLabelId: this.labelId('source', source.id),
              source,
            })),
          ];
        }
        const source = service.sources[0] ?? null;
        return [
          {
            key: service.id,
            type: 'single',
            serviceName: service.name,
            serviceLabelId,
            sourceLabelId: source ? this.labelId('source', source.id) : null,
            sources: service.sources,
            source,
          },
        ];
      });
    },
    selectedSources() {
      return Object.entries(this.selections).map(([sourceId, { serviceId, versionId }]) => ({
        serviceId,
        sourceId,
        versionId,
      }));
    },
    changedCount() {
      return Object.keys(this.initialVersionIds).filter((sourceId) =>
        this.isSourceChanged(sourceId),
      ).length;
    },
    showPagination() {
      return Boolean(this.pageInfo.hasNextPage || this.pageInfo.hasPreviousPage);
    },
  },
  watch: {
    selectedSources(selection) {
      this.$emit('change', selection);
    },
    changedCount(count) {
      this.$emit('changed-count', count);
    },
  },
  methods: {
    environmentsByVersionId(service) {
      const deployed = (service.serviceEnvironmentHealths?.nodes ?? [])
        .filter((node) => node.environment?.name)
        .flatMap((node) =>
          (node.deployedVersions?.nodes ?? []).map((version) => ({
            versionId: version.id,
            environment: node.environment.name,
            tier: node.environment.tier,
          })),
        );

      return mapValues(groupBy(deployed, 'versionId'), (entries) =>
        sortBy(entries, ({ tier }) => this.tierOrder(tier)).map(({ environment }) => environment),
      );
    },
    tierOrder(tier) {
      const index = TIERS.findIndex(({ key }) => key === tier);

      return index === -1 ? TIERS.length + 1 : TIERS.length - index;
    },
    sortVersionsByNewest(versions) {
      return [...versions].sort(
        (a, b) =>
          new Date(b.createdAt) - new Date(a.createdAt) ||
          getIdFromGraphQLId(b.id) - getIdFromGraphQLId(a.id),
      );
    },
    presetVersionId(source, presetVersionIds) {
      return (
        source.versionItems.find((item) => presetVersionIds.includes(item.value))?.value ?? null
      );
    },
    preselectVersions(presetVersionIds) {
      const selections = { ...this.selections };
      const initialVersionIds = { ...this.initialVersionIds };

      this.allSources.forEach((source) => {
        if (initialVersionIds[source.id] !== undefined) {
          return;
        }
        const presetId = this.presetVersionId(source, presetVersionIds);
        initialVersionIds[source.id] = presetId;
        if (presetId) {
          selections[source.id] = { serviceId: source.serviceId, versionId: presetId };
        }
      });

      this.selections = selections;
      this.initialVersionIds = initialVersionIds;
    },
    nextPage(endCursor) {
      this.pagination = { first: DEFAULT_PER_PAGE, after: endCursor, last: null, before: null };
    },
    prevPage(startCursor) {
      this.pagination = { first: null, after: null, last: DEFAULT_PER_PAGE, before: startCursor };
    },
    selectedVersionId(source) {
      return this.selections[source.id]?.versionId ?? null;
    },
    isSourceChanged(sourceId) {
      return (
        (this.selections[sourceId]?.versionId ?? null) !==
        (this.initialVersionIds[sourceId] ?? null)
      );
    },
    isRowChanged(item) {
      return item.sources?.some((source) => this.isSourceChanged(source.id)) ?? false;
    },
    labelId(prefix, gid) {
      return `cd-${prefix}-${getIdFromGraphQLId(gid)}`;
    },
    selectVersion(source, versionId) {
      this.createError = '';
      this.selections = {
        ...this.selections,
        [source.id]: { serviceId: source.serviceId, versionId },
      };
    },
  },
  fields: [
    {
      key: 'service',
      label: s__('ReleaseCreation|Service'),
      thClass: '!gl-text-subtle !gl-text-sm !gl-p-3 !gl-border-t-0',
      tdClass: '!gl-p-3',
    },
    {
      key: 'version',
      label: s__('ReleaseCreation|Version'),
      thClass: 'gl-w-2/5 !gl-text-subtle !gl-text-sm !gl-p-3 !gl-border-t-0',
      tdClass: '!gl-p-3 !gl-align-middle',
    },
  ],
};
</script>

<template>
  <div>
    <gl-alert v-if="hasError" variant="danger" class="gl-mb-3" @dismiss="hasError = false">
      {{ s__('ReleaseCreation|Failed to load services. Refresh the page to try again.') }}
    </gl-alert>
    <gl-alert
      v-if="createError"
      variant="danger"
      class="gl-mb-3"
      data-testid="create-error"
      @dismiss="createError = ''"
    >
      {{ createError }}
    </gl-alert>
    <gl-table
      :items="tableRows"
      :fields="$options.fields"
      :empty-text="s__('ReleaseCreation|No services to display.')"
      :busy="isLoading"
      primary-key="key"
      show-empty
      class="gl-text-subtle"
    >
      <template #cell(service)="{ item }">
        <p
          v-if="item.type !== 'source'"
          :id="item.serviceLabelId"
          class="gl-mb-2 gl-font-bold"
          :class="{ 'gl-text-subtle': !isRowChanged(item) }"
          data-testid="service-name"
        >
          {{ item.serviceName }}
        </p>
        <p
          v-if="item.source && item.source.sourceRef"
          :id="item.sourceLabelId"
          class="gl-mb-0 gl-text-subtle"
          :class="item.type === 'source' ? 'gl-pl-4 gl-font-monospace' : 'gl-text-sm'"
          data-testid="source-ref"
        >
          {{ item.source.sourceRef }}
        </p>
      </template>

      <template #cell(version)="{ item }">
        <template v-if="item.source">
          <versions-dropdown
            :artifact-source-id="item.source.id"
            :version-items="item.source.versionItems"
            :selected="selectedVersionId(item.source)"
            :changed="isSourceChanged(item.source.id)"
            :toggle-aria-labelled-by="`${item.serviceLabelId} ${item.sourceLabelId}`"
            @select="selectVersion(item.source, $event)"
            @error="createError = $event"
          />
          <p
            v-if="isSourceChanged(item.source.id)"
            class="gl-mb-0 gl-mt-2 gl-text-xs gl-font-bold gl-uppercase gl-tracking-wider gl-text-blue-500"
            data-testid="version-changed"
          >
            {{ s__('ReleaseCreation|Changed') }}
          </p>
        </template>
      </template>
    </gl-table>

    <div v-if="showPagination" class="gl-mt-3 gl-flex gl-justify-center">
      <gl-keyset-pagination
        v-bind="pageInfo"
        :disabled="isLoading"
        @next="nextPage"
        @prev="prevPage"
      />
    </div>
  </div>
</template>
