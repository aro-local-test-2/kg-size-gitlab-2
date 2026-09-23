<script>
import { GlButton } from '@gitlab/ui';
import axios from '~/lib/utils/axios_utils';
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import { projectAutomateAgentSessionPath } from 'ee/lib/utils/path_helpers/project';
import DuoReadinessRow from '~/pages/projects/shared/permissions/components/duo_readiness_row.vue';
import {
  STATUS_DONE,
  STATUS_TODO,
  STATUS_BLOCKED,
} from '~/pages/projects/shared/permissions/constants';

/**
 * The configuration describing what container a flow runs in, and the action that generates it.
 *
 * Not a blocker: flows run without this file, on a generic image. It matters because that image
 * is unlikely to carry the project's toolchain, so the flow starts and then fails partway.
 */
export default {
  name: 'DuoReadinessAgentConfigRow',
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
  data() {
    return {
      generating: false,
      sessionPath: this.sessionPathFor(this.readiness.agentConfigWorkflowId),
    };
  },
  computed: {
    isPresent() {
      return Boolean(this.readiness.agentConfigPresent);
    },
    mergeRequestPath() {
      return this.readiness.agentConfigMergeRequestPath;
    },
    repositoryEmpty() {
      return Boolean(this.readiness.repositoryEmpty);
    },
    status() {
      if (this.isPresent) return STATUS_DONE;
      if (this.sessionPath || this.mergeRequestPath) return STATUS_TODO;
      if (this.repositoryEmpty) return STATUS_BLOCKED;

      return this.flowExecutionEnabled ? STATUS_TODO : STATUS_BLOCKED;
    },
    description() {
      if (this.isPresent) {
        return s__('DuoAgentPlatform|.gitlab/duo/agent-config.yml is on the default branch.');
      }
      if (this.sessionPath) {
        return s__(
          'DuoAgentPlatform|Generating the file. The session opens a merge request when it finishes.',
        );
      }
      if (this.mergeRequestPath) {
        return s__(
          'DuoAgentPlatform|A merge request adding the file is open. Agents use it once it merges.',
        );
      }
      if (!this.flowExecutionEnabled) {
        return s__('DuoAgentPlatform|Add a config file to customize how flows run in CI/CD.');
      }
      if (this.repositoryEmpty) {
        return s__(
          'DuoAgentPlatform|The repository is empty. Push a first commit, then return here to generate a config file.',
        );
      }

      return s__(
        'DuoAgentPlatform|Add a config file to customize how flows run in CI/CD. File not found.',
      );
    },
    // Without a flow consumer the run fails with a message meaningless to maintainers.
    showGenerate() {
      return (
        Boolean(this.readiness.canGenerate && this.readiness.generateAvailable) &&
        !this.isPresent &&
        !this.mergeRequestPath &&
        !this.sessionPath &&
        this.flowExecutionEnabled
      );
    },
  },
  methods: {
    sessionPathFor(workflowId) {
      return workflowId ? projectAutomateAgentSessionPath(this.projectFullPath, workflowId) : null;
    },
    async generate() {
      this.generating = true;

      try {
        const { data } = await axios.post(this.readiness.generatePath);
        this.sessionPath = this.sessionPathFor(data?.workflow_id);
      } catch (error) {
        const workflowId = error.response?.data?.workflow_id;

        if (workflowId) {
          this.sessionPath = this.sessionPathFor(workflowId);
        } else {
          createAlert({
            message:
              error.response?.data?.message ||
              s__('DuoAgentPlatform|Something went wrong while generating the configuration file.'),
            captureError: true,
            error,
          });
        }
      } finally {
        this.generating = false;
      }
    },
  },
  i18n: {
    title: s__('DuoAgentPlatform|Agent configuration file'),
    viewFile: s__('DuoAgentPlatform|View file'),
    viewSession: s__('DuoAgentPlatform|View session'),
    viewMergeRequest: s__('DuoAgentPlatform|View merge request'),
    generate: s__('DuoAgentPlatform|Generate'),
  },
};
</script>

<template>
  <duo-readiness-row :title="$options.i18n.title" :description="description" :status="status">
    <gl-button
      v-if="isPresent"
      category="tertiary"
      size="small"
      icon="doc-text"
      :href="readiness.agentConfigPath"
      target="_blank"
      data-testid="agent-config-row-action"
    >
      {{ $options.i18n.viewFile }}
    </gl-button>
    <gl-button
      v-else-if="sessionPath"
      category="tertiary"
      size="small"
      :href="sessionPath"
      target="_blank"
      data-testid="agent-config-row-action"
    >
      {{ $options.i18n.viewSession }}
    </gl-button>
    <!-- Linking the open merge request instead of offering Generate again, which would open a
         duplicate for the same file. -->
    <gl-button
      v-else-if="mergeRequestPath"
      category="secondary"
      size="small"
      icon="merge-request"
      :href="mergeRequestPath"
      target="_blank"
      data-testid="agent-config-row-action"
    >
      {{ $options.i18n.viewMergeRequest }}
    </gl-button>
    <gl-button
      v-else-if="showGenerate"
      category="secondary"
      size="small"
      icon="doc-new"
      :loading="generating"
      data-testid="agent-config-row-action"
      @click="generate"
    >
      {{ $options.i18n.generate }}
    </gl-button>
  </duo-readiness-row>
</template>
