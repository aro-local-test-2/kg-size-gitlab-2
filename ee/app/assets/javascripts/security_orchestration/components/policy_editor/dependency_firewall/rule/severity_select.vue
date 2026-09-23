<script>
import { GlCollapsibleListbox } from '@gitlab/ui';
import { s__ } from '~/locale';
import { SEVERITY_LISTBOX_ITEMS } from '../constants';

export default {
  name: 'SeveritySelect',
  SEVERITY_LISTBOX_ITEMS,
  components: { GlCollapsibleListbox },
  i18n: {
    header: s__('SecurityOrchestration|Severity threshold'),
  },
  props: {
    selected: {
      type: String,
      required: true,
    },
  },
  emits: ['select'],
  computed: {
    toggleText() {
      return (
        SEVERITY_LISTBOX_ITEMS.find(({ value }) => value === this.selected)?.text ||
        this.$options.i18n.header
      );
    },
  },
};
</script>

<template>
  <gl-collapsible-listbox
    :header-text="$options.i18n.header"
    :items="$options.SEVERITY_LISTBOX_ITEMS"
    :selected="selected"
    :toggle-text="toggleText"
    @select="$emit('select', $event)"
  />
</template>
