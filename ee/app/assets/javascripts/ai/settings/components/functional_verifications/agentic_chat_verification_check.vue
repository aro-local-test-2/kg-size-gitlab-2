<script>
import { s__ } from '~/locale';
import getFunctionalVerificationStatusQuery from '../../graphql/queries/get_functional_verification_status.query.graphql';
import FunctionalVerificationCheck from './functional_verification_check.vue';
import { CHECK_TYPES, FUNCTIONAL_VERIFICATION_STATUS, NOT_RUN_STATE } from './constants';

export default {
  name: 'AgenticChatVerificationCheck',
  components: {
    FunctionalVerificationCheck,
  },
  props: {
    model: {
      type: Object,
      required: false,
      default: null,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['updated'],
  data() {
    return {
      run: NOT_RUN_STATE,
      queryError: false,
    };
  },
  apollo: {
    run: {
      query: getFunctionalVerificationStatusQuery,
      variables: {
        checkType: CHECK_TYPES.AGENTIC_CHAT,
      },
      update(data) {
        this.queryError = false;

        const run = data.functionalVerificationStatus;

        if (!run) {
          return NOT_RUN_STATE;
        }

        return { state: run.state, checkedAt: run.updatedAt };
      },
      error() {
        this.queryError = true;
      },
      skip() {
        return this.disabled;
      },
    },
  },
  computed: {
    status() {
      return this.run?.state ?? FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN;
    },
    lastRunAt() {
      return this.run?.checkedAt;
    },
    errorText() {
      if (this.queryError) return s__('AiPowered|Failed to load last run details.');

      // TODO: error message handled when mutation/WebSocket-driven run is wired up
      // ISsue: https://gitlab.com/gitlab-org/gitlab/-/work_items/627472
      return '';
    },
  },
  watch: {
    run: {
      immediate: true,
      handler(run) {
        this.$emit('updated', run);
      },
    },
  },
  methods: {
    // No-op until the mutation/WebSocket-driven run is wired up
    // Issue: https://gitlab.com/gitlab-org/gitlab/-/work_items/627472
    runCheck() {},
  },
};
</script>

<template>
  <functional-verification-check
    :name="s__('AiPowered|Agentic Chat')"
    :description="s__('AiPowered|Verifies the request flow of Agentic Chat end to end.')"
    :status="status"
    :model="model"
    :last-run-at="lastRunAt"
    :error-text="errorText"
    :disabled="disabled"
    @run="runCheck"
  />
</template>
