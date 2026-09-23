<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem, GlToastMixin } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import {
  REPOSITORY_EDIT_ROUTE_NAME,
  REPOSITORY_KIND_REMOTE,
} from 'ee/packages_and_registries/artifact_registry/constants';
import clearRepositoryCacheMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/clear_repository_cache.mutation.graphql';
import { evictClearedRepositoryDetails } from 'ee/packages_and_registries/artifact_registry/graphql/utils/cache_update';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';

export default {
  name: 'ArtifactRegistryUpstreamRepositoryActions',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
  },
  mixins: [GlToastMixin],
  props: {
    upstreamRepository: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      clearing: false,
    };
  },
  computed: {
    toggleText() {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), {
        name: this.upstreamRepository.name,
      });
    },
    isRemote() {
      return this.upstreamRepository.kind === REPOSITORY_KIND_REMOTE;
    },
    editItem() {
      return {
        text: s__('ArtifactRegistry|Edit repository'),
        to: { name: REPOSITORY_EDIT_ROUTE_NAME, params: { id: this.upstreamRepository.name } },
      };
    },
    clearCacheItem() {
      return {
        text: s__('ArtifactRegistry|Clear cache'),
        action: () => this.clearCache(),
      };
    },
  },
  methods: {
    async clearCache() {
      if (this.clearing) return;

      this.clearing = true;
      const { name } = this.upstreamRepository;

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: clearRepositoryCacheMutation,
          input: { name },
          update: evictClearedRepositoryDetails(name),
        });

        if (!accepted) return;

        this.$toast.show(
          sprintf(s__('ArtifactRegistry|Cache clear successfully scheduled for %{name}.'), {
            name,
          }),
        );
      } finally {
        this.clearing = false;
      }
    },
  },
};
</script>

<template>
  <gl-disclosure-dropdown
    icon="ellipsis_v"
    :toggle-text="toggleText"
    :loading="clearing"
    text-sr-only
    category="tertiary"
    no-caret
    placement="bottom-end"
    data-testid="upstream-actions"
  >
    <gl-disclosure-dropdown-item
      v-if="isRemote"
      :item="clearCacheItem"
      data-testid="clear-upstream-cache"
    />

    <gl-disclosure-dropdown-item :item="editItem" data-testid="edit-upstream-repository" />
  </gl-disclosure-dropdown>
</template>
