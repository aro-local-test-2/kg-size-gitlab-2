<script>
export default {
  name: 'RiskStaleWarning',
};
</script>

<template>
  <p class="gl-text-warning" data-testid="risk-stale-warning">
    {{
      s__(
        'RiskClassification|New commits were pushed after this assessment. It reflects an earlier version of the changes.',
      )
    }}
  </p>
</template>
