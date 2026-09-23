<script>
import { GlButton, GlFormGroup, GlFormInput } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import FieldWrapper from './fields/field_wrapper.vue';
import MultiBadgeSelector from './fields/multi_badge_selector.vue';

// Edits a calendar rule's `windows` — the shape the store's transpiler
// accepts: `[{ name, tiers, starts_at, ends_at }]`, where each bound is an
// RFC 3339 instant with an explicit time zone and no sub-second precision.
export default {
  name: 'FreezeWindowsConfig',
  components: {
    GlButton,
    GlFormGroup,
    GlFormInput,
    FieldWrapper,
    MultiBadgeSelector,
  },
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
  computed: {
    freezeWindows() {
      return this.value || [];
    },
    // The catalog declares the shared environment-tier options on the field.
    // MultiBadgeSelector is itself a field control, so the per-row tier picker
    // gets a field of its own rather than this component's.
    tierField() {
      return { key: 'tiers', options: this.field.options || [] };
    },
  },
  methods: {
    // sprintf must not escape: this is read out as an aria-label, so a window
    // named "Q&A freeze" would otherwise be announced with the entity.
    removeLabel(freezeWindow, index) {
      return sprintf(
        s__('PolicyStore|Remove window %{name}'),
        { name: freezeWindow.name || index + 1 },
        false,
      );
    },
    addWindow() {
      this.$emit('input', [
        ...this.freezeWindows,
        { name: '', tiers: [], starts_at: '', ends_at: '' },
      ]);
    },
    removeWindow(index) {
      this.$emit(
        'input',
        this.freezeWindows.filter((_, position) => position !== index),
      );
    },
    updateWindow(index, key, value) {
      this.$emit(
        'input',
        this.freezeWindows.map((freezeWindow, position) =>
          position === index ? { ...freezeWindow, [key]: value } : freezeWindow,
        ),
      );
    },
  },
};
</script>

<template>
  <!-- The rows are a group of controls rather than one labelable element, so the
       wrapper's label names the group instead of pointing at a single input. -->
  <field-wrapper :field="field" :labelled-control="false">
    <div class="gl-flex gl-flex-col gl-gap-4">
      <!-- Rows carry no identity, so they are keyed by index deliberately: every
         control is a controlled :value binding that resyncs on re-render, and
         the only reorder is removal by click, where losing focus is expected. -->
      <div
        v-for="(freezeWindow, index) in freezeWindows"
        :key="index"
        class="gl-rounded-base gl-border-1 gl-border-solid gl-border-default gl-p-4"
        data-testid="freeze-window"
      >
        <div class="gl-flex gl-items-start gl-gap-3">
          <div class="gl-flex gl-grow gl-flex-col gl-gap-3">
            <gl-form-group :label="s__('PolicyStore|Window name')" class="gl-mb-0">
              <gl-form-input
                :value="freezeWindow.name"
                :placeholder="s__('PolicyStore|end-of-year freeze')"
                data-testid="window-name"
                @input="updateWindow(index, 'name', $event)"
              />
            </gl-form-group>
            <gl-form-group :label="s__('PolicyStore|Environment tiers')" class="gl-mb-0">
              <multi-badge-selector
                :field="tierField"
                :value="freezeWindow.tiers"
                @input="updateWindow(index, 'tiers', $event)"
              />
            </gl-form-group>
            <div class="gl-flex gl-flex-wrap gl-gap-3">
              <gl-form-group :label="s__('PolicyStore|Starts at')" class="gl-mb-0 gl-grow">
                <gl-form-input
                  :value="freezeWindow.starts_at"
                  :placeholder="s__('PolicyStore|2026-12-24T00:00:00Z')"
                  data-testid="window-starts-at"
                  @input="updateWindow(index, 'starts_at', $event)"
                />
              </gl-form-group>
              <gl-form-group :label="s__('PolicyStore|Ends at')" class="gl-mb-0 gl-grow">
                <gl-form-input
                  :value="freezeWindow.ends_at"
                  :placeholder="s__('PolicyStore|2027-01-02T00:00:00Z')"
                  data-testid="window-ends-at"
                  @input="updateWindow(index, 'ends_at', $event)"
                />
              </gl-form-group>
            </div>
          </div>
          <gl-button
            icon="remove"
            category="tertiary"
            :aria-label="removeLabel(freezeWindow, index)"
            data-testid="remove-window"
            @click="removeWindow(index)"
          />
        </div>
      </div>
      <gl-button
        category="tertiary"
        size="small"
        icon="plus"
        class="gl-self-start"
        data-testid="add-window"
        @click="addWindow"
      >
        {{ s__('PolicyStore|Add window') }}
      </gl-button>
    </div>
  </field-wrapper>
</template>
