<script>
import { GlButton, GlFormCheckbox, GlFormInput, GlTooltipDirective } from '@gitlab/ui';
import { getDraft, updateDraft } from '~/lib/utils/autosave';
import { s__ } from '~/locale';
import { stripDuoAnswerMarker } from '../../utils/duo_question';

export default {
  name: 'DuoCustomAnswerInput',
  components: { GlButton, GlFormCheckbox, GlFormInput },
  directives: { GlTooltip: GlTooltipDirective },
  props: {
    draftKey: {
      type: String,
      required: true,
    },
    inputId: {
      type: String,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    submitting: {
      type: Boolean,
      required: false,
      default: false,
    },
    multiple: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['submit', 'change'],
  data() {
    const customAnswer = getDraft(this.draftKey) ?? '';

    // A draft restored from a previous visit counts already, so it starts ticked.
    return { customAnswer, isSelected: stripDuoAnswerMarker(customAnswer).length > 0 };
  },
  computed: {
    label() {
      return stripDuoAnswerMarker(this.customAnswer);
    },
    canSubmit() {
      return this.label.length > 0 && !this.disabled;
    },
    tooltip() {
      return this.canSubmit ? '' : s__('WorkItemDuoQuestion|An answer is required to submit');
    },
    selectedAnswer() {
      return this.isSelected ? this.label : '';
    },
    isChecked() {
      return this.multiple && this.isSelected;
    },
  },
  watch: {
    customAnswer(value, previous) {
      updateDraft(this.draftKey, value);

      // The checkmark follows the text appearing and disappearing, not every edit in between:
      // an answer checked off by hand stays out while it is corrected, and clearing the
      // text takes it away rather than leaving a checkbox with nothing in it.
      if (!this.label.length) {
        this.isSelected = false;
      } else if (!stripDuoAnswerMarker(previous).length) {
        this.isSelected = true;
      }
    },
    selectedAnswer: {
      immediate: true,
      handler(value) {
        this.$emit('change', value);
      },
    },
  },
  methods: {
    // Enter reaches this even when the button is disabled, so the guard is not
    // redundant with the button's `disabled`.
    submit() {
      if (this.canSubmit) this.$emit('submit', this.label);
    },
    onEnter() {
      if (!this.multiple) this.submit();
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-min-h-8 gl-items-center gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-py-1 focus-within:gl-focus"
    :class="[
      multiple ? 'gl-px-4' : 'gl-gap-2 gl-pr-2',
      isChecked ? 'gl-bg-subtle' : 'gl-bg-default dark:gl-bg-neutral-700',
    ]"
  >
    <gl-form-checkbox
      v-if="multiple"
      v-model="isSelected"
      :disabled="disabled || !label.length"
      class="gl-mb-0 gl-mr-0 !gl-min-h-0 gl-w-5 gl-shrink-0 [&_label]:!gl-mb-0"
      data-testid="duo-custom-answer-checkbox"
    >
      <span class="gl-sr-only">{{ s__('WorkItemDuoQuestion|Include your answer') }}</span>
    </gl-form-checkbox>
    <label :for="inputId" class="gl-sr-only">{{
      s__('WorkItemDuoQuestion|Answer in your own words')
    }}</label>
    <gl-form-input
      :id="inputId"
      v-model.trim="customAnswer"
      :placeholder="s__('WorkItemDuoQuestion|Type your answer here…')"
      :disabled="disabled"
      class="!gl-bg-transparent !gl-shadow-none"
      :class="{ '!gl-pl-3': multiple }"
      data-testid="duo-custom-answer-input"
      @keydown.enter="onEnter"
    />
    <gl-button
      v-if="!multiple"
      v-gl-tooltip="tooltip"
      :disabled="!canSubmit"
      :loading="submitting"
      :aria-label="s__('WorkItemDuoQuestion|Send answer')"
      variant="confirm"
      icon="paper-airplane"
      data-testid="duo-custom-answer-submit"
      @click="submit"
    />
  </div>
</template>
