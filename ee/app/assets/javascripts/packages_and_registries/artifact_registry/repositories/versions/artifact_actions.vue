<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem, GlToastMixin } from '@gitlab/ui';
import {
  REPOSITORY_DETAIL_ROUTE_NAME,
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
} from 'ee/packages_and_registries/artifact_registry/constants';
import deleteArtifactMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_artifact.mutation.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import { permissionAllows } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';
import {
  artifactActionsToggleText,
  artifactDeleteCopy,
  artifactDeleteLabel,
  artifactDeletionScheduledMessage,
} from 'ee/packages_and_registries/artifact_registry/utils';
import DeleteConfirmationModal from '../components/delete_confirmation_modal.vue';

export default {
  name: 'ArtifactRegistryArtifactActions',
  components: {
    DeleteConfirmationModal,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
  },
  mixins: [GlToastMixin],
  props: {
    artifact: {
      type: Object,
      required: true,
    },
    format: {
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
      deleting: false,
    };
  },
  computed: {
    canDelete() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_DELETE_ARTIFACT);
    },
    toggleText() {
      return artifactActionsToggleText(this.artifact, this.format);
    },
    deleteModalCopy() {
      return artifactDeleteCopy(this.artifactToDelete, this.format);
    },
    deleteItem() {
      return {
        text: artifactDeleteLabel(this.format),
        variant: 'danger',
        action: () => {
          this.artifactToDelete = this.artifact;
        },
      };
    },
  },
  methods: {
    async deleteArtifact(artifact) {
      if (this.deleting) return;

      this.deleting = true;

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: deleteArtifactMutation,
          input: { name: this.name, id: artifact.id },
        });

        if (!accepted) return;

        this.$toast.show(artifactDeletionScheduledMessage(this.format));
        this.$router.push({ name: REPOSITORY_DETAIL_ROUTE_NAME, params: { id: this.name } });
      } finally {
        this.deleting = false;
      }
    },
  },
};
</script>

<template>
  <div>
    <gl-disclosure-dropdown
      v-if="canDelete"
      icon="ellipsis_v"
      :toggle-text="toggleText"
      :loading="deleting"
      text-sr-only
      category="tertiary"
      no-caret
      placement="bottom-end"
      data-testid="artifact-actions"
    >
      <gl-disclosure-dropdown-item :item="deleteItem" data-testid="delete-artifact" />
    </gl-disclosure-dropdown>

    <delete-confirmation-modal
      v-model="artifactToDelete"
      v-bind="deleteModalCopy"
      @confirm="deleteArtifact"
    />
  </div>
</template>
