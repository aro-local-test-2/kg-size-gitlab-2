<script>
import { GlFormRadioGroup, GlFormRadio } from '@gitlab/ui';
import { s__ } from '~/locale';

export default {
  name: 'AllowDenyToggle',
  components: { GlFormRadioGroup, GlFormRadio },
  i18n: {
    denied: s__('SecurityOrchestration|Deny list'),
    allowed: s__('SecurityOrchestration|Allow list'),
  },
  props: {
    listKey: {
      type: String,
      required: true,
    },
  },
  emits: ['change'],
};
</script>

<template>
  <gl-form-radio-group :checked="listKey" @change="$emit('change', $event)">
    <gl-form-radio value="denied">{{ $options.i18n.denied }}</gl-form-radio>
    <gl-form-radio value="allowed">{{ $options.i18n.allowed }}</gl-form-radio>
  </gl-form-radio-group>
</template>
