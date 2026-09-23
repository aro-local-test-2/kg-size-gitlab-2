<script>
import { GlFormGroup, GlFormRadioGroup, GlFormRadio, GlIcon } from '@gitlab/ui';
import { s__ } from '~/locale';
import { ENFORCEMENT_TYPE_ITEMS } from '../constants';

export default {
  name: 'EnforcementTypeSelect',
  ENFORCEMENT_TYPE_ITEMS,
  components: { GlFormGroup, GlFormRadioGroup, GlFormRadio, GlIcon },
  i18n: {
    label: s__('SecurityOrchestration|Enforcement mode'),
  },
  props: {
    enforcementType: {
      type: String,
      required: true,
    },
  },
  emits: ['change'],
};
</script>

<template>
  <gl-form-group :label="$options.i18n.label" class="gl-mt-5">
    <gl-form-radio-group :checked="enforcementType" @change="$emit('change', $event)">
      <gl-form-radio
        v-for="item in $options.ENFORCEMENT_TYPE_ITEMS"
        :key="item.value"
        :value="item.value"
        :data-testid="`enforcement-radio-${item.value}`"
      >
        <span class="gl-inline-flex gl-items-center gl-gap-2">
          <gl-icon :name="item.icon" :class="item.iconClass" :size="12" />
          <span class="gl-font-bold">{{ item.text }}</span>
        </span>
        <template #help>{{ item.description }}</template>
      </gl-form-radio>
    </gl-form-radio-group>
  </gl-form-group>
</template>
