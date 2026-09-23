<script>
import { GlDisclosureDropdownGroup, GlDisclosureDropdownItem, GlToggle } from '@gitlab/ui';
import {
  MANIFESTS_TABLE_FIELDS,
  VERSION_LIST_FAMILY_CONTAINERS,
  VERSION_LIST_OPTIONAL_COLUMNS,
} from '../../constants';
import { versionListFamily, versionsTableFields } from '../../utils';
import ViewOptions from '../components/view_options.vue';

export default {
  name: 'ArtifactRegistryVersionListViewOptions',
  components: {
    GlDisclosureDropdownGroup,
    GlDisclosureDropdownItem,
    GlToggle,
    ViewOptions,
  },
  props: {
    format: {
      type: String,
      required: true,
    },
    hiddenColumns: {
      type: Array,
      required: false,
      default: () => [],
    },
    includeReferrers: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['input', 'referrers-changed'],
  computed: {
    family() {
      return versionListFamily(this.format);
    },
    familyFields() {
      return this.family === VERSION_LIST_FAMILY_CONTAINERS
        ? MANIFESTS_TABLE_FIELDS
        : versionsTableFields(this.format);
    },
    // Filtered from the table fields, not mapped from the optional keys, so a switch cannot exist
    // for a column the table declares no label for.
    columns() {
      const optional = VERSION_LIST_OPTIONAL_COLUMNS[this.family];

      return this.familyFields.filter(({ key }) => optional.includes(key));
    },
    rendersPreferences() {
      return this.family === VERSION_LIST_FAMILY_CONTAINERS;
    },
  },
};
</script>

<template>
  <view-options :columns="columns" :hidden-columns="hiddenColumns" @input="$emit('input', $event)">
    <gl-disclosure-dropdown-group v-if="rendersPreferences" bordered>
      <template #group-label>{{ s__('ArtifactRegistry|Preferences') }}</template>

      <gl-disclosure-dropdown-item
        data-testid="preference-item-referrers"
        @action="$emit('referrers-changed', !includeReferrers)"
      >
        <template #list-item>
          <gl-toggle
            :value="includeReferrers"
            :label="s__('ArtifactRegistry|Referrer manifests')"
            label-position="left"
            class="gl-w-full gl-flex-row gl-justify-between [&_.gl-toggle-label]:gl-font-normal"
          />
        </template>
      </gl-disclosure-dropdown-item>
    </gl-disclosure-dropdown-group>
  </view-options>
</template>
