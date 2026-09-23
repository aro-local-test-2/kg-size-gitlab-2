<script>
import { GlModal } from '@gitlab/ui';
import { s__, __, n__, sprintf } from '~/locale';

export default {
  name: 'DeleteScanProfileConfirmationModal',
  components: {
    GlModal,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
      default: false,
    },
    profileName: {
      type: String,
      required: true,
    },
    projectCount: {
      type: Number,
      required: false,
      default: 0,
    },
  },
  emits: ['confirm', 'cancel'],
  computed: {
    modalTitle() {
      return sprintf(s__('ScanProfiles|Delete %{profileName}'), {
        profileName: this.profileName,
      });
    },
    confirmationMessage() {
      return sprintf(
        s__(
          'ScanProfiles|You are about to delete “%{profileName}”. Are you sure you want to proceed?',
        ),
        { profileName: this.profileName },
      );
    },
    hasAttachedProjects() {
      return this.projectCount > 0;
    },
    projectCountMessage() {
      return n__(
        '%d project currently uses this profile and will be left without one.',
        '%d projects currently use this profile and will be left without one.',
        this.projectCount,
      );
    },
    actionPrimaryProps() {
      return {
        text: s__('ScanProfiles|Delete profile'),
        attributes: {
          variant: 'danger',
        },
      };
    },
    actionCancelProps() {
      return {
        text: __('Cancel'),
      };
    },
  },
  methods: {
    handleConfirm() {
      this.$emit('confirm');
    },
    handleCancel() {
      this.$emit('cancel');
    },
  },
};
</script>

<template>
  <gl-modal
    :visible="visible"
    :title="modalTitle"
    :action-primary="actionPrimaryProps"
    :action-cancel="actionCancelProps"
    modal-id="delete-scan-profile-confirmation-modal"
    size="sm"
    @primary="handleConfirm"
    @hidden="handleCancel"
  >
    <p>{{ confirmationMessage }}</p>
    <p
      v-if="hasAttachedProjects"
      class="gl-text-subtle"
      data-testid="scan-profile-delete-project-count"
    >
      {{ projectCountMessage }}
    </p>
  </gl-modal>
</template>
