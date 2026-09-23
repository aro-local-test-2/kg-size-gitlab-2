<script>
export default {
  name: 'RiskRationale',
  props: {
    rationale: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <div>
    <h5 class="gl-mb-2 gl-mt-4">{{ s__('RiskClassification|Rationale') }}</h5>
    <p class="gl-mb-0" data-testid="risk-rationale">{{ rationale }}</p>
  </div>
</template>
