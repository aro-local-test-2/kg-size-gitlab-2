<script>
import {
  GlAlert,
  GlButton,
  GlFormGroup,
  GlFormTextarea,
  GlIcon,
  GlModal,
  GlModalDirective,
} from '@gitlab/ui';
import { __, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  GATE_ICONS,
  GATE_LABELS,
  GATE_STATE,
  RESOLVED_GATE_TITLES,
  DANGER_STATUS_ICON,
} from 'ee/cd/constants';
import cdRolloutApprovalGatesQuery from 'ee/cd/graphql/applications/flow/cd_rollout_approval_gates.query.graphql';
import cdRolloutGateUpdatedSubscription from 'ee/cd/graphql/applications/flow/cd_rollout_gate_updated.subscription.graphql';
import cdRolloutGateResolveMutation from 'ee/cd/graphql/applications/flow/cd_rollout_gate_resolve.mutation.graphql';

export default {
  name: 'FlowFooter',
  components: {
    GlAlert,
    GlButton,
    GlFormGroup,
    GlFormTextarea,
    GlIcon,
    GlModal,
    TimeAgo,
  },
  directives: {
    GlModal: GlModalDirective,
  },
  props: {
    rolloutId: {
      type: String,
      required: true,
    },
    canResolve: {
      type: Boolean,
      required: false,
      default: false,
    },
    failedSteps: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  modalId: 'cd-reject-gate-modal',
  data() {
    return {
      gates: [],
      gateLoadError: false,
      isResolving: false,
      rejectReason: '',
      approveErrors: [],
      rejectErrors: [],
    };
  },
  apollo: {
    gates: {
      query: cdRolloutApprovalGatesQuery,
      variables() {
        return { id: this.rolloutId };
      },
      update: (data) => data?.organization?.cdRollout?.gates ?? [],
      error(error) {
        this.gateLoadError = true;
        Sentry.captureException(error);
      },
      subscribeToMore: {
        document: cdRolloutGateUpdatedSubscription,
        variables() {
          return { rolloutId: this.rolloutId };
        },
      },
    },
  },
  computed: {
    latestGate() {
      return this.gates.at(-1);
    },
    isVisible() {
      return this.statusItems.length > 0 || this.gateLoadError;
    },
    isAwaitingApproval() {
      return this.latestGate?.state === GATE_STATE.PENDING;
    },
    failedItems() {
      return this.failedSteps.map((step) => ({
        id: step.nodeId,
        icon: DANGER_STATUS_ICON,
        title: this.failedTitle(step),
        reason: step.error,
      }));
    },
    gateItems() {
      return this.gates.map((gate) => ({
        id: gate.id,
        icon: GATE_ICONS[gate.state] ?? GATE_ICONS.UNKNOWN,
        title: this.gateTitle(gate),
        environment: this.environmentLabel(gate),
        reason: gate.reason,
        resolutionReason: gate.resolutionReason,
        resolvedBy: gate.resolvedBy?.username,
        resolvedAt: gate.resolvedAt,
        isPending: gate.state === GATE_STATE.PENDING,
        hasName: Boolean(gate.name),
      }));
    },
    statusItems() {
      return [...this.failedItems, ...this.gateItems];
    },
    modalActionPrimary() {
      return {
        text: s__('ContinuousDeployment|Reject'),
        attributes: { variant: 'danger', size: 'small', loading: this.isResolving },
      };
    },
    modalActionCancel() {
      return {
        text: __('Cancel'),
        attributes: { size: 'small', disabled: this.isResolving },
      };
    },
  },
  methods: {
    failedTitle(step) {
      if (!step.title) {
        return s__('ContinuousDeployment|Step failed');
      }

      return sprintf(s__('ContinuousDeployment|%{step} failed'), { step: step.title }, false);
    },
    gateTitle(gate) {
      if (!gate.name) {
        return GATE_LABELS[gate.state];
      }

      const resolvedTitle = RESOLVED_GATE_TITLES[gate.state];

      if (gate.state === GATE_STATE.PENDING || !resolvedTitle) {
        return gate.name;
      }

      return sprintf(resolvedTitle, { step: gate.name }, false);
    },
    environmentLabel(gate) {
      const name = gate.step?.environment?.name;

      return name ? sprintf(s__('ContinuousDeployment|Environment: %{name}'), { name }, false) : '';
    },
    onModalHidden() {
      this.rejectReason = '';
      this.rejectErrors = [];
    },
    approve() {
      return this.resolveGate(GATE_STATE.APPROVED);
    },
    async reject(event) {
      event.preventDefault();

      const recorded = await this.resolveGate(GATE_STATE.REJECTED, this.rejectReason.trim());

      if (recorded) {
        this.$refs.rejectModal?.hide();
      }
    },
    async resolveGate(status, reason = '') {
      this.isResolving = true;
      this.approveErrors = [];
      this.rejectErrors = [];

      const errors = await this.recordDecision(status, reason);

      if (errors.length) {
        this.isResolving = false;

        if (status === GATE_STATE.REJECTED) {
          this.rejectErrors = errors;
        } else {
          this.approveErrors = errors;
        }

        return false;
      }

      await this.refreshGates();
      this.isResolving = false;

      return true;
    },
    refreshGates() {
      return this.$apollo.queries.gates.refetch().catch(() => {
        this.gateLoadError = true;
      });
    },
    async recordDecision(status, reason) {
      try {
        const { data } = await this.$apollo.mutate({
          mutation: cdRolloutGateResolveMutation,
          variables: {
            input: { id: this.rolloutId, status, resolutionReason: reason || null },
          },
        });

        return data?.cdRolloutGateResolve?.errors ?? [];
      } catch (error) {
        Sentry.captureException(error);

        return [s__('ContinuousDeployment|Failed to record the decision. Please try again.')];
      }
    },
  },
};
</script>

<template>
  <div
    v-if="isVisible"
    class="gl-border-t-1 gl-border-t-default gl-bg-default gl-border-t-solid"
    data-testid="flow-footer"
  >
    <div v-if="gateLoadError" class="gl-px-4 gl-py-3">
      <gl-alert variant="danger" data-testid="gate-load-error" @dismiss="gateLoadError = false">
        {{ s__('ContinuousDeployment|Failed to load the approval gate. Refresh to try again.') }}
      </gl-alert>
    </div>

    <div v-if="statusItems.length" role="status">
      <ul role="list" class="gl-mb-0 gl-list-none gl-pl-0">
        <li
          v-for="item in statusItems"
          :key="item.id"
          class="gl-border-b-1 gl-border-b-default gl-px-4 gl-py-3 gl-border-b-solid last:gl-border-b-0"
          data-testid="status-item"
        >
          <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-x-3 gl-gap-y-2">
            <span
              :class="item.icon.halo"
              class="gl-flex gl-h-5 gl-w-5 gl-shrink-0 gl-items-center gl-justify-center gl-rounded-full"
            >
              <gl-icon :name="item.icon.name" :size="12" :class="item.icon.fill" />
            </span>
            <span class="gl-font-bold" data-testid="status-title">{{ item.title }}</span>
            <span
              v-if="item.environment"
              class="gl-text-sm gl-text-subtle"
              data-testid="status-environment"
              >{{ item.environment }}</span
            >

            <span
              v-if="item.resolvedAt"
              class="gl-flex gl-items-center gl-gap-2 gl-text-sm gl-text-subtle"
              data-testid="status-resolution"
            >
              <template v-if="item.resolvedBy">
                <span class="gl-font-monospace">@{{ item.resolvedBy }}</span>
                <span aria-hidden="true">·</span>
              </template>
              <time-ago :time="item.resolvedAt" />
            </span>

            <span
              v-else-if="item.isPending && item.hasName && !canResolve"
              class="gl-text-sm gl-text-subtle"
              data-testid="status-pending"
              >{{ s__('ContinuousDeployment|Awaiting approval') }}</span
            >
          </div>

          <p
            v-if="item.reason"
            class="gl-mb-0 gl-ml-6 gl-text-sm gl-text-subtle"
            data-testid="status-reason"
          >
            {{ item.reason }}
          </p>

          <p
            v-if="item.resolutionReason"
            class="gl-mb-0 gl-ml-6 gl-text-sm gl-italic gl-text-subtle"
            data-testid="status-resolution-reason"
          >
            {{ item.resolutionReason }}
          </p>
        </li>
      </ul>
    </div>

    <div
      v-if="isAwaitingApproval && canResolve && !gateLoadError"
      class="gl-border-t-1 gl-border-t-default gl-px-4 gl-py-3 gl-border-t-solid"
    >
      <gl-alert
        v-if="approveErrors.length"
        variant="danger"
        class="gl-mb-3"
        data-testid="approve-error"
        @dismiss="approveErrors = []"
      >
        {{ approveErrors.join(' ') }}
      </gl-alert>

      <div class="gl-flex gl-gap-3">
        <gl-button
          variant="confirm"
          size="small"
          :loading="isResolving"
          data-testid="approve-button"
          @click="approve"
        >
          {{ s__('ContinuousDeployment|Approve') }}
        </gl-button>
        <gl-button
          v-gl-modal="$options.modalId"
          size="small"
          :disabled="isResolving"
          data-testid="reject-button"
        >
          {{ s__('ContinuousDeployment|Reject') }}
        </gl-button>
      </div>
    </div>

    <gl-modal
      ref="rejectModal"
      :modal-id="$options.modalId"
      :title="s__('ContinuousDeployment|Reject this approval?')"
      :action-primary="modalActionPrimary"
      :action-cancel="modalActionCancel"
      :no-close-on-esc="isResolving"
      :no-close-on-backdrop="isResolving"
      :hide-header-close="isResolving"
      size="sm"
      @primary="reject"
      @hidden="onModalHidden"
    >
      <gl-alert
        v-if="rejectErrors.length"
        variant="danger"
        class="gl-mb-3"
        data-testid="reject-error"
        @dismiss="rejectErrors = []"
      >
        {{ rejectErrors.join(' ') }}
      </gl-alert>

      <gl-form-group
        :label="s__('ContinuousDeployment|Reason')"
        label-for="cd-reject-gate-reason"
        optional
      >
        <gl-form-textarea
          id="cd-reject-gate-reason"
          v-model="rejectReason"
          data-testid="reject-reason"
          :placeholder="s__('ContinuousDeployment|Explain why this rollout is being rejected')"
          :disabled="isResolving"
        />
      </gl-form-group>
    </gl-modal>
  </div>
</template>
