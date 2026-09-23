<script>
import { GlBadge, GlButton, GlTooltipDirective } from '@gitlab/ui';
import { s__, __ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import ScanTriggersDetail from './scan_triggers_detail.vue';
import { scanTypeName, scanTypeHelpLink, resolveTriggers, managedByLabel } from './utils';

const i18n = {
  generalDetails: s__('ScanProfiles|General details'),
  scanTriggers: s__('ScanProfiles|Scan triggers'),
  scanTriggersInfo: s__('ScanProfiles|When and how scans are run.'),
  managedBy: s__('ScanProfiles|Managed by'),
  name: __('Name'),
  description: __('Description'),
  analyzerType: __('Analyzer type'),
  delete: __('Delete'),
  deleteManagedDisallowed: s__("ScanProfiles|GitLab-managed profiles can't be deleted."),
};

export default {
  name: 'ScanProfileDetail',
  components: {
    CrudComponent,
    GlBadge,
    GlButton,
    ScanTriggersDetail,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    profile: {
      type: Object,
      required: true,
    },
  },
  emits: ['delete'],
  computed: {
    generalDetails() {
      return [
        { label: i18n.name, value: this.profile.name },
        { label: i18n.description, value: this.profile.description },
        { label: i18n.analyzerType, value: scanTypeName(this.profile.scanType) },
        { label: i18n.managedBy, value: managedByLabel(this.profile), isBadge: true },
      ];
    },
    profileHelpLink() {
      return scanTypeHelpLink(this.profile.scanType);
    },
    triggers() {
      return resolveTriggers(this.profile.triggers);
    },
    canDelete() {
      return !this.profile.gitlabRecommended;
    },
    deleteButtonTitle() {
      return this.canDelete ? i18n.delete : i18n.deleteManagedDisallowed;
    },
  },
  i18n,
};
</script>

<template>
  <div data-testid="scan-profile-detail">
    <div class="gl-flex gl-items-start gl-justify-between gl-gap-3">
      <h3 class="gl-heading-3">{{ profile.name }}</h3>
      <div class="gl-flex gl-shrink-0 gl-items-center gl-gap-2">
        <gl-button
          v-gl-tooltip
          icon="remove"
          category="secondary"
          :disabled="!canDelete"
          :title="deleteButtonTitle"
          :aria-label="$options.i18n.delete"
          data-testid="scan-profile-delete-button"
          @click="$emit('delete')"
        />
      </div>
    </div>

    <crud-component class="gl-mb-5" :title="$options.i18n.generalDetails">
      <dl class="gl-m-0 gl-flex gl-flex-col gl-gap-3">
        <div
          v-for="{ label, value, isBadge } in generalDetails"
          :key="label"
          class="gl-flex gl-gap-3"
        >
          <dt class="gl-w-1/3 gl-font-normal gl-text-subtle">{{ label }}</dt>
          <dd class="gl-m-0 gl-flex-1">
            <gl-badge v-if="isBadge">{{ value }}</gl-badge>
            <template v-else>{{ value }}</template>
          </dd>
        </div>
      </dl>
    </crud-component>

    <h4 class="gl-heading-4 gl-mb-1">{{ $options.i18n.scanTriggers }}</h4>
    <p class="gl-mb-3 gl-text-subtle">{{ $options.i18n.scanTriggersInfo }}</p>
    <scan-triggers-detail :profile-help-link="profileHelpLink" :triggers="triggers" />
  </div>
</template>
