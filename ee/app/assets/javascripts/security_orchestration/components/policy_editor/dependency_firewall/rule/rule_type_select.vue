<script>
import { GlCollapsibleListbox } from '@gitlab/ui';
import { s__ } from '~/locale';
import { RULE_TYPE_LISTBOX_ITEMS } from '../constants';

export default {
  name: 'RuleTypeSelect',
  components: { GlCollapsibleListbox },
  i18n: {
    header: s__('SecurityOrchestration|Choose a rule type'),
  },
  props: {
    items: {
      type: Array,
      required: false,
      default: () => RULE_TYPE_LISTBOX_ITEMS,
    },
    toggleText: {
      type: String,
      required: false,
      default: '',
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select'],
  computed: {
    computedToggleText() {
      return this.toggleText || this.$options.i18n.header;
    },
  },
};
</script>

<template>
  <gl-collapsible-listbox
    :header-text="$options.i18n.header"
    :toggle-text="computedToggleText"
    :disabled="disabled"
    :items="items"
    @select="$emit('select', $event)"
  />
</template>
