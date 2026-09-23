<script>
import {
  GlAttributeList,
  GlBadge,
  GlIcon,
  GlIntersperse,
  GlLink,
  GlTooltipDirective,
  GlSkeletonLoader,
} from '@gitlab/ui';
import { __, s__ } from '~/locale';
import { localeDateFormat, newDate } from '~/lib/utils/datetime_utility';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { projectAutomateAgentSessionPath } from 'ee/lib/utils/path_helpers/project';
import {
  ciJobsLabel,
  formatFlowLabel,
  parseExecutorLogUrls,
} from 'ee/ai/duo_agents_platform/utils';
import AgentFlowTriggeredUser from '../../../components/common/agent_flow_triggered_user.vue';

export default {
  name: 'AgentFlowDetailsPanel',
  components: {
    GlAttributeList,
    GlBadge,
    GlIcon,
    GlIntersperse,
    GlLink,
    GlSkeletonLoader,
    AgentFlowTriggeredUser,
    TimeAgoTooltip,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    isLoading: {
      required: true,
      type: Boolean,
    },
    agentFlowDefinition: {
      type: String,
      required: true,
    },
    aiCatalogItemPath: {
      type: String,
      required: false,
      default: '',
    },
    flowVersion: {
      type: String,
      required: false,
      default: '',
    },
    project: {
      type: Object,
      required: true,
    },
    user: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    createdAt: {
      type: String,
      required: false,
      default: '',
    },
    updatedAt: {
      type: String,
      required: false,
      default: '',
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
    allExecutorUrls: {
      type: Array,
      required: false,
      default: () => [],
    },
    sessionId: {
      type: String,
      required: true,
    },
  },
  computed: {
    sessionUrl() {
      const projectFullPath = this.project?.fullPath;

      return this.sessionId && projectFullPath
        ? projectAutomateAgentSessionPath(projectFullPath, this.sessionId)
        : '';
    },
    flowName() {
      return formatFlowLabel(this.agentFlowDefinition, this.flowVersion);
    },
    jobItems() {
      return parseExecutorLogUrls(this.allExecutorUrls);
    },
    sections() {
      return [
        {
          label: s__('DuoAgentsPlatform|Identity'),
          text: '',
          rows: [
            {
              label: s__('DuoAgentsPlatform|Session'),
              text: this.sessionId,
              link: this.sessionUrl || null,
              icon: 'session-ai',
            },
            {
              label: s__('AI|Flow'),
              text: this.flowName,
              link: this.aiCatalogItemPath || null,
            },
            {
              label: __('Project'),
              text: this.project?.name || __('None'),
              link: this.project?.webPath || null,
              icon: 'project',
            },
            {
              label: __('Group'),
              text: this.project?.namespace?.name || __('None'),
              link: this.project?.namespace?.webPath || null,
              icon: 'group',
            },
          ],
        },
        {
          label: s__('DuoAgentsPlatform|Execution'),
          text: '',
          rows: [
            {
              label: __('Triggered by'),
              type: 'triggeredUser',
            },
            ...(this.createdAt
              ? [{ label: __('Started'), type: 'timeago', time: this.createdAt }]
              : []),
            ...(this.updatedAt
              ? [{ label: __('Last updated'), type: 'timeago', time: this.updatedAt }]
              : []),
          ],
        },
        {
          label: s__('DuoAgentsPlatform|Supplemental'),
          text: '',
          rows: [
            ...(this.modelName
              ? [
                  {
                    label: s__('DuoAgentsPlatform|Default model'),
                    type: 'model',
                    text: this.modelName,
                    tooltip: this.modelIdentifier,
                  },
                ]
              : []),
            {
              label: this.ciJobsLabel,
              type: 'jobItems',
              jobItems: this.jobItems,
            },
          ],
        },
      ];
    },
    ciJobsLabel() {
      return ciJobsLabel(this.jobItems.length);
    },
  },
  methods: {
    formatDateTime(time) {
      return localeDateFormat.asDateTime.format(newDate(time));
    },
  },
};
</script>
<template>
  <div class="gl-overflow-hidden">
    <div class="gl-@container">
      <gl-attribute-list
        :items="sections"
        layout="vertical"
        class="[&_.gl-attribute-list-item:last-child]:gl-border-b-0"
      >
        <template #label="{ item: section }">
          {{ section.label }}
        </template>
        <template #description="{ item: section }">
          <dl class="gl-m-0">
            <div
              v-for="row in section.rows"
              :key="row.label"
              class="gl-flex gl-flex-col gl-gap-2 gl-py-3"
              :data-testid="`row-${row.label}`"
            >
              <dt class="gl-text-sm gl-text-subtle">
                {{ row.label }}
              </dt>
              <dd v-if="isLoading">
                <gl-skeleton-loader :width="290" lines="1" />
              </dd>
              <dd v-else class="gl-m-0" data-testid="detail-value">
                <agent-flow-triggered-user v-if="row.type === 'triggeredUser'" :user="user" />
                <time-ago-tooltip v-else-if="row.type === 'timeago'" :time="row.time">{{
                  formatDateTime(row.time)
                }}</time-ago-tooltip>
                <span v-else-if="row.type === 'model'">
                  <gl-badge
                    v-gl-tooltip="row.tooltip"
                    class="gl-font-monospace"
                    data-testid="model-badge"
                  >
                    {{ row.text }}
                  </gl-badge>
                </span>
                <span v-else-if="row.type === 'jobItems'" class="gl-min-w-0">
                  <template v-if="row.jobItems.length">
                    <gl-intersperse>
                      <gl-link
                        v-for="jobItem in row.jobItems"
                        :key="jobItem.iid"
                        :href="jobItem.webPath"
                        class="gl-text-inherit gl-no-underline hover:gl-text-link hover:gl-underline"
                        >{{ jobItem.iid }}</gl-link
                      >
                    </gl-intersperse>
                  </template>
                  <template v-else>{{ __('None') }}</template>
                  <p class="gl-mb-0 gl-mt-1 gl-text-sm gl-text-subtle">
                    {{ s__('DuoAgentsPlatform|Raw runner output') }}
                  </p>
                </span>
                <span v-else class="gl-inline-flex gl-items-center gl-gap-2">
                  <gl-icon v-if="row.icon" :name="row.icon" variant="subtle" :size="14" />
                  <gl-link
                    v-if="row.link"
                    :href="row.link"
                    class="gl-text-inherit gl-no-underline hover:gl-text-link hover:gl-underline"
                    >{{ row.text }}</gl-link
                  >
                  <template v-else>{{ row.text }}</template>
                </span>
              </dd>
            </div>
          </dl>
        </template>
      </gl-attribute-list>
    </div>
  </div>
</template>
