<script>
import {
  GlDisclosureDropdown,
  GlDisclosureDropdownGroup,
  GlDisclosureDropdownItem,
  GlTooltipDirective,
  GlToastMixin,
} from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import dashboardsListItemActionsMixin from '~/vue_shared/components/dashboards_list/dashboards_list_item_actions_mixin';
import DashboardDeleteModal from './dashboard_delete_modal.vue';

export default {
  name: 'DashboardsListItemActionsEE',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownGroup,
    GlDisclosureDropdownItem,
    DashboardDeleteModal,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [dashboardsListItemActionsMixin, GlToastMixin],
  props: {
    actionLabel: {
      type: String,
      required: true,
    },
    id: {
      type: String,
      required: false,
      default: '',
    },
    name: {
      type: String,
      required: false,
      default: '',
    },
    system: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  methods: {
    handleDeleteAction() {
      this.$refs.deleteModal.show();
    },
    handleDeleteSuccess() {
      this.$refs.deleteModal.hide();
      // Deleting is permanent and the card disappears, so confirm it happened,
      // matching the Copy link toast in the same menu.
      this.$toast.show(sprintf(s__('AnalyticsDashboards|%{name} deleted'), { name: this.name }));
    },
  },
  deleteDashboardItem: { text: s__('AnalyticsDashboards|Delete dashboard') },
};
</script>

<template>
  <div>
    <dashboard-delete-modal
      v-if="!system"
      ref="deleteModal"
      :dashboard-id="id"
      :dashboard-name="name"
      @delete="handleDeleteSuccess"
    />

    <gl-disclosure-dropdown
      v-gl-tooltip.hover
      icon="ellipsis_v"
      category="tertiary"
      :title="__('More actions')"
      no-caret
      placement="bottom-end"
      :toggle-text="actionLabel"
      text-sr-only
    >
      <gl-disclosure-dropdown-item
        :item="openDashboardItem"
        icon="dashboard"
        data-testid="dashboard-open-action"
      />
      <gl-disclosure-dropdown-item
        :item="$options.copyLinkItem"
        icon="link"
        data-testid="dashboard-copy-link-action"
        :data-clipboard-text="absoluteDashboardUrl"
        @action="handleCopyLinkAction"
      />
      <gl-disclosure-dropdown-group v-if="!system" bordered>
        <gl-disclosure-dropdown-item
          :item="$options.deleteDashboardItem"
          icon="remove"
          variant="danger"
          data-testid="dashboard-delete-action"
          @action="handleDeleteAction"
        />
      </gl-disclosure-dropdown-group>
    </gl-disclosure-dropdown>
  </div>
</template>
