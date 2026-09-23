<script>
import { GlNavItem, GlTooltipDirective } from '@gitlab/ui';
import { GlBreakpointInstance } from '@gitlab/ui/src/utils'; // eslint-disable-line no-restricted-syntax -- GlBreakpointInstance is used intentionally to switch the indicator position on viewport width
import { InternalEvents } from '~/tracking';
import { BV_HIDE_TOOLTIP } from '~/lib/utils/constants';
import { keysFor, DUO_CHAT } from '~/behaviors/shortcuts/keybindings';
import { keyboardShortcutsDisabled } from '~/behaviors/shortcuts/shortcuts_disabled';
import { __, sprintf } from '~/locale';
import { sanitize } from '~/lib/dompurify';
import { ROUTE_TO_TAB } from 'ee/ai/duo_agents_platform/router/constants';
import NewChatButton from './new_chat_button.vue';

export default {
  name: 'NavigationRail',
  components: {
    GlNavItem,
    NewChatButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [InternalEvents.mixin()],
  i18n: {
    aiCatalogLabel: __('GitLab Duo AI Catalog'),
    chatOffLabel: __('GitLab Duo Agent Platform'),
    currentChatLabel: __('Current GitLab Duo Chat'),
    duoChatLabel: __('Active GitLab Duo Chat'),
    historyLabel: __('GitLab Duo Chat history'),
    sessionsLabel: __('GitLab Duo sessions'),
    suggestionsLabel: __('GitLab Duo suggestions'),
  },
  props: {
    isExpanded: {
      type: Boolean,
      required: false,
      default: true,
    },
    showSuggestionsTab: {
      type: Boolean,
      required: false,
      default: true,
    },
    showSessionsTab: {
      type: Boolean,
      required: false,
      default: true,
    },
    chatDisabledReason: {
      type: String,
      required: false,
      default: '',
    },
    projectId: {
      type: String,
      required: false,
      default: null,
    },
    namespaceId: {
      type: String,
      required: false,
      default: null,
    },
    isAgenticMode: {
      type: Boolean,
      required: true,
    },
    exploreAiCatalogPath: {
      type: String,
      required: false,
      default: null,
    },
    showChatDisabledNav: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['handle-tab-toggle', 'new-chat', 'new-chat-error'],
  data() {
    return {
      isDesktop: GlBreakpointInstance.isDesktop(),
    };
  },
  computed: {
    indicatorPosition() {
      return this.isDesktop ? 'right' : 'bottom';
    },
    activeTab() {
      return ROUTE_TO_TAB[this.$route?.name];
    },
    duoShortcutKey() {
      return keyboardShortcutsDisabled() || this.isChatDisabled ? null : keysFor(DUO_CHAT);
    },
    isChatDisabled() {
      return Boolean(this.chatDisabledReason);
    },
    chatDisabledTooltip() {
      if (!this.isChatDisabled) return '';

      return sprintf(__('An administrator has turned off GitLab Duo for this %{reason}.'), {
        reason: this.chatDisabledReason,
      });
    },
    formattedDuoShortcutTooltip() {
      if (this.isChatDisabled) return this.chatDisabledTooltip;

      const description = this.isAgenticMode
        ? this.$options.i18n.currentChatLabel
        : this.$options.i18n.duoChatLabel;
      const key = keysFor(DUO_CHAT);
      return keyboardShortcutsDisabled()
        ? description
        : sanitize(`${description} <kbd class="flat gl-ml-1" aria-hidden=true>${key}</kbd>`);
    },
  },
  mounted() {
    window.addEventListener('resize', this.handleWindowResize);
  },
  beforeDestroy() {
    window.removeEventListener('resize', this.handleWindowResize);
  },
  methods: {
    handleWindowResize() {
      this.isDesktop = GlBreakpointInstance.isDesktop();
    },
    // Tabs only convey a selected state while the DuoChat pane is open.
    // When the pane is closed we omit `aria-selected` entirely (return null)
    // so assistive tech doesn't announce unselected tabs as "not selected".
    // We return strings ('true'/'false') rather than booleans because Vue
    // strips boolean `false` attributes, which would drop `aria-selected="false"`.
    ariaSelectedFor(tab) {
      if (!this.isExpanded) return null;
      return this.activeTab === tab ? 'true' : 'false';
    },
    toggleTab(tab) {
      if (!this.isChatDisabled || this.showChatDisabledNav) {
        this.$emit('handle-tab-toggle', tab);
      }
    },
    handleNewChat(agent) {
      this.$emit('new-chat', agent);
    },
    hideTooltips() {
      this.$root.$emit(BV_HIDE_TOOLTIP);
    },
    handleNewChatError(error) {
      this.$emit('new-chat-error', error);
    },
    handleAiCatalogClick() {
      this.trackEvent('click_ai_catalog_button_duo_rail');
    },
  },
};
</script>

<!-- eslint-disable @gitlab/vue-tailwind-no-max-width-media-queries -->
<template>
  <nav class="ai-navigation-rail" :aria-label="__('Duo controls')">
    <template v-if="showChatDisabledNav">
      <gl-nav-item
        v-gl-tooltip.left
        icon="duo-chat-off"
        class="gl-basis-0 !gl-p-1 gl-text-strong"
        :indicator-position="indicatorPosition"
        :aria-label="$options.i18n.chatOffLabel"
        :title="$options.i18n.chatOffLabel"
        :selected="isExpanded"
        data-testid="duo-disabled-toggle"
        is-icon-only
        @click="toggleTab('chat')"
        @pointerleave="hideTooltips"
      />
    </template>
    <template v-else>
      <new-chat-button
        :project-id="projectId"
        :namespace-id="namespaceId"
        :is-chat-disabled="isChatDisabled"
        :is-agent-select-enabled="isAgenticMode"
        :chat-disabled-tooltip="chatDisabledTooltip"
        @new-chat="handleNewChat"
        @hide-tooltips="hideTooltips"
        @new-chat-error="handleNewChatError"
      />
      <div
        class="gl-h-5 gl-w-1 gl-border-0 gl-border-r-1 gl-border-solid gl-border-strong lg:gl-mx-auto lg:gl-mt-1 lg:gl-h-px lg:gl-w-5 lg:gl-border-r-0 lg:gl-border-t-1"
      ></div>
      <div
        role="tablist"
        aria-orientation="vertical"
        class="gl-flex gl-gap-4 lg:gl-flex-col lg:gl-gap-3"
      >
        <gl-nav-item
          v-gl-tooltip.left="{
            title: formattedDuoShortcutTooltip,
            html: true,
          }"
          icon="duo-chat"
          class="js-tanuki-bot-chat-toggle gl-basis-0 !gl-p-1 gl-text-strong"
          :class="{ 'gl-opacity-5': isChatDisabled }"
          :indicator-position="indicatorPosition"
          :selected="activeTab === 'chat'"
          :aria-selected="ariaSelectedFor('chat')"
          :aria-keyshortcuts="duoShortcutKey"
          :aria-label="$options.i18n.duoChatLabel"
          role="tab"
          :aria-disabled="isChatDisabled"
          data-testid="ai-chat-toggle"
          is-icon-only
          @pointerleave="hideTooltips"
          @click="toggleTab('chat')"
        />
        <gl-nav-item
          v-gl-tooltip.left
          icon="history"
          class="gl-basis-0 !gl-p-1 gl-text-strong"
          :class="{ 'gl-opacity-5': isChatDisabled }"
          :indicator-position="indicatorPosition"
          :selected="activeTab === 'history'"
          :aria-selected="ariaSelectedFor('history')"
          :aria-label="$options.i18n.historyLabel"
          :title="isChatDisabled ? chatDisabledTooltip : $options.i18n.historyLabel"
          role="tab"
          :aria-disabled="isChatDisabled"
          data-testid="ai-history-toggle"
          is-icon-only
          @pointerleave="hideTooltips"
          @click="toggleTab('history')"
        />
        <gl-nav-item
          v-if="showSessionsTab"
          v-gl-tooltip.left
          icon="session-ai"
          class="gl-basis-0 !gl-p-1 gl-text-strong"
          :class="{ 'gl-opacity-5': isChatDisabled }"
          :indicator-position="indicatorPosition"
          :selected="activeTab === 'sessions'"
          :aria-selected="ariaSelectedFor('sessions')"
          :aria-label="$options.i18n.sessionsLabel"
          :title="isChatDisabled ? chatDisabledTooltip : $options.i18n.sessionsLabel"
          role="tab"
          :aria-disabled="isChatDisabled"
          data-testid="ai-sessions-toggle"
          @pointerleave="hideTooltips"
          @click="toggleTab('sessions')"
        />
        <gl-nav-item
          v-if="showSuggestionsTab"
          v-gl-tooltip.left
          icon="suggestion-ai"
          class="gl-basis-0 !gl-p-1 gl-text-strong max-lg:gl-ml-auto lg:gl-mt-auto"
          :class="{ 'gl-opacity-5': isChatDisabled }"
          :indicator-position="indicatorPosition"
          :selected="activeTab === 'suggestions'"
          :aria-selected="ariaSelectedFor('suggestions')"
          :aria-label="$options.i18n.suggestionsLabel"
          :title="isChatDisabled ? chatDisabledTooltip : $options.i18n.suggestionsLabel"
          role="tab"
          :aria-disabled="isChatDisabled"
          data-testid="ai-suggestions-toggle"
          is-icon-only
          @pointerleave="hideTooltips"
          @click="toggleTab('suggestions')"
        />
      </div>
      <gl-nav-item
        v-if="exploreAiCatalogPath"
        v-gl-tooltip.left
        icon="tanuki-ai"
        class="gl-basis-0 !gl-p-1 gl-text-strong"
        :class="{ 'max-lg:gl-ml-auto lg:gl-mt-auto': !showSuggestionsTab }"
        :indicator-position="indicatorPosition"
        :aria-label="$options.i18n.aiCatalogLabel"
        :title="$options.i18n.aiCatalogLabel"
        :href="exploreAiCatalogPath"
        target="_blank"
        data-testid="ai-catalog-button"
        is-icon-only
        @pointerleave="hideTooltips"
        @click="handleAiCatalogClick"
      />
    </template>
  </nav>
</template>
