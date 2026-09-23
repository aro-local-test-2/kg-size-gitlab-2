<script>
import { GlFormInput, GlFormTextarea } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__ } from '~/locale';
import { POLICY_NAME_MAX_LENGTH, POLICY_DESCRIPTION_MAX_LENGTH } from './constants';

export default {
  name: 'PolicyNameField',
  components: { GlFormInput, GlFormTextarea },
  POLICY_NAME_MAX_LENGTH,
  POLICY_DESCRIPTION_MAX_LENGTH,
  i18n: {
    nameLabel: s__('PolicyStore|Policy name'),
    namePlaceholder: s__('PolicyStore|Untitled policy'),
    descriptionLabel: s__('PolicyStore|Description'),
    descriptionPlaceholder: s__('PolicyStore|Describe what this policy does'),
    saveHint: s__('PolicyStore|Esc or click outside to save'),
  },
  props: {
    name: {
      type: String,
      required: false,
      default: '',
    },
    description: {
      type: String,
      required: false,
      default: '',
    },
    error: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['update:name', 'update:description'],
  data() {
    return { showDescription: false, errorId: uniqueId('policy-name-error-') };
  },
  watch: {
    // The save button sits in a sticky footer at the bottom of the page while
    // this field is at the top, so bring the rejection back into view.
    error(value) {
      if (value) this.$el.scrollIntoView?.({ block: 'center' });
    },
  },
  methods: {
    openDescription() {
      this.showDescription = true;
    },
    closeDescription() {
      this.showDescription = false;
    },
    onFocusOut(event) {
      if (!this.$refs.header.contains(event.relatedTarget)) this.closeDescription();
    },
  },
};
</script>

<template>
  <div
    ref="header"
    class="gl-relative"
    data-testid="policy-header"
    @focusout="onFocusOut"
    @keydown.esc="closeDescription"
  >
    <gl-form-input
      :value="name"
      :placeholder="$options.i18n.namePlaceholder"
      :aria-label="$options.i18n.nameLabel"
      :aria-invalid="error ? 'true' : null"
      :aria-describedby="error ? errorId : null"
      :maxlength="$options.POLICY_NAME_MAX_LENGTH"
      class="gl-heading-2 gl-mb-0 gl-border-0 gl-bg-transparent gl-px-0 gl-shadow-none"
      data-testid="policy-name"
      @input="$emit('update:name', $event)"
      @focus="openDescription"
    />
    <p
      v-if="error"
      :id="errorId"
      role="alert"
      class="gl-mb-0 gl-mt-1 gl-text-sm gl-text-danger"
      data-testid="policy-name-error"
    >
      {{ error }}
    </p>
    <div
      v-if="showDescription"
      tabindex="-1"
      class="gl-absolute gl-left-0 gl-top-full gl-z-200 gl-mt-2 gl-w-48 gl-rounded-base gl-border-1 gl-border-solid gl-border-default gl-bg-default gl-p-4 gl-shadow-md"
      data-testid="description-panel"
    >
      <label for="policy-description" class="gl-mb-2 gl-block gl-text-sm gl-text-subtle">
        {{ $options.i18n.descriptionLabel }}
      </label>
      <gl-form-textarea
        id="policy-description"
        :value="description"
        :placeholder="$options.i18n.descriptionPlaceholder"
        :rows="5"
        :maxlength="$options.POLICY_DESCRIPTION_MAX_LENGTH"
        :no-resize="false"
        class="gl-resize-y"
        @input="$emit('update:description', $event)"
      />
      <p class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle">{{ $options.i18n.saveHint }}</p>
    </div>
  </div>
</template>
