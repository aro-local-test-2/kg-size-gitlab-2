<script>
import { GlCollapsibleListbox, GlFormGroup } from '@gitlab/ui';
import { s__ } from '~/locale';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import { AVAILABILITY_OPTIONS } from '../constants';

const HELP_TEXTS = {
  [AVAILABILITY_OPTIONS.DEFAULT_ON]: {
    group: s__('AiPowered|Auto mode is available. Subgroups can turn it off.'),
    instance: s__('AiPowered|Auto mode is available. Groups and subgroups can turn it off.'),
  },
  [AVAILABILITY_OPTIONS.DEFAULT_OFF]: {
    group: s__('AiPowered|Auto mode is not available. Subgroups can turn it on.'),
    instance: s__('AiPowered|Auto mode is not available. Groups and subgroups can turn it on.'),
  },
  [AVAILABILITY_OPTIONS.NEVER_ON]: {
    group: s__('AiPowered|Auto mode is not available and cannot be turned on for any subgroup.'),
    instance: s__(
      'AiPowered|Auto mode is not available and cannot be turned on for any group or subgroup.',
    ),
  },
};

export default {
  name: 'DuoAutoModeSettings',
  i18n: {
    sectionTitle: s__('AiPowered|Auto mode'),
    sectionDescription: s__(
      'AiPowered|Control whether users can relax governance "Always Ask" rules to "Always Allow" in the IDE and CLI. "Always Deny" rules always hold, regardless of mode.',
    ),
    defaultOnText: s__('AiPowered|On by default'),
    defaultOffText: s__('AiPowered|Off by default'),
    neverOnText: s__('AiPowered|Always off'),
  },
  components: {
    CascadingLockIcon,
    GlCollapsibleListbox,
    GlFormGroup,
  },
  inject: {
    isGroupSettings: { default: false },
    duoAutoModeCascadingSettings: { default: null },
  },
  props: {
    duoAutoModeAvailability: {
      type: String,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  data() {
    return {
      selectedValue: this.duoAutoModeAvailability,
    };
  },
  computed: {
    dropdownItems() {
      return [
        {
          value: AVAILABILITY_OPTIONS.DEFAULT_ON,
          text: this.$options.i18n.defaultOnText,
          secondaryText: this.helpTextFor(AVAILABILITY_OPTIONS.DEFAULT_ON),
        },
        {
          value: AVAILABILITY_OPTIONS.DEFAULT_OFF,
          text: this.$options.i18n.defaultOffText,
          secondaryText: this.helpTextFor(AVAILABILITY_OPTIONS.DEFAULT_OFF),
        },
        {
          value: AVAILABILITY_OPTIONS.NEVER_ON,
          text: this.$options.i18n.neverOnText,
          secondaryText: this.helpTextFor(AVAILABILITY_OPTIONS.NEVER_ON),
        },
      ];
    },
    selectedToggleText() {
      const item = this.dropdownItems.find((i) => i.value === this.selectedValue);
      return item?.text || '';
    },
    showCascadingButton() {
      return (
        this.duoAutoModeCascadingSettings?.lockedByAncestor ||
        this.duoAutoModeCascadingSettings?.lockedByApplicationSetting
      );
    },
    isDisabled() {
      return this.disabled || this.showCascadingButton;
    },
  },
  methods: {
    helpTextFor(value) {
      const context = this.isGroupSettings ? 'group' : 'instance';
      return HELP_TEXTS[value]?.[context] ?? '';
    },
    onSelect(value) {
      this.selectedValue = value;
      this.$emit('change', value);
    },
  },
};
</script>
<template>
  <gl-form-group
    :label="$options.i18n.sectionTitle"
    :label-description="$options.i18n.sectionDescription"
  >
    <div class="gl-flex gl-items-center gl-gap-3">
      <gl-collapsible-listbox
        :selected="selectedValue"
        :items="dropdownItems"
        :disabled="isDisabled"
        :toggle-text="selectedToggleText"
        data-testid="duo-auto-mode-dropdown"
        @select="onSelect"
      >
        <template #list-item="{ item }">
          <div>
            {{ item.text }}
            <p class="gl-mb-0 gl-text-sm gl-text-subtle">{{ item.secondaryText }}</p>
          </div>
        </template>
      </gl-collapsible-listbox>
      <cascading-lock-icon
        v-if="showCascadingButton"
        :is-locked-by-group-ancestor="duoAutoModeCascadingSettings.lockedByAncestor"
        :is-locked-by-application-settings="duoAutoModeCascadingSettings.lockedByApplicationSetting"
        :ancestor-namespace="duoAutoModeCascadingSettings.ancestorNamespace"
      />
    </div>
  </gl-form-group>
</template>
