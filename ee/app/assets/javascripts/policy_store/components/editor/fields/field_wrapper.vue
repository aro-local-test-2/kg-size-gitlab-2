<script>
import { GlFormGroup, GlIcon, GlTooltipDirective } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';

export default {
  name: 'FieldWrapper',
  components: { GlFormGroup, GlIcon },
  directives: { GlTooltip: GlTooltipDirective },
  mixins: [glSlotsMixin],
  props: {
    field: {
      type: Object,
      required: true,
    },
    // False when the slot holds a group of controls rather than one labelable element,
    // so the label is not given a `for` that points at nothing.
    labelledControl: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  data() {
    // Per instance, not per field key: several ConfigWrappers render at once and
    // catalog entries may share keys, which would give two controls one DOM id.
    return {
      inputId: uniqueId('policy-store-field-'),
      labelTextId: uniqueId('policy-store-field-label-'),
    };
  },
  computed: {
    labelFor() {
      return this.labelledControl ? this.inputId : null;
    },
  },
};
</script>

<template>
  <gl-form-group :label-for="labelFor" :description="field.description" class="gl-mb-0">
    <!-- The row lives inside the label because bootstrap-vue forces `!gl-block` on the
         label itself. A control slotted beside the text should point `aria-labelledby`
         at labelTextId so the actions do not become part of its accessible name. -->
    <template #label>
      <span class="gl-flex gl-items-center gl-justify-between" data-testid="label-row">
        <span :id="labelTextId">
          {{ field.label
          }}<span v-if="field.required" class="gl-text-danger" data-testid="required-marker">
            *</span
          >
          <gl-icon
            v-if="field.helpText"
            v-gl-tooltip
            name="question-o"
            :size="12"
            :title="field.helpText"
            class="gl-ml-1 gl-text-subtle"
          />
        </span>
        <slot name="label-actions"></slot>
      </span>
    </template>
    <template v-if="glSlots().default" #default>
      <slot :input-id="inputId" :label-text-id="labelTextId"></slot>
    </template>
  </gl-form-group>
</template>
