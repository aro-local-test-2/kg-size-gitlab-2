<script>
import { defineComponent } from 'vue';
import { GlAvatar, GlButton, GlLink, GlLoadingIcon } from '@gitlab/ui';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import excludedNamespacesQuery from '../graphql/queries/excluded_namespaces.query.graphql';
import excludedNamespaceDestroyMutation from '../graphql/mutations/excluded_namespace_destroy.mutation.graphql';
import ExcludeGroupModal from './exclude_group_modal.vue';

export default defineComponent({
  name: 'ExcludedGroupsCard',
  compatConfig: { MODE: 3 },
  components: {
    CrudComponent,
    ExcludeGroupModal,
    GlAvatar,
    GlButton,
    GlLink,
    GlLoadingIcon,
  },
  apollo: {
    excludedGroupsConnection: {
      query: excludedNamespacesQuery,
      variables: { first: 100 },
      update(data) {
        const connection = data.knowledgeGraphExcludedNamespaces;

        return { nodes: connection?.nodes || [], pageInfo: connection?.pageInfo || {} };
      },
      error() {
        createAlert({ message: s__('Orbit|Failed to load excluded groups. Please try again.') });
      },
    },
  },
  data() {
    return {
      excludedGroupsConnection: { nodes: [], pageInfo: {} },
      loadingMore: false,
      modalVisible: false,
      removingPaths: {},
    };
  },
  computed: {
    loading() {
      return this.$apollo.queries.excludedGroupsConnection.loading;
    },
    excludedGroups() {
      return this.excludedGroupsConnection.nodes;
    },
    excludedPaths() {
      return this.excludedGroups.map((group) => group.fullPath);
    },
    hasNextPage() {
      return this.excludedGroupsConnection.pageInfo.hasNextPage;
    },
  },
  methods: {
    async refetch() {
      await this.$apollo.queries.excludedGroupsConnection.refetch();
    },
    async loadMore() {
      if (this.loadingMore || !this.hasNextPage) return;

      this.loadingMore = true;

      try {
        await this.$apollo.queries.excludedGroupsConnection.fetchMore({
          variables: { after: this.excludedGroupsConnection.pageInfo.endCursor },
          updateQuery(previousResult, { fetchMoreResult }) {
            return {
              knowledgeGraphExcludedNamespaces: {
                ...fetchMoreResult.knowledgeGraphExcludedNamespaces,
                nodes: [
                  ...previousResult.knowledgeGraphExcludedNamespaces.nodes,
                  ...fetchMoreResult.knowledgeGraphExcludedNamespaces.nodes,
                ],
              },
            };
          },
        });
      } catch (error) {
        Sentry.captureException(error);
        createAlert({ message: s__('Orbit|Failed to load excluded groups. Please try again.') });
      } finally {
        this.loadingMore = false;
      }
    },
    async remove(group) {
      this.removingPaths = { ...this.removingPaths, [group.fullPath]: true };

      try {
        const { data } = await this.$apollo.mutate({
          mutation: excludedNamespaceDestroyMutation,
          variables: { input: { groupPath: group.fullPath } },
        });
        const result = data.knowledgeGraphExcludedNamespaceDestroy;
        if (result.errors?.length) throw new Error(result.errors.join(', '));

        await this.refetch();
      } catch (error) {
        Sentry.captureException(error);
        createAlert({
          message: s__('Orbit|Failed to remove the group exclusion. Please try again.'),
        });
      } finally {
        const { [group.fullPath]: _, ...remaining } = this.removingPaths;
        this.removingPaths = remaining;
      }
    },
  },
});
</script>

<template>
  <crud-component data-testid="excluded-groups-card">
    <template #title>{{ s__('Orbit|Excluded groups') }}</template>
    <template #actions>
      <gl-button size="small" variant="confirm" @click="modalVisible = true">
        {{ s__('Orbit|Exclude group') }}
      </gl-button>
    </template>

    <gl-loading-icon v-if="loading" size="lg" />
    <template v-else-if="excludedGroups.length">
      <div
        v-for="group in excludedGroups"
        :key="group.fullPath"
        class="gl-border-b gl-flex gl-items-center gl-gap-3 gl-border-default gl-py-4 first:gl-pt-0 last:gl-border-b-0 last:gl-pb-0"
      >
        <gl-avatar :src="group.avatarUrl" :entity-name="group.name" :size="32" shape="rect" />
        <gl-link :href="group.webPath" class="gl-flex-1 gl-text-default">{{ group.name }}</gl-link>
        <gl-button
          size="small"
          variant="danger"
          category="secondary"
          :loading="Boolean(removingPaths[group.fullPath])"
          @click="remove(group)"
        >
          {{ s__('Orbit|Remove') }}
        </gl-button>
      </div>
      <gl-button
        v-if="hasNextPage"
        class="gl-mt-4"
        :loading="loadingMore"
        data-testid="load-more-excluded-groups"
        @click="loadMore"
      >
        {{ s__('Orbit|Load more') }}
      </gl-button>
    </template>
    <p v-else class="gl-mb-0 gl-text-subtle" data-testid="excluded-groups-empty-state">
      {{
        s__(
          'Orbit|No groups are excluded. Excluded top-level groups are skipped by automatic indexing.',
        )
      }}
    </p>

    <exclude-group-modal
      :visible="modalVisible"
      :excluded-paths="excludedPaths"
      @change="modalVisible = $event"
      @excluded="refetch"
    />
  </crud-component>
</template>
