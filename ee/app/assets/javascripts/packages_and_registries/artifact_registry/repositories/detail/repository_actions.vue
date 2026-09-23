<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem, GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { copyToClipboard } from '~/lib/utils/copy_to_clipboard';
import { __, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
  REPOSITORY_PERMISSION_DELETE_REPOSITORY,
} from 'ee/packages_and_registries/artifact_registry/constants';
import clearRepositoryCacheMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/clear_repository_cache.mutation.graphql';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.query.graphql';
import { permissionAllows } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';
import {
  buildRepositoryClientUrl,
  isContainerFormat,
} from 'ee/packages_and_registries/artifact_registry/utils';
import DeleteRepositoryModal from '../components/delete_repository_modal.vue';

export default {
  name: 'ArtifactRegistryRepositoryActions',
  i18n: {
    clearCache: s__('ArtifactRegistry|Clear cache'),
    cacheCleared: s__('ArtifactRegistry|Cache successfully cleared.'),
    genericError: __('Something went wrong. Please try again.'),
  },
  components: {
    DeleteRepositoryModal,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
  },
  mixins: [GlToastMixin],
  inject: ['slug', 'clientBaseUrl'],
  props: {
    repository: {
      type: Object,
      required: true,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      showDeleteModal: false,
    };
  },
  computed: {
    // The toggle renders as an icon, so its accessible name is all a screen reader
    // gets: it names the repository the actions belong to rather than saying only
    // "More actions".
    toggleText() {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), {
        name: this.repository.name,
      });
    },
    clientUrl() {
      return buildRepositoryClientUrl({
        clientBaseUrl: this.clientBaseUrl,
        slug: this.slug,
        format: this.repository.format,
        name: this.repository.name,
      });
    },
    isRemote() {
      return this.repository.kind === REPOSITORY_KIND_REMOTE;
    },
    canDelete() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_DELETE_REPOSITORY);
    },
    canClearCache() {
      return (
        this.isRemote && permissionAllows(this.permissions, REPOSITORY_PERMISSION_DELETE_ARTIFACT)
      );
    },
    hasItems() {
      return Boolean(this.clientUrl) || this.canClearCache || this.canDelete;
    },
    artifactConnectionQuery() {
      return isContainerFormat(this.repository.format)
        ? getRepositoryImagesQuery
        : getRepositoryPackagesQuery;
    },
    copyItem() {
      return {
        text: s__('ArtifactRegistry|Copy repository URL'),
        action: () => this.copyClientUrl(),
      };
    },
    clearCacheItem() {
      return {
        text: this.$options.i18n.clearCache,
        action: () => this.clearCache(),
      };
    },
    deleteItem() {
      return {
        text: s__('ArtifactRegistry|Delete repository'),
        variant: 'danger',
        action: () => {
          this.showDeleteModal = true;
        },
      };
    },
  },
  methods: {
    // A menu item shows nothing once it is chosen, so the toast is what reports the
    // copy, and being a live region it is also what announces it. A failed write is
    // reported rather than swallowed: the user has no other signal that the clipboard
    // still holds what it held before.
    async copyClientUrl() {
      try {
        await copyToClipboard(this.clientUrl);
        this.$toast.show(s__('ArtifactRegistry|Repository URL copied to clipboard.'));
      } catch (error) {
        Sentry.captureException(error);
      }
    },
    async clearCache() {
      try {
        const { data } = await this.$apollo.mutate({
          mutation: clearRepositoryCacheMutation,
          variables: { input: { name: this.repository.name } },
          refetchQueries: [getRepositoryDetailQuery, this.artifactConnectionQuery],
        });

        const { errors } = data.clearRepositoryCache;

        if (errors.length) {
          createAlert({ message: errors.join(' ') });
          return;
        }

        this.$toast.show(this.$options.i18n.cacheCleared);
      } catch (error) {
        createAlert({ message: this.$options.i18n.genericError, error, captureError: true });
      }
    },
  },
};
</script>

<template>
  <div>
    <gl-disclosure-dropdown
      v-if="hasItems"
      icon="ellipsis_v"
      :toggle-text="toggleText"
      text-sr-only
      category="tertiary"
      no-caret
      placement="bottom-end"
    >
      <!-- Left out rather than shown broken when the instance configures no Artifact
           Registry: there is no URL to hand over. -->
      <gl-disclosure-dropdown-item
        v-if="clientUrl"
        :item="copyItem"
        data-testid="copy-repository-url"
      />

      <gl-disclosure-dropdown-item
        v-if="canClearCache"
        :item="clearCacheItem"
        data-testid="clear-repository-cache"
      />

      <!-- The destructive action is marked out by its variant alone, with no divider
           above it: the design groups every item in one list. -->
      <gl-disclosure-dropdown-item
        v-if="canDelete"
        :item="deleteItem"
        data-testid="delete-repository"
      />
    </gl-disclosure-dropdown>

    <delete-repository-modal v-model="showDeleteModal" :repository="repository" />
  </div>
</template>
