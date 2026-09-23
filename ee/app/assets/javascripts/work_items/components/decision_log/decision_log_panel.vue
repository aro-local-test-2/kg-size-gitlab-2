<script>
import { GlButton, GlEmptyState, GlSkeletonLoader, GlToggle } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import produce from 'immer';
import emptyStateSvg from '@gitlab/svgs/dist/illustrations/empty-state/empty-activity-md.svg';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import { createAlert } from '~/alert';
import { n__, s__, sprintf } from '~/locale';
import {
  getLocationHash,
  updateHistory,
  setUrlParams,
  removeParams,
} from '~/lib/utils/url_utility';
import { DECISION_LOG_PANEL, DETAIL_VIEW_QUERY_PARAM_NAME } from '~/work_items/constants';
import toast from '~/vue_shared/plugins/global_toast';
import { getRequestedPanel } from '~/work_items/utils';
import { activeDecisions, getArchivedDecisions } from './utils';
import { DECISION_ANCHOR_PREFIX } from './constants';
import DecisionLogFormModal from './decision_log_form_modal.vue';
import DecisionLogItem from './decision_log_item.vue';
import archiveDecisionMutation from './graphql/archive_decision.mutation.graphql';
import createDecisionMutation from './graphql/create_decision.mutation.graphql';
import decisionLogQuery from './graphql/decision_log.query.graphql';
import updateDecisionMutation from './graphql/update_decision.mutation.graphql';

export default {
  name: 'DecisionLogPanel',
  components: {
    DecisionLogFormModal,
    DecisionLogItem,
    DynamicPanel,
    GlButton,
    GlEmptyState,
    GlSkeletonLoader,
    GlToggle,
    MountingPortal,
  },
  inheritAttrs: false,
  props: {
    open: {
      type: Boolean,
      required: true,
    },
    workItemId: {
      type: String,
      required: true,
    },
    workItemIid: {
      type: String,
      required: true,
    },
    decisions: {
      type: Array,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    fullPath: {
      type: String,
      required: false,
      default: '',
    },
    isGroup: {
      type: Boolean,
      required: false,
      default: false,
    },
    participants: {
      type: Array,
      required: false,
      default: () => [],
    },
    workItemWebUrl: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['close'],
  data() {
    return {
      isFormVisible: false,
      isSaving: false,
      editedDecision: null,
      showArchived: false,
      // CSS `:target` cannot carry the highlight, because the cards only arrive once this panel
      // has fetched them. The panel tracks the hash so one listener serves every card.
      targetAnchor: getLocationHash() ?? '',
    };
  },
  computed: {
    activeDecisions() {
      return activeDecisions(this.decisions);
    },
    archivedDecisions() {
      return getArchivedDecisions(this.decisions);
    },
    // The heading counts what the work item stands on, so archiving a decision takes it out of the
    // count whether or not the reader is looking at archived ones.
    capturedHeading() {
      return n__('%d decision', '%d decisions', this.activeDecisions.length);
    },
    archivedCount() {
      return this.archivedDecisions.length;
    },
    // A log with nothing archived has nothing to reveal, so the toggle would be a dead control.
    showArchivedToggle() {
      return this.archivedCount > 0;
    },
    showArchivedLabel() {
      return sprintf(s__('WorkItemDecisionLog|Show archived (%{count})'), {
        count: this.archivedCount,
      });
    },
    visibleDecisions() {
      return this.showArchived ? this.decisions : this.activeDecisions;
    },
  },
  watch: {
    open(value) {
      if (value) {
        this.addPanelParam();
      } else {
        this.removePanelParam();
      }
    },
  },
  created() {
    if (this.open) {
      this.addPanelParam();
    }
  },
  mounted() {
    document.addEventListener('keydown', this.handleKeydown);
    window.addEventListener('hashchange', this.readTargetAnchor);
  },
  beforeDestroy() {
    document.removeEventListener('keydown', this.handleKeydown);
    window.removeEventListener('hashchange', this.readTargetAnchor);
  },
  methods: {
    readTargetAnchor() {
      this.targetAnchor = getLocationHash() ?? '';
    },
    addPanelParam() {
      if (getRequestedPanel() === DECISION_LOG_PANEL) return;

      updateHistory({
        url: setUrlParams({ [DETAIL_VIEW_QUERY_PARAM_NAME]: DECISION_LOG_PANEL }),
      });
    },
    // Only clear the param while it still points here, so closing this panel cannot wipe the deep
    // link another panel just wrote. The decision anchor goes with it, so reopening the panel does
    // not highlight whichever card the reader last arrived on.
    removePanelParam() {
      if (getRequestedPanel() !== DECISION_LOG_PANEL) return;

      const url = new URL(removeParams([DETAIL_VIEW_QUERY_PARAM_NAME]));

      if (getLocationHash()?.startsWith(DECISION_ANCHOR_PREFIX)) {
        url.hash = '';
      }

      updateHistory({ url: url.href });
    },
    hasPriorEscapeHandler() {
      const active = document.activeElement;

      return (
        document.body.classList.contains('modal-open') ||
        active?.closest('.js-editor') != null ||
        active?.closest('[contenteditable]:not([contenteditable="false"])') != null ||
        active?.tagName === 'INPUT' ||
        active?.tagName === 'TEXTAREA'
      );
    },
    handleKeydown({ key }) {
      if (key === 'Escape' && this.open && !this.hasPriorEscapeHandler()) {
        this.$emit('close');
      }
    },
    openForm(decision = null) {
      this.editedDecision = decision;
      this.isFormVisible = true;
    },
    closeForm() {
      this.isFormVisible = false;
      this.editedDecision = null;
    },
    saveDecision(fields) {
      if (this.editedDecision) {
        this.updateDecision(fields);
        return;
      }

      this.createDecision(fields);
    },
    // A created decision is a new node, so Apollo cannot place it by normalising the payload the
    // way the update mutation is. The mutation selects the same fields as the list query, so the
    // node can go straight into the cached list.
    addDecisionToCache(cache, decision) {
      const variables = { fullPath: this.fullPath, iid: this.workItemIid };
      const sourceData = cache.readQuery({ query: decisionLogQuery, variables });

      if (!sourceData) return;

      cache.writeQuery({
        query: decisionLogQuery,
        variables,
        data: produce(sourceData, (draftData) => {
          // Newest first, matching the order the list is read in.
          draftData.namespace.workItem.features.decisionLog.decisions.nodes.unshift(decision);
        }),
      });
    },
    async createDecision({ title, resolvedBy, description, resolutionRationale, sourceLink }) {
      this.isSaving = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: createDecisionMutation,
          variables: {
            input: {
              workItemId: this.workItemId,
              // The form asks for a decision, not the question behind one, so the text is sent only
              // as the settled option. Leaving the title unset keeps the card from repeating it as
              // the question line, which is what `title` means everywhere else in the log.
              title: null,
              description,
              sourceLink: sourceLink?.trim() || null,
              resolution: {
                decision: title.trim(),
                rationale: resolutionRationale || null,
                resolvedById: resolvedBy?.id ?? null,
              },
            },
          },
          update: (cache, { data: payload }) => {
            const { decision, errors } = payload?.workItemDecisionCreate ?? {};

            if (!decision || errors?.length) return;

            this.addDecisionToCache(cache, decision);
          },
        });

        const [error] = data?.workItemDecisionCreate?.errors ?? [];
        if (error) throw new Error(error);

        this.closeForm();
        toast(s__('WorkItemDecisionLog|Decision created.'));
      } catch (error) {
        createAlert({
          message: s__(
            'WorkItemDecisionLog|Something went wrong when saving the decision. Please try again.',
          ),
          captureError: true,
          error,
        });
      } finally {
        this.isSaving = false;
      }
    },
    // The mutation rejects blank values and an otherwise empty payload, so a cleared field is
    // left untouched and an unchanged field is never sent.
    changedFields(fields) {
      const changed = Object.entries(fields)
        .map(([name, value]) => [name, value?.trim() ?? ''])
        .filter(([name, value]) => value && value !== (this.editedDecision[name] ?? ''));

      return changed.length ? Object.fromEntries(changed) : null;
    },
    async updateDecision({ title, description, resolutionRationale, sourceLink }) {
      const changed = this.changedFields({ title, description, resolutionRationale, sourceLink });

      if (!changed) {
        this.closeForm();
        return;
      }

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateDecisionMutation,
          variables: { input: { id: this.editedDecision.id, ...changed } },
        });

        const [error] = data?.workItemDecisionUpdate?.errors ?? [];
        if (error) throw new Error(error);

        this.closeForm();
      } catch (error) {
        createAlert({
          message: s__(
            'WorkItemDecisionLog|Something went wrong when saving the decision. Please try again.',
          ),
          captureError: true,
          error,
        });
      }
    },
    async archiveDecision(decision) {
      try {
        const { data } = await this.$apollo.mutate({
          mutation: archiveDecisionMutation,
          variables: { input: { id: decision.id } },
        });

        const [error] = data?.workItemDecisionArchive?.errors ?? [];
        if (error) throw new Error(error);

        toast(s__('WorkItemDecisionLog|Decision archived.'));
      } catch (error) {
        createAlert({
          message: s__(
            'WorkItemDecisionLog|Something went wrong when archiving the decision. Please try again.',
          ),
          captureError: true,
          error,
        });
      }
    },
  },
  emptyStateSvg,
};
</script>

<template>
  <mounting-portal v-if="open" mount-to="#contextual-panel-portal" append>
    <dynamic-panel
      :header="s__('WorkItemDecisionLog|Decision log')"
      data-testid="decision-log-panel"
      @close="$emit('close')"
    >
      <gl-skeleton-loader v-if="isLoading" data-testid="decision-log-loading" />
      <template v-else-if="decisions.length">
        <div
          class="gl-mb-5 gl-mt-4 gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-5"
        >
          <h2 class="gl-heading-3 gl-mb-0" data-testid="decision-log-count">
            {{ capturedHeading }}
          </h2>
          <gl-toggle
            v-if="showArchivedToggle"
            v-model="showArchived"
            class="gl-ml-auto"
            label-position="left"
            data-testid="show-archived-toggle"
          >
            <template #label>
              <span class="gl-font-normal gl-text-subtle">{{ showArchivedLabel }}</span>
            </template>
          </gl-toggle>
          <gl-button size="small" data-testid="new-decision-button" @click="openForm()">
            {{ s__('WorkItemDecisionLog|New decision') }}
          </gl-button>
        </div>
        <ul class="gl-m-0 gl-p-0">
          <decision-log-item
            v-for="decision in visibleDecisions"
            :key="decision.id"
            :decision="decision"
            :work-item-web-url="workItemWebUrl"
            :target-anchor="targetAnchor"
            @view-comment="$emit('close')"
            @edit="openForm(decision)"
            @archive="archiveDecision(decision)"
          />
        </ul>
      </template>
      <gl-empty-state
        v-else
        data-testid="decision-log-empty-state"
        :svg-path="$options.emptyStateSvg"
        :svg-height="144"
        content-class="!gl-px-0"
        :title="s__('WorkItemDecisionLog|No decisions yet')"
        :description="
          s__(
            'WorkItemDecisionLog|Decisions show up here once an open question gets answered or a comment is marked as a decision. Each one keeps the background behind it and a link back to where it was made.',
          )
        "
      >
        <template #actions>
          <gl-button variant="confirm" data-testid="new-decision-button" @click="openForm()">
            {{ s__('WorkItemDecisionLog|New decision') }}
          </gl-button>
        </template>
      </gl-empty-state>

      <decision-log-form-modal
        :visible="isFormVisible"
        :decision="editedDecision"
        :full-path="fullPath"
        :is-group="isGroup"
        :participants="participants"
        :saving="isSaving"
        @save="saveDecision"
        @hide="closeForm"
      />
    </dynamic-panel>
  </mounting-portal>
</template>
