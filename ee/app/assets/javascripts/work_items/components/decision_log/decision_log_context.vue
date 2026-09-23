<script>
import { GlButton, GlCollapse } from '@gitlab/ui';
import { s__ } from '~/locale';

const HEADING_CLASSES =
  'gl-mb-1 gl-text-xs gl-font-semibold gl-uppercase gl-tracking-wide gl-text-subtle';

export default {
  name: 'DecisionLogContext',
  components: {
    GlButton,
    GlCollapse,
  },
  props: {
    context: {
      type: String,
      required: false,
      default: '',
    },
    rationale: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return {
      isVisible: false,
    };
  },
  computed: {
    toggleText() {
      return this.isVisible
        ? s__('WorkItemDecisionLog|Hide context')
        : s__('WorkItemDecisionLog|Show context');
    },
    toggleIcon() {
      return this.isVisible ? 'chevron-down' : 'chevron-right';
    },
  },
  methods: {
    toggle() {
      this.isVisible = !this.isVisible;
    },
  },
  headingClasses: HEADING_CLASSES,
};
</script>

<template>
  <div>
    <gl-button
      class="gl-mt-2"
      category="tertiary"
      size="small"
      :icon="toggleIcon"
      :aria-expanded="String(isVisible)"
      data-testid="decision-context-toggle"
      @click="toggle"
    >
      {{ toggleText }}
    </gl-button>

    <gl-collapse :visible="isVisible">
      <div class="gl-border-t gl-mt-3 gl-border-section gl-pt-3">
        <template v-if="context">
          <h4 :class="$options.headingClasses">{{ s__('WorkItemDecisionLog|Context') }}</h4>
          <p class="gl-mb-0 gl-text-sm" data-testid="decision-context">{{ context }}</p>
        </template>

        <!-- No rationale is left blank rather than filled in, so an empty Why is simply absent. -->
        <template v-if="rationale">
          <h4 :class="$options.headingClasses" class="gl-mt-4">
            {{ s__('WorkItemDecisionLog|Why') }}
          </h4>
          <p class="gl-mb-0 gl-text-sm" data-testid="decision-why">{{ rationale }}</p>
        </template>
      </div>
    </gl-collapse>
  </div>
</template>
