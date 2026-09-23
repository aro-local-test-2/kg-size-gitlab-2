<script>
import { GlCard, GlLink, GlLoadingIcon, GlAlert } from '@gitlab/ui';

export default {
  name: 'DashboardListCard',
  components: {
    GlCard,
    GlLink,
    GlLoadingIcon,
    GlAlert,
  },
  props: {
    title: {
      type: String,
      required: true,
    },
    viewAllText: {
      type: String,
      required: false,
      default: '',
    },
    viewAllHref: {
      type: String,
      required: false,
      default: null,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    errorText: {
      type: String,
      required: false,
      default: '',
    },
    isEmpty: {
      type: Boolean,
      required: false,
      default: false,
    },
    emptyText: {
      type: String,
      required: false,
      default: '',
    },
    // Set by cards that cannot honour the dashboard date range, to state the
    // window they do use.
    footnote: {
      type: String,
      required: false,
      default: '',
    },
  },
};
</script>

<template>
  <gl-card body-class="gl-p-0">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between">
        <div class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <h2 class="gl-m-0 gl-text-base gl-font-bold">{{ title }}</h2>
          <slot name="title-badge"></slot>
        </div>
        <gl-link v-if="viewAllHref" :href="viewAllHref" data-testid="view-all-link">
          {{ viewAllText }}
        </gl-link>
      </div>
    </template>

    <gl-loading-icon v-if="loading" size="md" class="gl-my-6" />
    <gl-alert v-else-if="errorText" variant="danger" :dismissible="false" class="gl-m-3">
      {{ errorText }}
    </gl-alert>
    <div v-else-if="isEmpty" class="gl-p-5 gl-text-center gl-text-subtle" data-testid="empty-state">
      {{ emptyText }}
    </div>
    <ul v-else class="gl-m-0 gl-list-none gl-p-0">
      <slot></slot>
    </ul>

    <template v-if="footnote" #footer>
      <span class="gl-text-sm gl-text-subtle" data-testid="card-footnote">{{ footnote }}</span>
    </template>
  </gl-card>
</template>
