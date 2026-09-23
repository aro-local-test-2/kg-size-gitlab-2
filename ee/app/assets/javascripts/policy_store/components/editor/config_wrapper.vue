<script>
import {
  FIELD_TYPE_CHECKBOX,
  FIELD_TYPE_CODE,
  FIELD_TYPE_FREEZE_WINDOWS,
  FIELD_TYPE_MULTI_BADGE,
  FIELD_TYPE_SELECT,
  FIELD_TYPE_TEXT,
  FIELD_TYPE_TEXTAREA,
  FIELD_TYPE_TEXT_LIST,
} from './constants';
import CheckboxField from './fields/checkbox_field.vue';
import CodeField from './fields/code_field.vue';
import SelectField from './fields/select_field.vue';
import TextField from './fields/text_field.vue';
import TextListField from './fields/text_list_field.vue';
import TextareaField from './fields/textarea_field.vue';
import FreezeWindowsConfig from './freeze_windows_config.vue';
import MultiBadgeSelector from './fields/multi_badge_selector.vue';

// One component per field type, all sharing the same contract: `{ field, value }` in,
// `input` out. A capability contributing its own control adds an entry here rather than
// growing a branch inside the renderer.
//
// A type missing from this map renders nothing, because Vue does not render
// `<component :is="undefined" />`. That is deliberate, and follows
// security_configuration/components/dynamic_fields.vue: it lets the backend catalog add a
// type before the frontend supports it, rather than drawing the wrong control for it.
const FIELD_COMPONENTS = {
  [FIELD_TYPE_TEXT]: TextField,
  [FIELD_TYPE_TEXT_LIST]: TextListField,
  [FIELD_TYPE_TEXTAREA]: TextareaField,
  [FIELD_TYPE_SELECT]: SelectField,
  [FIELD_TYPE_CHECKBOX]: CheckboxField,
  [FIELD_TYPE_MULTI_BADGE]: MultiBadgeSelector,
  [FIELD_TYPE_CODE]: CodeField,
  [FIELD_TYPE_FREEZE_WINDOWS]: FreezeWindowsConfig,
};

export default {
  name: 'ConfigWrapper',
  props: {
    fields: {
      type: Array,
      required: true,
    },
    value: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['input'],
  created() {
    // Seed every field that declares a default, so the value is persisted even when the
    // user never touches the control. Emitted as one update: `update` rebuilds the object
    // from the current value, so seeding field by field would drop all but the last.
    const defaults = this.fields.reduce((acc, field) => {
      const isUnset = this.value[field.key] == null;

      return field.default !== undefined && isUnset ? { ...acc, [field.key]: field.default } : acc;
    }, {});

    if (Object.keys(defaults).length) {
      this.$emit('input', { ...this.value, ...defaults });
    }
  },
  methods: {
    componentFor(type) {
      return FIELD_COMPONENTS[type];
    },
    update(key, newValue) {
      this.$emit('input', { ...this.value, [key]: newValue });
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-4">
    <component
      :is="componentFor(field.type)"
      v-for="field in fields"
      :key="field.key"
      :field="field"
      :value="value[field.key]"
      @input="update(field.key, $event)"
    />
  </div>
</template>
