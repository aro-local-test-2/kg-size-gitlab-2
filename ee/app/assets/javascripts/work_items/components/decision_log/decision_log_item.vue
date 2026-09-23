<script>
import {
  GlAvatar,
  GlBadge,
  GlDisclosureDropdown,
  GlDisclosureDropdownGroup,
  GlDisclosureDropdownItem,
  GlLink,
} from '@gitlab/ui';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { getBaseURL, isExternal, setUrlParams } from '~/lib/utils/url_utility';
import { __ } from '~/locale';
import toast from '~/vue_shared/plugins/global_toast';
import { DECISION_LOG_PANEL, DETAIL_VIEW_QUERY_PARAM_NAME } from '~/work_items/constants';
import { DECISION_ANCHOR_PREFIX, DECISION_STATE_ARCHIVED } from './constants';
import { decisionSourceUrl, decisionText, settledDecisionOptions } from './utils';
import DecisionLogContext from './decision_log_context.vue';

export default {
  name: 'DecisionLogItem',
  components: {
    DecisionLogContext,
    GlAvatar,
    GlBadge,
    GlDisclosureDropdown,
    GlDisclosureDropdownGroup,
    GlDisclosureDropdownItem,
    GlLink,
    TimeAgoTooltip,
  },
  props: {
    decision: {
      type: Object,
      required: true,
    },
    workItemWebUrl: {
      type: String,
      required: true,
    },
    // The anchor the reader arrived on. The panel owns the hash and hands it to every card.
    targetAnchor: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['view-comment', 'edit', 'archive'],
  computed: {
    anchorId() {
      return `${DECISION_ANCHOR_PREFIX}${getIdFromGraphQLId(this.decision.id)}`;
    },
    isTarget() {
      return this.targetAnchor === this.anchorId;
    },
    isArchived() {
      return this.decision.state === DECISION_STATE_ARCHIVED;
    },
    archivedTextClass() {
      return { 'gl-text-subtle': this.isArchived };
    },
    // The link has to land somewhere the reader can see, so it points at the whole work item, with
    // the param that reopens this panel and the hash that highlights this card.
    decisionUrl() {
      const workItemUrl = new URL(this.workItemWebUrl, getBaseURL()).href;
      const panelUrl = setUrlParams(
        { [DETAIL_VIEW_QUERY_PARAM_NAME]: DECISION_LOG_PANEL },
        { url: workItemUrl, clearParams: true },
      );

      return `${panelUrl}#${this.anchorId}`;
    },
    settledOptions() {
      return settledDecisionOptions(this.decision);
    },
    heading() {
      return decisionText(this.decision);
    },
    otherSettledOptions() {
      return this.settledOptions.slice(1);
    },
    // The question already heads the card when nothing was settled, so it is not repeated below.
    questionSubhead() {
      return this.settledOptions.length ? this.decision.title : null;
    },
    sourceUrl() {
      return decisionSourceUrl(this.decision);
    },
    // A link outside GitLab cannot be reached by moving the panel aside, so it opens in its own
    // tab and leaves the work item where the reader left it.
    isSourceExternal() {
      return Boolean(this.sourceUrl) && isExternal(this.sourceUrl);
    },
    sourceTarget() {
      return this.isSourceExternal ? '_blank' : null;
    },
    hasContext() {
      return Boolean(this.decision.description || this.decision.resolutionRationale);
    },
  },
  async mounted() {
    if (!this.isTarget) return;

    // The panel mounts the card, so the scroll waits for that to settle before it measures.
    await this.$nextTick();

    this.$el.scrollIntoView({ block: 'center' });
  },
  methods: {
    // The panel only has to move aside for a link that lands on the page behind it.
    onSourceClick() {
      if (this.isSourceExternal) return;

      this.$emit('view-comment');
    },
    notifyLinkCopied() {
      toast(__('Link copied to clipboard.'));
    },
  },
};
</script>

<template>
  <li
    :id="anchorId"
    class="decision-log-item gl-mb-4 gl-list-none gl-rounded-lg gl-border-1 gl-border-solid gl-border-section gl-p-4"
    :class="[isArchived ? 'gl-bg-disabled' : 'gl-bg-section', { 'is-target': isTarget }]"
    data-testid="decision-log-item"
  >
    <div class="gl-flex gl-items-start gl-justify-between gl-gap-3">
      <div v-if="heading || otherSettledOptions.length || isArchived" class="gl-min-w-0">
        <!-- The badge leads the card, so an archived decision reads as archived before its text
          does. -->
        <gl-badge v-if="isArchived" class="gl-mb-2" data-testid="decision-archived-badge">
          {{ s__('WorkItemDecisionLog|Archived') }}
        </gl-badge>

        <!-- The decision leads the card, because that is what people scan a log for. The question
          it settled follows underneath, and is absent when the decision was marked from a
          thread. -->
        <h3
          v-if="heading"
          class="gl-heading-4 gl-mb-1"
          :class="archivedTextClass"
          data-testid="decision-answer"
        >
          {{ heading }}
        </h3>

        <ul v-if="otherSettledOptions.length" class="gl-mb-1 gl-p-0">
          <li
            v-for="option in otherSettledOptions"
            :key="option.id"
            class="gl-heading-4 gl-mb-1 gl-list-none"
            :class="archivedTextClass"
            data-testid="decision-answer"
          >
            {{ option.content }}
          </li>
        </ul>
      </div>

      <!-- Without the work item URL there is nothing safe to copy, so the menu stays away rather
        than handing the reader a link to the wrong page. -->
      <gl-disclosure-dropdown
        v-if="workItemWebUrl"
        icon="ellipsis_v"
        category="tertiary"
        size="small"
        placement="bottom-end"
        text-sr-only
        no-caret
        :toggle-text="s__('WorkItemDecisionLog|Decision actions')"
      >
        <gl-disclosure-dropdown-item
          :data-clipboard-text="decisionUrl"
          data-testid="copy-decision-link-action"
          @action="notifyLinkCopied"
        >
          <template #list-item>
            {{ __('Copy link') }}
          </template>
        </gl-disclosure-dropdown-item>
        <gl-disclosure-dropdown-item data-testid="edit-decision-action" @action="$emit('edit')">
          <template #list-item>
            {{ s__('WorkItemDecisionLog|Edit decision') }}
          </template>
        </gl-disclosure-dropdown-item>
        <gl-disclosure-dropdown-group v-if="!isArchived" bordered>
          <gl-disclosure-dropdown-item
            variant="danger"
            data-testid="archive-decision-action"
            @action="$emit('archive')"
          >
            <template #list-item>
              {{ s__('WorkItemDecisionLog|Archive decision') }}
            </template>
          </gl-disclosure-dropdown-item>
        </gl-disclosure-dropdown-group>
      </gl-disclosure-dropdown>
    </div>

    <p
      v-if="questionSubhead"
      class="gl-mb-3 gl-text-sm gl-text-subtle"
      data-testid="decision-question"
    >
      {{ questionSubhead }}
    </p>

    <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-2 gl-text-sm gl-text-subtle">
      <!-- A decision with no resolver drops the attribution rather than the whole line, because
        the time and the link still read on their own. -->

      <template v-if="decision.resolvedBy">
        <gl-avatar
          :size="16"
          :src="decision.resolvedBy.avatarUrl"
          :entity-name="decision.resolvedBy.name"
        />
        <span class="gl-font-bold gl-text-default" data-testid="decision-decided-by">
          {{ decision.resolvedBy.name }}
        </span>
      </template>
      <time-ago-tooltip v-if="decision.resolvedAt" :time="decision.resolvedAt" />
      <!-- The note lives on the page behind this panel, so the panel has to get out of the way
        for the link to land anywhere the reader can see. -->
      <gl-link
        v-if="sourceUrl"
        :href="sourceUrl"
        :target="sourceTarget"
        :show-external-icon="isSourceExternal"
        class="gl-text-sm"
        data-testid="decision-source-link"
        @click="onSourceClick"
      >
        {{ s__('WorkItemDecisionLog|View source') }}
      </gl-link>
    </div>

    <decision-log-context
      v-if="hasContext"
      :context="decision.description"
      :rationale="decision.resolutionRationale"
    />
  </li>
</template>
