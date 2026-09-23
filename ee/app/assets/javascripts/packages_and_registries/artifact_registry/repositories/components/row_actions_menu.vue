<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import {
  REPOSITORY_EDIT_ROUTE_NAME,
  REPOSITORY_PERMISSION_UPDATE_REPOSITORY,
} from '../../constants';
import { permissionAllows } from '../../graphql/utils/permissions';

export default {
  name: 'ArtifactRegistryRepositoryRowActionsMenu',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
  },
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
  computed: {
    canEdit() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_UPDATE_REPOSITORY);
    },
    toggleText() {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), {
        name: this.repository.name,
      });
    },
    editItem() {
      return {
        text: s__('ArtifactRegistry|Edit repository'),
        to: { name: REPOSITORY_EDIT_ROUTE_NAME, params: { id: this.repository.name } },
      };
    },
  },
};
</script>

<template>
  <gl-disclosure-dropdown
    v-if="canEdit"
    icon="ellipsis_v"
    :toggle-text="toggleText"
    text-sr-only
    category="tertiary"
    no-caret
    placement="bottom-end"
    data-testid="repository-actions"
  >
    <gl-disclosure-dropdown-item :item="editItem" data-testid="edit-repository" />
  </gl-disclosure-dropdown>
</template>
