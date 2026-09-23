<script>
import { GlIcon, GlProgressBar } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { NON_OPEN_STATE } from '../constants';
import { buildRows, getVerdict } from '../utils';
import ReadinessRow from './readiness_row.vue';

export default {
  name: 'MergeReadiness',
  components: {
    GlIcon,
    GlProgressBar,
    ReadinessRow,
  },
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  computed: {
    rows() {
      return buildRows(this.mergeRequest);
    },
    passingCount() {
      return this.rows.filter((row) => row.passing).length;
    },
    verdict() {
      return getVerdict(this.rows);
    },
    // Everything but an open merge request replaces the panel: the merge gate reports `not_open`
    // as a failing check, which would otherwise read as "not ready to merge" on a merged one.
    nonOpenState() {
      return NON_OPEN_STATE[this.mergeRequest.state] || null;
    },
    checksPassingText() {
      return sprintf(s__('AiOverview|%{passing} of %{total} checks passing'), {
        passing: this.passingCount,
        total: this.rows.length,
      });
    },
    heroTitle() {
      return this.nonOpenState ? this.nonOpenState.title : this.verdict.title;
    },
    heroSubtitle() {
      if (this.nonOpenState) return this.nonOpenState.summary;
      if (!this.verdict.checkStatus) return this.verdict.summary;

      return sprintf(this.verdict.summary, {
        checks: this.rows
          .filter((row) => row.status === this.verdict.checkStatus)
          .map((row) => row.label)
          .join(', '),
      });
    },
  },
};
</script>

<template>
  <div class="ai-overview-hero gl-overflow-hidden gl-rounded-lg">
    <div class="gl-flex gl-items-start gl-justify-between gl-gap-4 gl-px-5 gl-pb-1 gl-pt-4">
      <div class="gl-flex gl-items-start gl-gap-3">
        <span
          class="gl-flex gl-h-8 gl-w-8 gl-shrink-0 gl-items-center gl-justify-center gl-rounded-lg gl-bg-purple-500 gl-text-neutral-0"
        >
          <gl-icon name="tanuki-ai" :size="16" />
        </span>
        <div>
          <h3 class="gl-m-0 gl-text-base gl-font-bold">{{ heroTitle }}</h3>
          <p class="gl-mb-0 gl-mt-1 gl-text-sm gl-text-subtle">{{ heroSubtitle }}</p>
        </div>
      </div>
    </div>

    <template v-if="!nonOpenState">
      <div class="gl-px-5 gl-pb-4 gl-pt-3">
        <div class="gl-mb-2 gl-flex gl-items-center gl-justify-between gl-gap-3">
          <span class="gl-text-sm gl-font-bold" :class="verdict.statusClass">{{
            verdict.status
          }}</span>
          <span class="gl-text-sm gl-text-subtle">{{ checksPassingText }}</span>
        </div>
        <gl-progress-bar
          :value="passingCount"
          :max="rows.length"
          :variant="verdict.variant"
          aria-hidden="true"
        />
      </div>

      <ul class="gl-m-0 gl-list-none gl-bg-default gl-p-0">
        <readiness-row v-for="row in rows" :key="row.key" :row="row" />
      </ul>
    </template>
  </div>
</template>
