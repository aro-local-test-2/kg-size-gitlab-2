<script>
import { GlButton } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import workItemEnableAiPlanningMutation from 'ee/work_items/graphql/work_item_enable_ai_planning.mutation.graphql';
import workItemGenerateWorkplanMutation from 'ee/work_items/graphql/work_item_generate_workplan.mutation.graphql';
import { eventHub, REFETCH_SESSIONS } from 'ee/ai/events/panel';

export default {
  name: 'WorkItemPlanCta',
  components: {
    GlButton,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    workItem: {
      type: Object,
      required: true,
    },
  },
  emits: ['error'],
  data() {
    return {
      isEnabling: false,
    };
  },
  computed: {
    canGenerateAsync() {
      return Boolean(this.glFeatures?.duoWorkplanAsyncFlow);
    },
  },
  methods: {
    async enableAiPlanning() {
      this.isEnabling = true;
      try {
        // Generate first: enabling mounts the widget, whose first query must find the
        // workflow or it races the flow to `NOT_STARTED`.
        const generateError = this.canGenerateAsync ? await this.generateWorkplan() : null;
        await this.enablePlanning();
        if (generateError) {
          this.$emit('error', generateError);
        }
      } catch (error) {
        this.$emit(
          'error',
          s__(
            'WorkItem|Something went wrong while enabling planning for this item. Please try again.',
          ),
        );
        Sentry.captureException(error);
      } finally {
        this.isEnabling = false;
      }
    },
    async enablePlanning() {
      const { data } = await this.$apollo.mutate({
        mutation: workItemEnableAiPlanningMutation,
        variables: {
          input: { id: this.workItem.id },
          useWorkItemFeatures: Boolean(this.glFeatures?.workItemFeaturesField),
        },
      });

      if (data.workItemEnableAiPlanning.errors.length) {
        this.$emit('error', data.workItemEnableAiPlanning.errors.join('\n'));
      }
    },
    // Returns rather than throws, so a flow that cannot start still leaves planning on.
    async generateWorkplan() {
      try {
        const { data } = await this.$apollo.mutate({
          mutation: workItemGenerateWorkplanMutation,
          variables: { input: { id: this.workItem.id } },
        });

        const { errors } = data.workItemGenerateWorkplan;
        if (errors.length) {
          return errors.join('\n');
        }

        eventHub.$emit(REFETCH_SESSIONS);
        return null;
      } catch (error) {
        Sentry.captureException(error);
        return s__('AgentPlan|Something went wrong while starting workplan generation.');
      }
    },
  },
};
</script>

<template>
  <gl-button
    icon="tanuki-ai"
    :loading="isEnabling"
    category="tertiary"
    size="small"
    data-testid="work-item-plan-cta"
    @click="enableAiPlanning"
  >
    {{ s__('WorkItem|Plan') }}
  </gl-button>
</template>
