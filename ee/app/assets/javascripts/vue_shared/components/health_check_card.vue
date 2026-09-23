<script>
import {
  GlAnimatedChevronRightDownIcon,
  GlButton,
  GlCard,
  GlCollapse,
  GlExperimentBadge,
  GlIcon,
} from '@gitlab/ui';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { __ } from '~/locale';

export default {
  name: 'HealthCheckCard',
  components: {
    GlAnimatedChevronRightDownIcon,
    GlButton,
    GlCard,
    GlCollapse,
    GlExperimentBadge,
    GlIcon,
  },
  mixins: [glSlotsMixin],
  props: {
    title: {
      type: String,
      required: true,
    },
    icon: {
      type: String,
      required: false,
      default: null,
    },
    iconVariant: {
      type: String,
      required: false,
      default: 'default',
    },
    titleMuted: {
      type: Boolean,
      required: false,
      default: false,
    },
    expanded: {
      type: Boolean,
      required: true,
    },
    contentId: {
      type: String,
      required: true,
    },
    expandDisabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['toggle'],
  computed: {
    expandLabel() {
      return this.expanded ? __('Hide results') : __('Show results');
    },
  },
};
</script>

<template>
  <gl-card
    class="gl-mb-5"
    header-class="gl-flex gl-flex-col gl-items-start @sm/panel:gl-flex-row @sm/panel:gl-items-center gl-gap-3 gl-px-5"
    body-class="gl-p-0"
  >
    <template #header>
      <div class="gl-flex gl-min-w-0 gl-grow gl-items-center gl-gap-3">
        <gl-icon
          v-if="icon"
          :name="icon"
          :variant="iconVariant"
          data-testid="health-check-card-icon"
        />

        <h2
          class="gl-m-0 gl-min-w-0 gl-grow gl-text-lg gl-leading-24"
          :class="{ 'gl-text-subtle': titleMuted }"
          data-testid="health-check-card-title"
        >
          {{ title }}
        </h2>
      </div>

      <slot name="actions"></slot>
    </template>

    <template #default>
      <div class="gl-flex gl-items-center gl-gap-3 gl-py-3 gl-pl-4 gl-pr-5">
        <gl-button
          :aria-label="expandLabel"
          :aria-expanded="expanded.toString()"
          :aria-controls="contentId"
          :disabled="expandDisabled"
          size="small"
          class="btn-icon"
          data-testid="health-check-card-expand-button"
          @click="$emit('toggle')"
        >
          <gl-animated-chevron-right-down-icon :is-on="expanded" />
        </gl-button>
        <p class="gl-mb-0" data-testid="health-check-card-expand-text">
          <slot name="expand-text"></slot>
        </p>
        <gl-experiment-badge type="beta" class="gl-ml-auto gl-mr-0" />
      </div>

      <gl-collapse :id="contentId" :visible="expanded" class="border-default gl-border-t">
        <template v-if="glSlots().default"><slot></slot></template>
      </gl-collapse>
    </template>

    <template v-if="expanded && glSlots().footer" #footer>
      <slot name="footer"></slot>
    </template>
  </gl-card>
</template>
