<script>
import { GlFormCheckbox, GlFormGroup, GlTooltipDirective } from '@gitlab/ui';
import { s__ } from '~/locale';

export default {
  name: 'DuoWebSearchForm',
  i18n: {
    sectionTitle: s__('DuoWorkflowSettings|Web search'),
    checkboxLabel: s__('DuoWorkflowSettings|Allow web search'),
    checkboxHelpText: s__(
      'DuoWorkflowSettings|When enabled, GitLab Duo Chat can send user questions to an external search provider to find current information. Users still choose to turn on web search in each conversation.',
    ),
    disabledTooltip: s__('AiPowered|This setting only applies when GitLab Duo is available.'),
  },
  components: {
    GlFormCheckbox,
    GlFormGroup,
  },
  directives: {
    tooltip: GlTooltipDirective,
  },
  props: {
    webSearchEnabled: {
      type: Boolean,
      required: true,
    },
    disabledCheckbox: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  methods: {
    checkboxChanged(value) {
      this.$emit('change', value);
    },
  },
};
</script>
<template>
  <gl-form-group :label="$options.i18n.sectionTitle">
    <gl-form-checkbox
      :checked="webSearchEnabled"
      :disabled="disabledCheckbox"
      data-testid="web-search-enabled-checkbox"
      name="namespace[ai_settings_attributes][web_search_enabled]"
      @change="checkboxChanged"
    >
      <span v-tooltip="disabledCheckbox ? $options.i18n.disabledTooltip : ''">{{
        $options.i18n.checkboxLabel
      }}</span>
      <template #help>
        {{ $options.i18n.checkboxHelpText }}
      </template>
    </gl-form-checkbox>
  </gl-form-group>
</template>
