<script>
import {
  GlBadge,
  GlButton,
  GlCard,
  GlFormGroup,
  GlFormInputGroup,
  GlInputGroupText,
  GlToggle,
} from '@gitlab/ui';

export default {
  name: 'CreditCapsFlatUserCapControl',
  components: {
    GlBadge,
    GlButton,
    GlCard,
    GlFormGroup,
    GlFormInputGroup,
    GlInputGroupText,
    GlToggle,
  },
  props: {
    flatUserCap: {
      type: Number,
      required: false,
      default: undefined,
    },
    flatUserCapEnabled: {
      type: Boolean,
      required: false,
      default: undefined,
    },
    isSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['save'],
  data() {
    return {
      draftFlatUserCap: this.flatUserCap,
      draftFlatUserCapEnabled: this.flatUserCapEnabled,
    };
  },
  watch: {
    flatUserCap(val) {
      this.draftFlatUserCap = val;
    },
    flatUserCapEnabled(val) {
      this.draftFlatUserCapEnabled = val;
    },
  },
  methods: {
    onSubmit() {
      this.$emit('save', {
        flatUserCap: this.draftFlatUserCap,
        flatUserCapEnabled: this.draftFlatUserCapEnabled ?? false,
      });
    },
  },
};
</script>

<template>
  <gl-card data-testid="flat-user-cap-control">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between">
        <div>
          <h3 class="gl-heading-scale-500 gl-mb-1">{{ s__('UsageBilling|Flat per-user cap') }}</h3>
          <p class="gl-mb-0 gl-text-subtle">
            {{
              s__(
                'UsageBilling|Applies to every user in this namespace unless an override replaces it.',
              )
            }}
          </p>
        </div>

        <gl-badge v-if="flatUserCapEnabled" variant="info" data-testid="cap-status-badge">
          {{ s__('UsageBilling|Flat cap enabled') }}
        </gl-badge>
        <gl-badge v-else variant="neutral" data-testid="cap-status-badge">
          {{ s__('UsageBilling|Flat cap disabled') }}
        </gl-badge>
      </div>
    </template>

    <template #default>
      <form @submit.prevent="onSubmit">
        <div class="gl-flex gl-flex-wrap gl-gap-5">
          <gl-form-group :label="s__('UsageBilling|Flat cap')" class="gl-mb-0">
            <label for="flat-user-cap-input" class="gl-sr-only">
              {{ s__('UsageBilling|Flat cap amount in credits') }}
            </label>
            <gl-form-input-group
              id="flat-user-cap-input"
              v-model.number="draftFlatUserCap"
              required
              type="number"
              min="0"
              step="1"
              :disabled="isSaving"
              data-testid="cap-amount-input"
              class="gl-w-48"
            >
              <template #append>
                <gl-input-group-text>{{ s__('UsageBilling|credits') }}</gl-input-group-text>
              </template>
            </gl-form-input-group>
            <p class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle">
              {{ s__('UsageBilling|Per user, per month. Resets on the 1st.') }}
            </p>
          </gl-form-group>

          <gl-form-group :label="s__('UsageBilling|Status')" class="gl-mb-0">
            <div class="gl-flex gl-h-7 gl-items-center gl-gap-3">
              <gl-toggle
                v-model="draftFlatUserCapEnabled"
                class="gl-h-7"
                :label="s__('UsageBilling|Enforce cap')"
                label-position="left"
                :disabled="isSaving"
                data-testid="cap-enabled-toggle"
              />
            </div>
            <p class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle">
              {{ s__('UsageBilling|When off, usage is tracked but not blocked.') }}
            </p>
          </gl-form-group>
        </div>

        <div class="gl-mt-5">
          <gl-button
            variant="confirm"
            type="submit"
            :loading="isSaving"
            data-testid="save-button"
            >{{ s__('UsageBilling|Save') }}</gl-button
          >
        </div>
      </form>
    </template>
  </gl-card>
</template>
