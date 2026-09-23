<script>
import { s__ } from '~/locale';
import PanelActionsPortal from '~/vue_shared/components/panel_actions_portal.vue';
import OrbitToggle from './orbit_toggle.vue';

// Owns the Duo Chat panel header: the title and subtitle the panel chrome
// renders, and the actions injected into it through the actions portal. The
// chat state manager already carries this feature's derivation across several
// unrelated methods, so it lives here instead. The redesign flag is read by
// the state manager and arrives as `singleHeader`.
export default {
  name: 'DuoAgenticChatHeader',
  components: {
    OrbitToggle,
    PanelActionsPortal,
  },
  i18n: {
    newChat: s__('DuoAgenticChat|New chat'),
    productName: s__('DuoAgenticChat|GitLab Duo'),
  },
  model: {
    prop: 'orbitEnabled',
    event: 'change',
  },
  props: {
    threadTitle: {
      type: String,
      required: false,
      default: null,
    },
    currentAgent: {
      type: Object,
      required: false,
      default: null,
    },
    orbitEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    // The redesign folds the subheader into the panel header: this component
    // then names the thread, adds a subtitle, and owns the header actions.
    singleHeader: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change-title', 'change-subtitle', 'change'],
  computed: {
    title() {
      if (this.threadTitle) {
        return this.threadTitle;
      }
      // Only the single header names an unstarted thread; the old one left the
      // route-derived title in place.
      return this.singleHeader ? this.$options.i18n.newChat : null;
    },
    subtitle() {
      if (!this.singleHeader) {
        return '';
      }
      return this.currentAgent?.name || this.$options.i18n.productName;
    },
  },
  watch: {
    title: {
      immediate: true,
      handler(title) {
        this.$emit('change-title', title);
      },
    },
    subtitle: {
      immediate: true,
      handler(subtitle) {
        this.$emit('change-subtitle', subtitle);
      },
    },
  },
  beforeDestroy() {
    this.$emit('change-title', null);
    this.$emit('change-subtitle', '');
  },
};
</script>

<template>
  <!-- The Orbit toggle and the session actions menu render in the panel
       header, injected via the actions portal. The title and subtitle are
       emitted, so this renders nothing without the single header. -->
  <panel-actions-portal v-if="singleHeader">
    <orbit-toggle
      :value="orbitEnabled"
      :current-agent="currentAgent"
      icon-only
      @change="$emit('change', $event)"
    />
    <slot></slot>
  </panel-actions-portal>
</template>
