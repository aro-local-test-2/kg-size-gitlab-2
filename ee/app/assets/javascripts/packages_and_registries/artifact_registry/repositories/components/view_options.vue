<script>
import {
  GlDisclosureDropdown,
  GlDisclosureDropdownGroup,
  GlDisclosureDropdownItem,
  GlToggle,
  GlTooltipDirective,
} from '@gitlab/ui';
import { __ } from '~/locale';

export default {
  name: 'ArtifactRegistryViewOptions',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownGroup,
    GlDisclosureDropdownItem,
    GlToggle,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    columns: {
      type: Array,
      required: true,
    },
    hiddenColumns: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['input'],
  methods: {
    isVisible(key) {
      return !this.hiddenColumns.includes(key);
    },
    toggle(key) {
      const hidden = this.isVisible(key)
        ? [...this.hiddenColumns, key]
        : this.hiddenColumns.filter((hiddenKey) => hiddenKey !== key);

      this.$emit('input', hidden);
    },
  },
  i18n: {
    viewOptions: __('View options'),
  },
};
</script>

<template>
  <gl-disclosure-dropdown
    v-gl-tooltip="$options.i18n.viewOptions"
    class="gl-border gl-rounded-lg gl-border-strong"
    category="tertiary"
    icon="preferences"
    no-caret
    placement="bottom-end"
    :toggle-text="$options.i18n.viewOptions"
    text-sr-only
    :auto-close="false"
    data-testid="view-options"
  >
    <gl-disclosure-dropdown-group>
      <template #group-label>{{ s__('ArtifactRegistry|Columns') }}</template>

      <gl-disclosure-dropdown-item
        v-for="column in columns"
        :key="column.key"
        :data-testid="`column-item-${column.key}`"
        @action="toggle(column.key)"
      >
        <template #list-item>
          <gl-toggle
            :value="isVisible(column.key)"
            :label="column.label"
            label-position="left"
            class="gl-w-full gl-flex-row gl-justify-between [&_.gl-toggle-label]:gl-font-normal"
          />
        </template>
      </gl-disclosure-dropdown-item>
    </gl-disclosure-dropdown-group>

    <slot></slot>
  </gl-disclosure-dropdown>
</template>
