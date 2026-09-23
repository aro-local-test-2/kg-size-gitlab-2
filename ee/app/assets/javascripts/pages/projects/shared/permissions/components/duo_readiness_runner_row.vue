<script>
import { GlButton } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import { mergeUrlParams } from '~/lib/utils/url_utility';
import DuoReadinessRow from '~/pages/projects/shared/permissions/components/duo_readiness_row.vue';
import {
  STATUS_DONE,
  STATUS_BLOCKED,
  STATUS_ERROR,
  STATUS_LOADING,
  RUNNER_TYPE_TO_TAB,
  DEFAULT_RUNNERS_TAB,
} from '~/pages/projects/shared/permissions/constants';
import duoWorkflowRunnerAvailableQuery from '../graphql/duo_workflow_runner_available.query.graphql';

export default {
  name: 'DuoReadinessRunnerRow',
  components: { DuoReadinessRow, GlButton },
  props: {
    readiness: {
      type: Object,
      required: true,
    },
    flowExecutionEnabled: {
      type: Boolean,
      required: true,
    },
    projectFullPath: {
      type: String,
      required: true,
    },
  },
  emits: ['status-changed'],
  data() {
    return {
      // Reactive mirror of the query's loading state: the immediate status watcher runs
      // before Apollo registers its queries, so reading $apollo.queries there caches wrong.
      checkLoading: true,
      available: null,
      runnerType: null,
      loadFailed: false,
      duoUnavailable: false,
      rechecking: false,
    };
  },
  apollo: {
    available: {
      query: duoWorkflowRunnerAvailableQuery,
      fetchPolicy: 'network-only',
      variables() {
        return { fullPath: this.projectFullPath };
      },
      update(data) {
        return data.project?.duoWorkflowRunnerAvailable ?? null;
      },
      watchLoading(isLoading) {
        this.checkLoading = isLoading;
      },
      result({ data }) {
        const project = data?.project;
        if (!project) return;

        // Field-level authorization redacts to a bare null with no error; not "no runner".
        if (project.duoWorkflowRunnerAvailable == null) {
          this.duoUnavailable = true;
          return;
        }

        this.duoUnavailable = false;
        this.loadFailed = false;
        this.runnerType = project.duoWorkflowUsableRunnerType;
      },
      error() {
        this.loadFailed = true;
      },
    },
  },
  computed: {
    loading() {
      return this.checkLoading;
    },
    viewRunnersHref() {
      const tab = RUNNER_TYPE_TO_TAB[this.runnerType] || DEFAULT_RUNNERS_TAB;

      return mergeUrlParams({ tab }, this.readiness.runnersPath);
    },
    isBlocked() {
      return !this.available && !this.flowExecutionEnabled;
    },
    status() {
      if (this.loading) return STATUS_LOADING;
      if (this.available) return STATUS_DONE;

      return this.isBlocked ? STATUS_BLOCKED : STATUS_ERROR;
    },
    description() {
      if (this.loading) {
        return s__('DuoAgentPlatform|Checking for a usable runner.');
      }
      if (this.available) {
        return s__('DuoAgentPlatform|A runner is available and picking up jobs.');
      }
      if (this.isBlocked) {
        return s__('DuoAgentPlatform|Connect a runner to run CI/CD flows.');
      }
      if (this.duoUnavailable) {
        return s__('DuoAgentPlatform|GitLab Duo is not available for this project.');
      }
      if (this.loadFailed) {
        return s__('DuoAgentPlatform|Could not check for a runner. Try again.');
      }

      return s__(
        "DuoAgentPlatform|Unable to find a runner configured for flows, so flows can't run.",
      );
    },
  },
  watch: {
    status: {
      immediate: true,
      handler(status) {
        this.$emit('status-changed', status);
      },
    },
  },
  methods: {
    async recheck() {
      if (this.rechecking) return;

      this.rechecking = true;

      try {
        const { data } = await this.$apollo.query({
          query: duoWorkflowRunnerAvailableQuery,
          variables: { fullPath: this.projectFullPath },
          fetchPolicy: 'no-cache',
        });

        const available = data?.project?.duoWorkflowRunnerAvailable;

        // Field-level authorization redacts to a bare null with no error; not "no runner".
        if (available == null) {
          this.duoUnavailable = true;
        } else {
          this.duoUnavailable = false;
          this.loadFailed = false;
          this.available = available;
          this.runnerType = data.project.duoWorkflowUsableRunnerType;
        }
      } catch (error) {
        createAlert({
          message: s__('DuoAgentPlatform|Could not check for a runner. Try again.'),
          error,
          captureError: true,
        });
      } finally {
        this.rechecking = false;
      }
    },
  },
  i18n: {
    title: s__('DuoAgentPlatform|CI/CD runner'),
    viewRunners: s__('DuoAgentPlatform|View runners'),
    checkAgain: s__('DuoAgentPlatform|Check again'),
  },
};
</script>

<template>
  <duo-readiness-row :title="$options.i18n.title" :description="description" :status="status">
    <gl-button
      v-if="available"
      category="tertiary"
      size="small"
      :href="viewRunnersHref"
      target="_blank"
      data-testid="runner-row-action"
    >
      {{ $options.i18n.viewRunners }}
    </gl-button>
    <gl-button
      v-else-if="!duoUnavailable"
      category="secondary"
      size="small"
      icon="retry"
      :disabled="!flowExecutionEnabled || loading"
      :loading="rechecking"
      data-testid="runner-row-action"
      @click="recheck"
    >
      {{ $options.i18n.checkAgain }}
    </gl-button>
  </duo-readiness-row>
</template>
