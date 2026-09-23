<script>
import { GlBadge, GlTable } from '@gitlab/ui';
import {
  REPOSITORY_KIND_LABELS,
  UPSTREAM_REPOSITORIES_ORDER_HELP,
  UPSTREAM_REPOSITORIES_TABLE_FIELDS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import UpstreamRepositoryActions from './upstream_repository_actions.vue';

export default {
  name: 'ArtifactRegistryUpstreamRepositoriesTable',
  components: {
    GlBadge,
    GlTable,
    HelpPopover,
    UpstreamRepositoryActions,
  },
  props: {
    upstreamRepositories: {
      type: Array,
      required: true,
    },
  },
  methods: {
    // A kind added to the upstream enum passes the server's contract check, so it arrives here
    // with no entry in the label map. Rendering it raw beats rendering an empty badge.
    kindLabel(kind) {
      return REPOSITORY_KIND_LABELS[kind] || kind;
    },
  },
  fields: UPSTREAM_REPOSITORIES_TABLE_FIELDS,
  orderHelp: { content: UPSTREAM_REPOSITORIES_ORDER_HELP },
};
</script>

<template>
  <gl-table :fields="$options.fields" :items="upstreamRepositories" show-empty>
    <!-- A placeholder, not the empty state: that ships with the setup entry in
         https://gitlab.com/gitlab-org/gitlab/-/issues/628667 -->
    <template #empty>
      <p class="gl-mb-0 gl-py-2 gl-text-center gl-text-subtle">
        {{ s__('ArtifactRegistry|There are no upstream repositories yet') }}
      </p>
    </template>

    <template #head(position)="{ label }">
      <span class="gl-flex gl-w-full gl-items-center gl-justify-center gl-gap-2">
        {{ label }}
        <help-popover
          :options="$options.orderHelp"
          icon="information-o"
          data-testid="upstream-order-help"
        />
      </span>
    </template>

    <template #cell(position)="{ item }">
      <gl-badge data-testid="upstream-position">{{ item.position }}</gl-badge>
    </template>

    <template #cell(name)="{ item }">
      <span class="gl-font-semibold gl-text-default gl-wrap-anywhere" data-testid="upstream-name">{{
        item.upstreamRepository.name
      }}</span>
    </template>

    <template #cell(kind)="{ item }">
      <gl-badge data-testid="upstream-kind">{{ kindLabel(item.upstreamRepository.kind) }}</gl-badge>
    </template>

    <template #cell(actions)="{ item }">
      <upstream-repository-actions :upstream-repository="item.upstreamRepository" />
    </template>
  </gl-table>
</template>
