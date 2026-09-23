<script>
import { GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { __, s__ } from '~/locale';
import ConfirmDangerModal from '~/vue_shared/components/confirm_danger/confirm_danger_modal.vue';
import { REPOSITORIES_LIST_ROUTE_NAME } from '../../constants';
import deleteRepositoryMutation from '../../graphql/mutations/delete_repository.mutation.graphql';
import { evictDeletedRepository } from '../../graphql/utils/cache_update';

const MODAL_ID = 'artifact-registry-delete-repository-modal';

export default {
  name: 'ArtifactRegistryDeleteRepositoryModal',
  components: {
    ConfirmDangerModal,
  },
  mixins: [GlToastMixin],
  // `ConfirmDangerModal` reads its button and consequence copy by injection, not props.
  provide: {
    confirmButtonText: s__('ArtifactRegistry|Delete repository'),
    additionalInformation: s__(
      'ArtifactRegistry|This action permanently deletes the repository and all of its artifacts.',
    ),
  },
  inject: ['organizationGid'],
  model: {
    prop: 'visible',
    event: 'change',
  },
  props: {
    repository: {
      type: Object,
      required: true,
    },
    visible: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  data() {
    return {
      deleting: false,
    };
  },
  methods: {
    async confirm() {
      this.deleting = true;

      try {
        const errors = await this.deleteRepository();

        if (errors.length) {
          createAlert({ message: errors.join(' ') });
          return;
        }

        this.$toast.show(s__('ArtifactRegistry|Repository was successfully deleted.'));
        this.$router.push({ name: REPOSITORIES_LIST_ROUTE_NAME });
      } catch (error) {
        createAlert({
          message: __('Something went wrong. Please try again.'),
          error,
          captureError: true,
        });
      } finally {
        // Also closes the modal: `ConfirmDangerModal` hides itself when `confirmLoading` flips off.
        this.deleting = false;
      }
    },
    async deleteRepository() {
      const { name } = this.repository;

      const { data } = await this.$apollo.mutate({
        mutation: deleteRepositoryMutation,
        variables: { input: { name } },
        update: evictDeletedRepository(this.organizationGid, name),
      });

      return data.deleteRepository.errors;
    },
  },
  modalId: MODAL_ID,
};
</script>

<template>
  <confirm-danger-modal
    :visible="visible"
    :modal-id="$options.modalId"
    :modal-title="s__('ArtifactRegistry|Delete repository?')"
    :phrase="repository.name"
    :phrase-label="s__('ArtifactRegistry|Type the repository name below to confirm: %{phrase}')"
    :confirm-loading="deleting"
    @confirm="confirm"
    @change="$emit('change', $event)"
  />
</template>
