<script>
import { GlIcon, GlTooltipDirective, GlTruncate } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import {
  STEP_CATEGORY_ICONS,
  STEP_UNKNOWN_ICON,
  STEP_STATE_CLASSES,
  STEP_STATE_LABELS,
  STEP_STATES,
  STEP_MUTED_STATES,
  UNKNOWN_LABEL,
  UNKNOWN_STEP_CLASSES,
} from 'ee/cd/constants';

export default {
  name: 'FlowStep',
  components: {
    GlIcon,
    GlTruncate,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    category: {
      type: String,
      required: false,
      default: null,
    },
    state: {
      type: String,
      required: true,
      validator: (value) => typeof value === 'string' && value.length > 0,
    },
    title: {
      type: String,
      required: false,
      default: '',
    },
    subtitle: {
      type: String,
      required: false,
      default: '',
    },
    nodeId: {
      type: String,
      required: false,
      default: '',
    },
    selectable: {
      type: Boolean,
      required: false,
      default: false,
    },
    selected: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select'],
  computed: {
    stepElement() {
      return this.selectable ? 'button' : 'div';
    },
    stepBindings() {
      if (!this.selectable) {
        return {};
      }

      return {
        type: 'button',
        'aria-current': this.selected ? 'true' : null,
        'aria-label': sprintf(
          s__('ContinuousDeployment|Show details for %{step}, %{state}'),
          { step: this.title, state: this.stateLabel },
          false,
        ),
      };
    },
    selectableClasses() {
      if (!this.selectable) {
        return [];
      }

      return [this.selected ? 'gl-focus' : 'hover:gl-shadow-md hover:-gl-translate-y-px'];
    },
    icon() {
      return STEP_CATEGORY_ICONS[this.category] ?? STEP_UNKNOWN_ICON;
    },
    stateClasses() {
      return STEP_STATE_CLASSES[this.state] ?? UNKNOWN_STEP_CLASSES;
    },
    subtitleText() {
      return this.subtitle || '\u00A0';
    },
    stateLabel() {
      return STEP_STATE_LABELS[this.state] ?? UNKNOWN_LABEL;
    },
    pulseClass() {
      return this.state === STEP_STATES.RUNNING ? 'flow-step-border-pulse' : '';
    },
    isMuted() {
      return STEP_MUTED_STATES.includes(this.state);
    },
    titleClass() {
      return this.isMuted ? 'gl-text-disabled' : 'gl-text-default';
    },
    subtitleClass() {
      return this.isMuted ? 'gl-text-disabled' : 'gl-text-subtle';
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-h-12 gl-w-12 gl-shrink-0 gl-flex-col gl-items-center">
    <component
      :is="stepElement"
      v-gl-tooltip
      v-bind="stepBindings"
      :class="[stateClasses, pulseClass, selectableClasses]"
      :title="stateLabel"
      :data-flow-node="nodeId"
      class="gl-flex gl-h-8 gl-w-8 gl-shrink-0 gl-items-center gl-justify-center gl-rounded-xl gl-border-1 gl-border-solid gl-p-0 gl-transition-all"
      data-testid="flow-step-box"
      @click="selectable && $emit('select')"
    >
      <gl-icon :name="icon" />
    </component>

    <gl-truncate
      v-if="title"
      :text="title"
      with-tooltip
      :class="titleClass"
      class="gl-mt-1 gl-max-w-full gl-text-center gl-font-monospace gl-text-sm gl-font-semibold"
      data-testid="flow-step-title"
    />

    <gl-truncate
      :text="subtitleText"
      position="middle"
      with-tooltip
      :aria-hidden="!subtitle"
      :class="subtitleClass"
      class="gl-mt-px gl-max-w-full gl-text-center gl-font-monospace gl-text-xs"
      data-testid="flow-step-subtitle"
    />
  </div>
</template>
