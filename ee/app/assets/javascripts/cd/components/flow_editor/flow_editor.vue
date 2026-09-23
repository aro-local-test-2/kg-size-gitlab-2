<script>
import { defineAsyncComponent } from 'vue';
import { GlAlert, GlBadge, GlButton, GlEmptyState, GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { safeLoadAll } from 'js-yaml';
import { n__, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { TYPENAME_CD_APPLICATION } from 'ee/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { ROLLOUT_STAGE_STEP_TYPE } from 'ee/cd/constants';
import cdApplicationFlowQuery from 'ee/cd/graphql/flow_editor/cd_application_flow.query.graphql';
import cdApplicationFlowDefinitionCreateMutation from 'ee/cd/graphql/flow_editor/cd_application_flow_definition_create.mutation.graphql';

const asList = (value) => (Array.isArray(value) ? value : []);

export default {
  name: 'FlowEditor',
  components: {
    GlAlert,
    GlBadge,
    GlButton,
    GlEmptyState,
    GlIcon,
    GlLoadingIcon,
    SourceEditor: defineAsyncComponent(
      () =>
        import(
          /* webpackChunkName: 'flow_source_editor' */ '~/vue_shared/components/source_editor.vue'
        ),
    ),
  },
  props: {
    id: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      application: null,
      draft: '',
      isSeeded: false,
      isSaving: false,
      hasError: false,
      errors: [],
    };
  },
  apollo: {
    application: {
      query: cdApplicationFlowQuery,
      variables() {
        return { applicationId: this.applicationId };
      },
      update: (data) => data?.organization?.cdApplication ?? null,
      result() {
        if (this.isSeeded) {
          return;
        }
        this.draft = this.originalDefinition;
        this.isSeeded = true;
      },
      error() {
        this.hasError = true;
      },
      watchLoading(isLoading) {
        if (isLoading) {
          this.hasError = false;
        }
      },
    },
  },
  computed: {
    applicationId() {
      return convertToGraphQLId(TYPENAME_CD_APPLICATION, this.id);
    },
    isLoading() {
      return this.$apollo.queries.application.loading;
    },
    applicationsShowRoute() {
      return { name: 'applications_show_route', params: { id: this.id } };
    },
    applicationName() {
      return this.application?.name ?? '';
    },
    currentVersion() {
      return this.application?.applicationFlowDefinitions?.nodes?.[0]?.version ?? 0;
    },
    originalDefinition() {
      return this.application?.applicationFlowDefinitions?.nodes?.[0]?.definition ?? '';
    },
    isUnchanged() {
      return this.draft === this.originalDefinition;
    },
    draftVersion() {
      return this.currentVersion + 1;
    },
    draftLabel() {
      return sprintf(s__('FlowEditor|Draft v%{version}'), { version: this.draftVersion });
    },
    draftSteps() {
      const collect = (steps) =>
        asList(steps)
          .filter(Boolean)
          .flatMap((step) => [step, ...collect(step.steps)]);

      try {
        return collect(safeLoadAll(this.draft, { json: true })?.[0]?.steps);
      } catch {
        return null;
      }
    },
    stageCount() {
      return this.draftSteps.filter((step) => step.type === ROLLOUT_STAGE_STEP_TYPE).length;
    },
    stepCount() {
      return this.draftSteps.filter((step) => step.type !== ROLLOUT_STAGE_STEP_TYPE).length;
    },
    stagesText() {
      return n__('FlowEditor|%d stage', 'FlowEditor|%d stages', this.stageCount);
    },
    stepsText() {
      return n__('FlowEditor|%d step', 'FlowEditor|%d steps', this.stepCount);
    },
    basedOnLabel() {
      return this.currentVersion
        ? sprintf(s__('FlowEditor|Based on v%{version}'), { version: this.currentVersion })
        : '';
    },
  },
  methods: {
    goBack() {
      this.$router.push(this.applicationsShowRoute);
    },
    async saveFlow() {
      this.errors = [];

      if (this.draftSteps === null) {
        this.errors = [s__('FlowEditor|The flow is not valid YAML. Fix the syntax and try again.')];
        return;
      }

      this.isSaving = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: cdApplicationFlowDefinitionCreateMutation,
          variables: {
            input: {
              applicationId: this.applicationId,
              definition: this.draft,
            },
          },
          refetchQueries: [
            { query: cdApplicationFlowQuery, variables: { applicationId: this.applicationId } },
          ],
          awaitRefetchQueries: true,
        });

        const errors = data?.cdApplicationFlowDefinitionCreate?.errors ?? [];
        if (errors.length) {
          this.errors = errors;
          return;
        }

        this.goBack();
      } catch (error) {
        this.errors = [s__('FlowEditor|Failed to save the flow. Please try again.')];
        Sentry.captureException(error);
      } finally {
        this.isSaving = false;
      }
    },
  },
};
</script>

<template>
  <div>
    <gl-loading-icon v-if="isLoading" size="lg" class="gl-mt-5" />

    <gl-alert
      v-else-if="hasError"
      variant="danger"
      :dismissible="false"
      class="gl-mt-5"
      data-testid="flow-editor-load-error-alert"
    >
      {{ s__('FlowEditor|Failed to load the application flow. Refresh to try again.') }}
    </gl-alert>

    <gl-empty-state
      v-else-if="!application"
      :title="s__('ContinuousDeployment|Application not found')"
      :description="
        s__(
          'ContinuousDeployment|The application may have been removed or you may not have access to it.',
        )
      "
      data-testid="flow-editor-not-found"
    />

    <template v-else>
      <gl-alert
        v-if="errors.length"
        variant="danger"
        class="gl-mt-5"
        data-testid="flow-editor-error-alert"
        @dismiss="errors = []"
      >
        <ul class="gl-m-0 gl-pl-5">
          <li v-for="(error, index) in errors" :key="index">{{ error }}</li>
        </ul>
      </gl-alert>

      <div class="gl-my-5 gl-flex gl-items-center gl-justify-between gl-gap-3">
        <div class="gl-flex gl-items-start gl-gap-3">
          <gl-button
            category="tertiary"
            icon="chevron-lg-left"
            :aria-label="__('Go back')"
            :to="applicationsShowRoute"
            data-testid="back-button"
          />

          <div class="gl-flex gl-flex-col gl-gap-2">
            <div class="gl-flex gl-items-center gl-gap-3">
              <h1 class="gl-heading-4 gl-mb-0">{{ applicationName }}</h1>
              <gl-badge variant="neutral">{{ draftLabel }}</gl-badge>
            </div>

            <div
              class="gl-flex gl-flex-wrap gl-items-center gl-gap-x-5 gl-gap-y-2 gl-text-sm gl-text-subtle"
            >
              <span v-if="draftSteps !== null" class="gl-flex gl-items-center gl-gap-2">
                <gl-icon name="deployments" />
                <span data-testid="stage-count">{{ stagesText }}</span>
                <span aria-hidden="true">·</span>
                <span data-testid="step-count">{{ stepsText }}</span>
              </span>
              <span v-if="basedOnLabel" data-testid="based-on">{{ basedOnLabel }}</span>
            </div>
          </div>
        </div>

        <div class="gl-flex gl-gap-3">
          <gl-button data-testid="discard-flow-button" @click="goBack">
            {{ s__('FlowEditor|Discard') }}
          </gl-button>
          <gl-button
            variant="confirm"
            :loading="isSaving"
            :disabled="isUnchanged"
            data-testid="save-flow-button"
            @click="saveFlow"
          >
            {{ s__('FlowEditor|Save flow') }}
          </gl-button>
        </div>
      </div>

      <div class="gl-overflow-hidden gl-rounded-base gl-border-1 gl-border-solid gl-border-default">
        <source-editor
          :value="draft"
          file-name="flow.yaml"
          :use-dynamic-height="false"
          data-testid="flow-source-editor"
          @input="draft = $event"
        />
      </div>
    </template>
  </div>
</template>
