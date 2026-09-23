<script>
import { GlBadge } from '@gitlab/ui';
import { s__ } from '~/locale';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import MrWidget from '~/vue_merge_request_widget/components/widget/widget.vue';
import ViewSessionButton from 'ee/ai/shared/widgets/view_session_button.vue';
import RiskRationale from './components/risk_rationale.vue';
import RiskSignalBreakdown from './components/risk_signal_breakdown.vue';
import RiskStaleWarning from './components/risk_stale_warning.vue';
import {
  CONFIDENCE_BADGE_VARIANTS,
  CONFIDENCE_LABELS,
  DEFAULT_RISK_ASSESSMENT,
  STATUS_COMPLETE,
  STATUS_FAILED,
  STATUS_ICONS,
  STATUS_PENDING,
  STATUS_QUEUED,
  TIER_BADGE_VARIANTS,
  TIER_LABELS,
  TIER_LOW,
} from './constants';

export default {
  name: 'WidgetRiskClassification',
  components: {
    GlBadge,
    MrWidget,
    RiskRationale,
    RiskSignalBreakdown,
    RiskStaleWarning,
    ViewSessionButton,
  },
  props: {
    riskAssessment: {
      type: Object,
      required: false,
      default: null,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    hasError: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    safeRiskClassification() {
      return { ...DEFAULT_RISK_ASSESSMENT, ...this.riskAssessment };
    },
    status() {
      return this.safeRiskClassification.status;
    },
    // A refresh leaves the previous score in place for the scoring job to replace,
    // so a queued record still carries a result worth showing. A failed run is a
    // hard stop instead: there is no result left to trust.
    isClassified() {
      return [STATUS_COMPLETE, STATUS_QUEUED].includes(this.status) && Boolean(this.tier);
    },
    isRefreshing() {
      return this.isClassified && this.status === STATUS_QUEUED;
    },
    statusIconName() {
      return STATUS_ICONS[this.status] ?? EXTENSION_ICONS.neutral;
    },
    tier() {
      return this.safeRiskClassification.riskTier;
    },
    tierLabel() {
      return TIER_LABELS[this.tier] ?? this.tier;
    },
    tierVariant() {
      return TIER_BADGE_VARIANTS[this.tier] ?? 'neutral';
    },
    confidenceTier() {
      return this.safeRiskClassification.confidenceTier;
    },
    confidenceLabel() {
      return CONFIDENCE_LABELS[this.confidenceTier] ?? this.confidenceTier;
    },
    confidenceVariant() {
      return CONFIDENCE_BADGE_VARIANTS[this.confidenceTier] ?? 'neutral';
    },
    isLowConfidence() {
      return this.confidenceTier === TIER_LOW;
    },
    summaryTitle() {
      if (this.isLoading) {
        return s__('RiskClassification|Loading the risk assessment');
      }

      if (this.status === STATUS_FAILED) {
        return s__('RiskClassification|Risk assessment failed');
      }

      if (this.isRefreshing) {
        return s__('RiskClassification|Risk assessment updating');
      }

      if (this.status === STATUS_QUEUED) {
        return s__('RiskClassification|New risk assessment queued');
      }

      if (this.status === STATUS_PENDING) {
        return s__('RiskClassification|Risk assessment pending');
      }

      return s__('RiskClassification|Risk assessment');
    },
    contributions() {
      return this.safeRiskClassification.contributingSignals;
    },
    // A claim has no registered signal class to resolve a label from, so its label
    // comes back null. Naming it as a raw key reads worse in prose than leaving it out.
    missingSignalsText() {
      return this.safeRiskClassification.missingSignals
        .map((entry) => entry.label)
        .filter(Boolean)
        .join(', ');
    },
    isStale() {
      return this.safeRiskClassification.stale;
    },
    rationale() {
      return this.safeRiskClassification.rationale;
    },
    duoWorkflowId() {
      return this.safeRiskClassification.duoWorkflowId;
    },
  },
};
</script>

<template>
  <div class="mr-section-container">
    <mr-widget
      :error-text="s__('RiskClassification|Failed to load the risk assessment')"
      :status-icon-name="statusIconName"
      :has-error="hasError"
      :is-collapsible="isClassified"
      widget-name="WidgetRiskClassification"
      data-testid="mr-risk-classification-widget"
      class="mr-widget-section"
    >
      <template #summary>
        <div class="gl-flex gl-h-full gl-flex-wrap gl-items-center gl-gap-3">
          <span data-testid="risk-summary">{{ summaryTitle }}</span>

          <template v-if="isClassified">
            <gl-badge class="gl-ml-auto" :variant="tierVariant" data-testid="risk-tier-badge">
              {{ tierLabel }}
            </gl-badge>

            <gl-badge :variant="confidenceVariant" data-testid="risk-confidence-badge">
              {{ confidenceLabel }}
            </gl-badge>
          </template>
        </div>
      </template>

      <template #action-buttons>
        <view-session-button
          v-if="duoWorkflowId"
          class="gl-ml-3"
          size="small"
          :session-id="duoWorkflowId"
          data-testid="risk-duo-session-link"
        />
      </template>

      <template #content>
        <div v-if="isClassified" class="gl-px-4 gl-py-3">
          <risk-stale-warning v-if="isStale" />
          <risk-rationale v-if="rationale" :rationale="rationale" />
          <risk-signal-breakdown
            v-if="contributions.length"
            :contributions="contributions"
            :missing-signals-text="missingSignalsText"
            :is-low-confidence="isLowConfidence"
          />
        </div>
      </template>
    </mr-widget>
  </div>
</template>
