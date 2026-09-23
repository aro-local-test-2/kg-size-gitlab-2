<script>
import { GlAlert, GlFormGroup, GlModal } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { joinPaths, visitUrl } from '~/lib/utils/url_utility';
import { getRegistryItem } from '../item_type_registry';
import FormProjectDropdown from './form_project_dropdown.vue';

export default {
  name: 'ProjectRedirectModal',
  components: {
    FormProjectDropdown,
    GlAlert,
    GlFormGroup,
    GlModal,
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    modalId: {
      type: String,
      required: false,
      default: 'project-redirect-modal',
    },
  },
  emits: ['hide'],
  data() {
    return {
      isOpen: this.open,
      selectedProject: null,
      isDirty: false,
      error: null,
    };
  },
  computed: {
    itemRegistry() {
      return getRegistryItem(this.item.itemType);
    },
    modal() {
      return {
        actionPrimary: {
          text: __('Continue'),
          attributes: {
            variant: 'confirm',
          },
        },
        actionCancel: {
          text: __('Cancel'),
        },
      };
    },
    projectId() {
      return this.selectedProject?.id || null;
    },
    isProjectValid() {
      if (!this.isDirty) return true;
      return Boolean(this.selectedProject);
    },
    projectInvalidFeedback() {
      return s__('AICatalog|Project is required.');
    },
  },
  methods: {
    onError(error) {
      this.error = error;
    },
    continueToProject() {
      this.isDirty = true;
      if (!this.isProjectValid) {
        return;
      }
      const automatePath = this.itemRegistry.projectPath;
      const itemId = getIdFromGraphQLId(this.item.id);

      visitUrl(
        joinPaths(this.selectedProject.webPath, automatePath, itemId.toString(), 'duplicate'),
      );

      this.isOpen = false;
    },
    resetForm() {
      this.selectedProject = null;
      this.isDirty = false;
      this.error = null;
    },
    onHidden() {
      this.resetForm();
      this.$emit('hide');
    },
  },
};
</script>

<template>
  <gl-modal
    v-model="isOpen"
    :modal-id="modalId"
    :title="s__('AICatalog|Choose a project')"
    :action-primary="modal.actionPrimary"
    :action-cancel="modal.actionCancel"
    @primary.prevent="continueToProject"
    @hidden="onHidden"
  >
    <gl-alert v-if="error" variant="danger" class="gl-mb-5" @dismiss="error = null">
      {{ error }}
    </gl-alert>
    <gl-form-group
      :label="__('Project')"
      label-for="project-id"
      :state="isProjectValid"
      :invalid-feedback="projectInvalidFeedback"
    >
      <form-project-dropdown
        id="project-id"
        :value="projectId"
        :is-valid="isProjectValid"
        @select="selectedProject = $event"
        @error="onError"
      />
    </gl-form-group>
  </gl-modal>
</template>
