<script>
import { GlSprintf } from '@gitlab/ui';

export default {
  name: 'RiskSignalBreakdown',
  components: { GlSprintf },
  props: {
    contributions: {
      type: Array,
      required: true,
    },
    missingSignalsText: {
      type: String,
      required: false,
      default: '',
    },
    isLowConfidence: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
};
</script>

<template>
  <div>
    <h5 class="gl-mb-2 gl-mt-4">
      {{ s__('RiskClassification|What contributed to this score') }}
    </h5>
    <p
      v-if="isLowConfidence && missingSignalsText"
      class="gl-mb-2 gl-text-sm gl-text-subtle"
      data-testid="risk-low-confidence"
    >
      <gl-sprintf
        :message="
          s__('RiskClassification|Based on a partial picture: %{missing} could not be measured.')
        "
      >
        <template #missing>{{ missingSignalsText }}</template>
      </gl-sprintf>
    </p>
    <ul class="gl-list-none gl-pl-0" data-testid="risk-signal-breakdown">
      <li
        v-for="entry in contributions"
        :key="entry.signal"
        class="gl-border-b gl-border-b-default gl-py-2 last:gl-border-b-0"
      >
        {{ entry.label || entry.signal }}
        <span v-if="entry.detail" class="gl-block gl-text-sm gl-text-subtle">{{
          entry.detail
        }}</span>
      </li>
    </ul>
  </div>
</template>
