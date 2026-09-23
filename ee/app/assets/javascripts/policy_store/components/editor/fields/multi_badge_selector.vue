<script>
import { GlBadge } from '@gitlab/ui';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'MultiBadgeSelector',
  components: { FieldWrapper, GlBadge },
  props: {
    field: {
      type: Object,
      required: true,
    },
    value: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['input'],
  methods: {
    isSelected(id) {
      return this.value.includes(id);
    },
    // A string, not a boolean: Vue drops an attribute bound to `false`, and an absent
    // aria-pressed reads as "not a toggle" rather than "a toggle that is off".
    ariaPressed(id) {
      return String(this.isSelected(id));
    },
    toggle(id) {
      const updated = this.isSelected(id)
        ? this.value.filter((selected) => selected !== id)
        : [...this.value, id];

      this.$emit('input', updated);
    },
  },
};
</script>

<template>
  <!-- The options are buttons, so there is no single element for a `for` to point at.
       Without one, the wrapper renders a fieldset whose legend names the group. -->
  <field-wrapper :field="field" :labelled-control="false">
    <div class="gl-flex gl-flex-wrap gl-gap-2">
      <gl-badge
        v-for="option in field.options"
        :key="option.id"
        tag="button"
        type="button"
        :variant="isSelected(option.id) ? 'info' : 'neutral'"
        :aria-pressed="ariaPressed(option.id)"
        class="gl-cursor-pointer"
        @click="toggle(option.id)"
      >
        {{ option.label }}
      </gl-badge>
    </div>
  </field-wrapper>
</template>
