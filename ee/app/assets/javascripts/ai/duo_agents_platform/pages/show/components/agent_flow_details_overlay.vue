<script>
import { uniqueId } from 'lodash-es';
import {
  GlBadge,
  GlCollapse,
  GlIcon,
  GlIntersperse,
  GlLink,
  GlSkeletonLoader,
  GlTooltipDirective,
} from '@gitlab/ui';
import { createListFormat, s__ } from '~/locale';
import { projectAutomateAgentSessionPath } from 'ee/lib/utils/path_helpers/project';
import {
  ciJobsLabel,
  formatFlowLabel,
  parseExecutorLogUrls,
} from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'AgentFlowDetailsOverlay',
  components: {
    GlBadge,
    GlCollapse,
    GlIcon,
    GlIntersperse,
    GlLink,
    GlSkeletonLoader,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    visible: {
      type: Boolean,
      required: false,
      default: false,
    },
    workflowId: {
      type: String,
      required: true,
    },
    project: {
      type: Object,
      required: true,
    },
    agentFlowDefinition: {
      type: String,
      required: true,
    },
    flowVersion: {
      type: String,
      required: false,
      default: '',
    },
    aiCatalogItemPath: {
      type: String,
      required: false,
      default: '',
    },
    allExecutorUrls: {
      type: Array,
      required: false,
      default: () => [],
    },
    modelName: {
      type: String,
      required: false,
      default: '',
    },
    modelIdentifier: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['toggle'],
  data() {
    return {
      contentId: uniqueId('agent-flow-details-overlay-'),
    };
  },
  computed: {
    ariaExpanded() {
      return String(this.visible);
    },
    sessionUrl() {
      const projectFullPath = this.project?.fullPath;

      return projectFullPath
        ? projectAutomateAgentSessionPath(projectFullPath, this.workflowId)
        : '';
    },
    flowText() {
      return formatFlowLabel(this.agentFlowDefinition, this.flowVersion);
    },
    jobItems() {
      return parseExecutorLogUrls(this.allExecutorUrls);
    },
    ciJobsLabel() {
      return ciJobsLabel(this.jobItems.length);
    },
    summary() {
      if (this.isLoading) {
        return '';
      }

      const parts = [s__('DuoAgentPlatform|Session ID')];

      if (this.jobItems.length) {
        parts.push(this.ciJobsLabel);
      }

      if (this.modelName) {
        parts.push(s__('DuoAgentPlatform|Model'));
      }

      return createListFormat({ style: 'narrow' }).format(parts);
    },
  },
};
</script>
<template>
  <div class="gl-border-t gl-sticky gl-bottom-0 gl-z-2 gl-mt-auto gl-shrink-0 gl-bg-default">
    <button
      type="button"
      class="gl-flex gl-w-full gl-items-center gl-justify-between gl-gap-3 gl-border-0 gl-bg-transparent gl-px-4 gl-py-3 gl-text-left gl-text-md focus-visible:gl-focus-inset"
      :aria-expanded="ariaExpanded"
      :aria-controls="contentId"
      data-testid="details-overlay-toggle"
      @click="$emit('toggle')"
    >
      <span class="gl-font-bold gl-text-default">{{
        s__('DuoAgentPlatform|Session details')
      }}</span>
      <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-2 gl-text-subtle">
        <span class="gl-truncate">{{ summary }}</span>
        <gl-icon :name="visible ? 'chevron-down' : 'chevron-up'" variant="subtle" />
      </span>
    </button>
    <gl-collapse :id="contentId" :visible="visible" data-testid="details-overlay-collapse">
      <dl
        class="gl-mb-0 gl-flex gl-max-h-48 gl-flex-col gl-gap-3 gl-overflow-y-auto gl-px-4 gl-pb-4 gl-pt-3 gl-text-md"
        data-testid="details-overlay-content"
      >
        <gl-skeleton-loader v-if="isLoading" :lines="4" />
        <template v-else>
          <div class="gl-flex gl-gap-6">
            <dt class="gl-w-13 gl-shrink-0 gl-font-normal gl-text-subtle">
              {{ s__('DuoAgentPlatform|Session ID') }}
            </dt>
            <dd class="gl-mb-0 gl-min-w-0" data-testid="session-id">
              <gl-link
                v-if="sessionUrl"
                :href="sessionUrl"
                variant="meta"
                class="hover:gl-text-link"
                >{{ workflowId }}</gl-link
              >
              <template v-else>{{ workflowId }}</template>
            </dd>
          </div>

          <div class="gl-flex gl-gap-6">
            <dt class="gl-w-13 gl-shrink-0 gl-font-normal gl-text-subtle">
              {{ s__('DuoAgentPlatform|Flow') }}
            </dt>
            <dd class="gl-mb-0 gl-min-w-0" data-testid="flow">
              <gl-link
                v-if="aiCatalogItemPath"
                :href="aiCatalogItemPath"
                variant="meta"
                class="hover:gl-text-link"
                >{{ flowText }}</gl-link
              >
              <template v-else>{{ flowText }}</template>
            </dd>
          </div>

          <div class="gl-flex gl-gap-6">
            <dt
              class="gl-w-13 gl-shrink-0 gl-font-normal gl-text-subtle"
              data-testid="ci-jobs-label"
            >
              {{ ciJobsLabel }}
            </dt>
            <dd class="gl-mb-0 gl-min-w-0" data-testid="ci-jobs">
              <gl-intersperse v-if="jobItems.length">
                <gl-link
                  v-for="jobItem in jobItems"
                  :key="jobItem.iid"
                  :href="jobItem.webPath"
                  variant="meta"
                  class="hover:gl-text-link"
                  >{{ jobItem.iid }}</gl-link
                >
              </gl-intersperse>
              <template v-else>{{ __('None') }}</template>
            </dd>
          </div>

          <div v-if="modelName" class="gl-flex gl-gap-6">
            <dt class="gl-w-13 gl-shrink-0 gl-font-normal gl-text-subtle">
              {{ s__('DuoAgentPlatform|Default model') }}
            </dt>
            <dd class="gl-mb-0 gl-min-w-0" data-testid="default-model">
              <gl-badge
                v-gl-tooltip="modelIdentifier"
                class="gl-font-monospace"
                data-testid="model-badge"
              >
                {{ modelName }}
              </gl-badge>
            </dd>
          </div>
        </template>
      </dl>
    </gl-collapse>
  </div>
</template>
