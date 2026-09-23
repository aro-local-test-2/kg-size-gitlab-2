<script>
// One labelled cell of the AI planning metadata row: an uppercase label above a value.
export default {
  name: 'AiWidgetSegment',
  props: {
    label: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-2 gl-text-sm">
    <div class="gl-flex gl-items-end gl-gap-2">
      <span
        class="gl-text-xs gl-font-semibold gl-uppercase gl-tracking-widest gl-text-control-placeholder"
        >{{ label }}</span
      >
      <slot name="label-append"></slot>
    </div>
    <slot></slot>
  </div>
</template>
