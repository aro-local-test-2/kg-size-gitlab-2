<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem, GlTable, GlToastMixin } from '@gitlab/ui';
import {
  ARTIFACTS_TABLE_FIELDS,
  ARTIFACT_VERSIONS_ROUTE_NAME,
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
} from 'ee/packages_and_registries/artifact_registry/constants';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.query.graphql';
import deleteArtifactMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_artifact.mutation.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import { permissionAllows } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';
import {
  artifactActionsToggleText,
  artifactDeleteCopy,
  artifactDeleteLabel,
  artifactDeletionScheduledMessage,
  artifactDisplayName,
  isContainerFormat,
} from 'ee/packages_and_registries/artifact_registry/utils';
import { formatNumber, s__ } from '~/locale';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import DeleteConfirmationModal from '../components/delete_confirmation_modal.vue';

export default {
  name: 'ArtifactRegistryArtifactsTable',
  components: {
    ClipboardButton,
    DeleteConfirmationModal,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlTable,
    TimeAgoTooltip,
  },
  mixins: [GlToastMixin],
  props: {
    artifacts: {
      type: Array,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
    kind: {
      type: String,
      required: true,
    },
    name: {
      type: String,
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
      artifactToDelete: null,
      pendingDeletionIds: [],
    };
  },
  computed: {
    fields() {
      return ARTIFACTS_TABLE_FIELDS[this.kind]?.[this.format] ?? [];
    },
    isNavigable() {
      return this.kind === REPOSITORY_KIND_HOSTED;
    },
    isRemote() {
      return this.kind === REPOSITORY_KIND_REMOTE;
    },
    isContainer() {
      return isContainerFormat(this.format);
    },
    canDelete() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_DELETE_ARTIFACT);
    },
    copyNameTitle() {
      const { copyImageName, copyPackageName } = this.$options.i18n;

      return this.isContainer ? copyImageName : copyPackageName;
    },
    emptyText() {
      const { emptyImages, emptyPackages } = this.$options.i18n;

      return this.isContainer ? emptyImages : emptyPackages;
    },
    artifactConnectionQuery() {
      return this.isContainer ? getRepositoryImagesQuery : getRepositoryPackagesQuery;
    },
    scheduledMessage() {
      return artifactDeletionScheduledMessage(this.format);
    },
    deleteModalCopy() {
      return artifactDeleteCopy(this.artifactToDelete, this.format);
    },
  },
  methods: {
    artifactName(artifact) {
      return artifactDisplayName(artifact, this.format);
    },
    versionsRoute(artifact) {
      return {
        name: ARTIFACT_VERSIONS_ROUTE_NAME,
        params: { id: this.name, artifactId: artifact.id },
      };
    },
    versions(versionsCount) {
      return formatNumber(versionsCount ?? 0);
    },
    toggleText(artifact) {
      return artifactActionsToggleText(artifact, this.format);
    },
    isPendingDeletion(artifact) {
      return this.pendingDeletionIds.includes(artifact.id);
    },
    deleteCacheEntryItem(artifact) {
      return {
        text: this.$options.i18n.deleteCacheEntry,
        variant: 'danger',
        action: () => this.deleteArtifact(artifact, this.$options.i18n.cacheEntryScheduled),
      };
    },
    deleteItem(artifact) {
      return {
        text: artifactDeleteLabel(this.format),
        variant: 'danger',
        action: () => {
          this.artifactToDelete = artifact;
        },
      };
    },
    async deleteArtifact(artifact, successMessage) {
      if (this.isPendingDeletion(artifact)) return;

      this.pendingDeletionIds.push(artifact.id);

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: deleteArtifactMutation,
          input: { name: this.name, id: artifact.id },
          refetchQueries: [getRepositoryDetailQuery, this.artifactConnectionQuery],
          awaitRefetchQueries: true,
        });

        if (accepted) this.$toast.show(successMessage);
      } finally {
        this.pendingDeletionIds = this.pendingDeletionIds.filter((id) => id !== artifact.id);
      }
    },
  },
  i18n: {
    emptyImages: s__('ArtifactRegistry|No images have been cached yet.'),
    emptyPackages: s__('ArtifactRegistry|No packages have been cached yet.'),
    deleteCacheEntry: s__('ArtifactRegistry|Delete cache entry'),
    copyImageName: s__('ArtifactRegistry|Copy image name'),
    copyPackageName: s__('ArtifactRegistry|Copy package name'),
    cacheEntryScheduled: s__('ArtifactRegistry|Cache entry successfully scheduled for deletion.'),
  },
};
</script>

<template>
  <div>
    <gl-table :fields="fields" :items="artifacts" :show-empty="isRemote" stacked="md">
      <template #empty>
        <p class="gl-mb-0 gl-py-2 gl-text-center gl-text-subtle">{{ emptyText }}</p>
      </template>

      <template #cell(name)="{ item }">
        <router-link
          v-if="isNavigable"
          :to="versionsRoute(item)"
          class="gl-font-semibold gl-text-default gl-wrap-anywhere"
          data-testid="artifact-name"
          >{{ artifactName(item) }}</router-link
        >
        <span
          v-else
          class="gl-font-semibold gl-text-default gl-wrap-anywhere"
          data-testid="artifact-name"
          >{{ artifactName(item) }}</span
        >
      </template>

      <template #cell(versionsCount)="{ item }">
        <span data-testid="artifact-versions">{{ versions(item.versionsCount) }}</span>
      </template>

      <template #cell(lastDownloadedAt)="{ item }">
        <time-ago-tooltip v-if="item.lastDownloadedAt" :time="item.lastDownloadedAt" />
      </template>

      <template #cell(actions)="{ item }">
        <clipboard-button :text="artifactName(item)" :title="copyNameTitle" category="tertiary" />
        <gl-disclosure-dropdown
          v-if="canDelete"
          icon="ellipsis_v"
          :toggle-text="toggleText(item)"
          :loading="isPendingDeletion(item)"
          text-sr-only
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="artifact-actions"
        >
          <gl-disclosure-dropdown-item
            v-if="isRemote"
            :item="deleteCacheEntryItem(item)"
            data-testid="delete-cache-entry"
          />
          <gl-disclosure-dropdown-item
            v-else
            :item="deleteItem(item)"
            data-testid="delete-artifact"
          />
        </gl-disclosure-dropdown>
      </template>
    </gl-table>

    <delete-confirmation-modal
      v-if="!isRemote"
      v-model="artifactToDelete"
      v-bind="deleteModalCopy"
      @confirm="deleteArtifact($event, scheduledMessage)"
    />
  </div>
</template>
