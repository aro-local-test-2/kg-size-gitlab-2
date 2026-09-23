<script>
import { GlBadge, GlLink, GlPopover } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';

/**
 * The to-do and notification buttons load after this popover mounts and push
 * the target along the row. Popper positions once, so wait for the row to stop
 * growing, or the popover points at wherever the button used to be.
 */
const ACTIONS_ROW_SELECTOR = '.js-panel-actions-portal-target';
const SETTLE_DELAY_MS = 300;

export default {
  name: 'DecisionLogOnboardingPopover',
  helpPath: helpPagePath('user/work_items/workplan', { anchor: 'decision-log' }),
  components: { GlBadge, GlLink, GlPopover },
  props: {
    target: {
      type: String,
      required: true,
    },
    hasOpenedDecisionLog: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['dismiss'],
  data() {
    return {
      hasTargetSettled: false,
    };
  },
  watch: {
    hasOpenedDecisionLog: {
      // Immediate, so a log opened before the callout loaded still counts as acknowledgement.
      immediate: true,
      handler(hasOpenedDecisionLog) {
        if (hasOpenedDecisionLog) {
          this.$emit('dismiss');
        }
      },
    },
  },
  mounted() {
    const actionsRow = document.getElementById(this.target)?.closest(ACTIONS_ROW_SELECTOR);

    if (actionsRow) {
      this.resizeObserver = new ResizeObserver(() => this.scheduleSettle());
      this.resizeObserver.observe(actionsRow);
    }

    this.scheduleSettle();
  },
  beforeDestroy() {
    this.stopWaiting();
  },
  methods: {
    scheduleSettle() {
      clearTimeout(this.settleTimeout);
      this.settleTimeout = setTimeout(() => {
        this.hasTargetSettled = true;
        this.stopWaiting();
      }, SETTLE_DELAY_MS);
    },
    stopWaiting() {
      clearTimeout(this.settleTimeout);
      this.resizeObserver?.disconnect();
      this.resizeObserver = null;
    },
  },
};
</script>

<template>
  <gl-popover
    v-if="!hasOpenedDecisionLog"
    :show="hasTargetSettled"
    :show-close-button="true"
    placement="bottom"
    boundary="viewport"
    triggers="manual"
    :target="target"
    data-testid="decision-log-onboarding-popover"
    @close-button-clicked="$emit('dismiss')"
  >
    <template #title>
      <div class="gl-flex gl-items-center gl-gap-3">
        {{ s__('WorkItemDecisionLog|Decision log') }}
        <gl-badge variant="info" size="small">{{ s__('WorkItemDecisionLog|New') }}</gl-badge>
      </div>
    </template>
    <p class="gl-mb-3">
      {{
        s__(
          'WorkItemDecisionLog|Keep a record of decisions and the reasoning behind them. You can add a decision at any time, and GitLab Duo can also capture decisions during planning.',
        )
      }}
    </p>
    <gl-link :href="$options.helpPath">{{
      s__('WorkItemDecisionLog|Learn more about the decision log')
    }}</gl-link>
  </gl-popover>
</template>
