<script>
import RiskClassificationWidget from './index.vue';
import riskAssessmentQuery from './graphql/risk_assessment.query.graphql';

export default {
  name: 'WidgetRiskClassificationApp',
  components: {
    RiskClassificationWidget,
  },
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  apollo: {
    riskAssessment: {
      query: riskAssessmentQuery,
      variables() {
        return {
          projectPath:
            this.mergeRequest.targetProjectFullPath || this.mergeRequest.sourceProjectFullPath,
          iid: String(this.mergeRequest.iid),
        };
      },
      update(data) {
        return data?.project?.mergeRequest?.riskAssessment ?? null;
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      riskAssessment: null,
      hasError: false,
    };
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.riskAssessment.loading;
    },
    shouldRender() {
      return Boolean(this.hasError || this.riskAssessment);
    },
  },
};
</script>

<template>
  <risk-classification-widget
    v-if="shouldRender"
    :risk-assessment="riskAssessment"
    :is-loading="isLoading"
    :has-error="hasError"
  />
</template>
