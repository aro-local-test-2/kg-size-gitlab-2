<script>
import { GlDrawer } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { MountingPortal } from 'portal-vue';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';

export default {
  name: 'ArtifactRegistryInstructionsDrawer',
  components: {
    GlDrawer,
    MountingPortal,
  },
  mixins: [glSlotsMixin],
  props: {
    title: {
      type: String,
      required: true,
    },
    accessibleTitle: {
      type: String,
      required: false,
      default: '',
    },
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['close'],
  data() {
    return {
      titleId: uniqueId('instructions-drawer-title-'),
      trigger: null,
    };
  },
  computed: {
    headerHeight() {
      return getContentWrapperHeight();
    },
  },
  watch: {
    open(isOpen) {
      if (isOpen) {
        this.trigger = document.activeElement;
      } else {
        this.returnFocus();
      }
    },
  },
  methods: {
    focusDrawer() {
      this.$refs.drawer?.$el?.focus();
    },
    // GlDrawer moves no focus of its own, so the shell takes focus on open and hands it back
    // on close; otherwise the closing drawer drops focus to <body> and a keyboard user
    // restarts from the top of the page. Trapping focus for the span in between is
    // GlDrawer's to do, and it does not.
    returnFocus() {
      this.trigger?.focus();
      this.trigger = null;
    },
  },
  DRAWER_Z_INDEX,
};
</script>

<template>
  <!-- Mounted at the body: .panel-content is a containing block for fixed descendants
  (contain: layout), which would otherwise scope this drawer to the panel. -->
  <mounting-portal mount-to="body" append>
    <gl-drawer
      ref="drawer"
      :aria-labelledby="titleId"
      :open="open"
      :header-height="headerHeight"
      :z-index="$options.DRAWER_Z_INDEX"
      header-sticky
      tabindex="-1"
      @opened="focusDrawer"
      @close="$emit('close')"
    >
      <template #title>
        <h2 :id="titleId" class="gl-heading-3 gl-my-0">
          <template v-if="accessibleTitle">
            <span aria-hidden="true">{{ title }}</span>
            <span class="gl-sr-only">{{ accessibleTitle }}</span>
          </template>
          <template v-else>{{ title }}</template>
        </h2>
      </template>

      <template v-if="glSlots().default"><slot></slot></template>
    </gl-drawer>
  </mounting-portal>
</template>
