<script>
import { GlDisclosureDropdown, GlTooltipDirective } from '@gitlab/ui';
import { GlBreakpointInstance } from '@gitlab/ui/src/utils'; // eslint-disable-line no-restricted-syntax -- GlBreakpointInstance is used intentionally here. In this case we must obtain viewport breakpoints
import { __, s__ } from '~/locale';
import { CHAT_MODES, duoChatGlobalState } from 'ee/ai/state';
import {
  AGENTS_PLATFORM_SHOW_ROUTE,
  AGENTIC_CHAT_BLOCKED_ROUTE,
  CLOSED_ROUTE,
  ROUTE_TO_TAB,
} from 'ee/ai/duo_agents_platform/router/constants';
import { getDefaultRouteForTab } from 'ee/ai/duo_agents_platform/router/utils';
import { safeRouterPush } from 'ee/ai/duo_agents_platform/utils/router_utils';
import dismissUserCalloutMutation from '~/graphql_shared/mutations/dismiss_user_callout.mutation.graphql';
import AccessiblePanelResizer from '~/vue_shared/components/accessible_panel_resizer.vue';
import RouterViewWithSlot from '~/vue_shared/spa/components/router_view_with_slot';
import { MIN_PANEL_PX, MAX_AI_PANEL_PX } from '~/vue_shared/components/panel_constants';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { setMaximized, toggleMaximized } from '../graphql';
import isMaximizedQuery from '../graphql/get_ai_panel_is_maximized.query.graphql';
import { toggleAiPanelMaximizedClass, toggleAiPanelOpenClass } from '../utils/dom_utils';
import { EventsTracker } from '../duo_agentic_chat/observability/events_tracker';
import AiContentContainer from './content_container.vue';
import NavigationRail from './navigation_rail.vue';

const DUO_PANEL_AUTO_EXPANDED_CALLOUT = 'duo_panel_auto_expanded';

// Quiet period after the last resize value before the event is tracked.
const RESIZE_TRACK_DEBOUNCE_MS = 500;

// Selector for the aside element whose rendered width equals --ai-panel-width.
// CSS custom properties store their raw declared value (e.g. "clamp(...)"), not
// a resolved pixel number, so we read the actual layout width instead.
const PANEL_PORTAL_SELECTOR = '#ai-panel-portal';

export default {
  name: 'AiPanel',
  i18n: {
    resizeLabel: __('Resize AI panel'),
  },
  MIN_PANEL_PX,
  components: {
    AiContentContainer,
    NavigationRail,
    GlDisclosureDropdown,
    AccessiblePanelResizer,
    RouterViewWithSlot,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: ['chatConfiguration'],
  props: {
    userId: {
      type: String,
      required: false,
      default: null,
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
    rootNamespaceId: {
      type: String,
      required: false,
      default: null,
    },
    resourceId: {
      type: String,
      required: false,
      default: null,
    },
    metadata: {
      type: String,
      required: false,
      default: null,
    },
    userModelSelectionEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    chatDisabledReason: {
      type: String,
      required: false,
      default: '',
    },
    shouldShowBlockedState: {
      type: Boolean,
      required: true,
    },
  },
  apollo: {
    isMaximized: {
      query: isMaximizedQuery,
      result({ data }) {
        toggleAiPanelMaximizedClass(data?.isMaximized);
      },
    },
  },
  data() {
    return {
      isDesktop: GlBreakpointInstance.isDesktop(),
      duoChatGlobalState,
      selectedAgentError: null,
      selectedAgent: {},
      isMaximized: false,
      // Reactive viewport-width cache so `computedMaxPx` re-evaluates on
      // resize without a separate listener in the shared resizer wrapper.
      viewportWidth: typeof window === 'undefined' ? 0 : window.innerWidth,
      // Seeded from the rendered panel width after the sibling content
      // container mounts (see mounted() $nextTick). Drives the resizer's
      // aria-valuenow before any drag has occurred.
      defaultPanelWidthPx: MIN_PANEL_PX,
    };
  },
  computed: {
    activeTab() {
      return ROUTE_TO_TAB[this.$route?.name];
    },
    isChatDisabled() {
      return Boolean(this.chatDisabledReason);
    },
    isExpandable() {
      return !this.isChatDisabled || this.shouldShowBlockedState;
    },
    isAgenticMode() {
      return (
        (this.chatConfiguration.defaultProps.isAgenticAvailable &&
          this.duoChatGlobalState.chatMode === CHAT_MODES.AGENTIC) ||
        this.shouldShowBlockedState
      );
    },
    exploreAiCatalogPath() {
      return this.chatConfiguration.defaultProps?.exploreAiCatalogPath ?? null;
    },
    showSessionsTab() {
      return this.chatConfiguration.defaultProps?.isDuoAgentPlatformEnabled ?? false;
    },
    currentChatTitle() {
      if (this.shouldShowBlockedState) {
        // The redesign drops the chat's own header, so the panel header takes
        // over the name that header showed. Not `agenticTitle`: the backend
        // always sends a `chatTitle`, so that resolves to the classic name.
        return this.glFeatures.duoChatRedesign
          ? s__('DuoAgenticChat|GitLab Duo Agentic Chat')
          : __('GitLab Duo Agent Platform');
      }
      return this.isAgenticMode
        ? this.chatConfiguration.agenticTitle
        : this.chatConfiguration.classicTitle;
    },
    currentTabTitle() {
      if (this.shouldShowBlockedState) {
        return this.currentChatTitle;
      }
      if (this.$route?.meta?.title) {
        return this.$route.meta.title;
      }
      switch (this.activeTab) {
        case 'chat':
          return this.currentChatTitle;
        case 'sessions':
          return __('Sessions');
        case 'suggestions':
          return __('Suggestions');
        default:
          return '';
      }
    },
    isPanelOpen() {
      return this.activeTab !== undefined && this.isExpandable;
    },
    isShowingAgentSession() {
      return this.$route?.name === AGENTS_PLATFORM_SHOW_ROUTE;
    },
    canGoBack() {
      // Re-evaluate on every navigation by depending on `$route`.
      // `router.canGoBack` is set up in `createRouter` and tracks how many
      // navigations have completed, avoiding any reliance on vue-router
      // internals like `router.history.index`.
      return Boolean(this.$route) && Boolean(this.$router.canGoBack?.());
    },
    showSessionBackButton() {
      return this.isShowingAgentSession && this.canGoBack;
    },
    panelWidthStyle() {
      const width = this.duoChatGlobalState.aiPanelDragWidth;
      return width != null ? { '--ai-panel-width': `${width}px` } : {};
    },
    computedMaxPx() {
      return Math.min(this.viewportWidth * 0.6, MAX_AI_PANEL_PX);
    },
  },
  watch: {
    'duoChatGlobalState.chatMode': {
      async handler(newMode, oldMode) {
        if (newMode !== oldMode && this.activeTab === 'chat') {
          await this.navigateToChatRoute();
        }
      },
    },
    isPanelOpen: {
      immediate: true,
      handler(isOpen) {
        toggleAiPanelOpenClass(isOpen);
      },
    },
  },
  async mounted() {
    window.addEventListener('resize', this.handleWindowResize);
    // Defer until the next tick so `<ai-content-container>` has mounted —
    // `#ai-panel-portal` lives inside it and isn't in the DOM yet at our
    // own mount time.
    this.$nextTick(() => {
      this.defaultPanelWidthPx = this.readPanelWidth();
    });
    if (!this.isExpandable) {
      await safeRouterPush(this.$router, { name: CLOSED_ROUTE }, { component: 'AiPanel' });
    } else if (this.activeTab === 'chat') {
      await this.navigateToChatRoute();
    }
  },
  beforeDestroy() {
    clearTimeout(this.resizeTrackTimeout);
    window.removeEventListener('resize', this.handleWindowResize);
    // Ensure the root class doesn't leak if the panel is torn down while open.
    toggleAiPanelOpenClass(false);
    // Tear down the router's event-hub listeners (SHOW_SESSION /
    // SHOW_NEW_CHAT) so they don't leak across panel re-mounts.
    this.$router?.cleanupEventListeners?.();
  },
  methods: {
    async navigateToChatRoute() {
      const routeName = this.shouldShowBlockedState
        ? AGENTIC_CHAT_BLOCKED_ROUTE
        : getDefaultRouteForTab('chat', this.isAgenticMode);
      await safeRouterPush(this.$router, { name: routeName }, { component: 'AiPanel' });
    },
    handleGoBack() {
      // The button is only rendered when `canGoBack` is true, so we can rely
      // on the router having a previous route to return to.
      this.$router.back();
    },
    async handleTabToggle(tab) {
      const currentTab = ROUTE_TO_TAB[this.$route?.name];

      if (currentTab === tab) {
        await this.closePanel();
        return;
      }

      const routeName =
        this.shouldShowBlockedState && tab === 'chat'
          ? AGENTIC_CHAT_BLOCKED_ROUTE
          : getDefaultRouteForTab(tab, this.isAgenticMode);

      await safeRouterPush(this.$router, { name: routeName }, { component: 'AiPanel' });

      if (['chat', 'new'].includes(tab)) {
        // The preceding `await safeRouterPush` has already advanced
        // `$route.name`, so the route-derived `activeTab` is already 'chat'.
        // Wait one nextTick for the chat state manager's children to
        // render, then signal the focus.
        await this.$nextTick();
        this.duoChatGlobalState.focusChatInput = true;
      }
    },
    async closePanel() {
      await setMaximized(false);
      await safeRouterPush(this.$router, { name: CLOSED_ROUTE }, { component: 'AiPanel' });
      this.dismissAutoExpandCallout();
      duoChatGlobalState.aiPanelDragWidth = null;
    },
    async dismissAutoExpandCallout() {
      try {
        await this.$apollo.mutate({
          mutation: dismissUserCalloutMutation,
          variables: {
            input: {
              featureName: DUO_PANEL_AUTO_EXPANDED_CALLOUT,
            },
          },
          context: {
            featureCategory: 'duo_agent_platform',
          },
        });
      } catch {
        // Silently ignore errors - callout dismissal is non-critical
      }
    },
    handleWindowResize() {
      const currentIsDesktop = GlBreakpointInstance.isDesktop();
      this.viewportWidth = window.innerWidth;

      // Re-read the painted panel width so the resizer's defaultSize
      // (and therefore aria-valuenow + start-size) tracks the viewport-
      // dependent CSS `clamp(25rem, 20vw, 35rem)`. Skip while maximized:
      // the portal width is the full viewport in that state and would
      // mislead us about the default when the user un-maximizes.
      if (this.duoChatGlobalState.aiPanelDragWidth == null && !this.isMaximized) {
        this.defaultPanelWidthPx = this.readPanelWidth();
      }

      // This check ensures that the panel is collapsed only when resizing
      // from desktop to mobile/tablet, not the other way around
      if (this.isDesktop && !currentIsDesktop) {
        this.closePanel();
      }

      this.isDesktop = currentIsDesktop;
    },
    readPanelWidth() {
      const portal = this.$el?.querySelector?.(PANEL_PORTAL_SELECTOR);
      if (!portal) return MIN_PANEL_PX;
      const { width } = portal.getBoundingClientRect();
      return width > 0 ? width : MIN_PANEL_PX;
    },
    handleNewChatError(error) {
      this.selectedAgentError = error;
    },
    handleResize(width) {
      // `null` is emitted when the resizer is reset (Home key / double-click);
      // preserve the previous v-model behaviour of writing it back, but only
      // track concrete resize values.
      this.duoChatGlobalState.aiPanelDragWidth = width;
      if (width != null) {
        this.trackResizeDebounced(width);
      }
    },
    trackResizeDebounced(width) {
      // Coalesce the continuous stream of resize values (drag and per-keystroke
      // keyboard resize) into a single tracking event once the user settles.
      clearTimeout(this.resizeTrackTimeout);
      this.resizeTrackTimeout = setTimeout(() => {
        EventsTracker.trackPanelResized({ value: Math.round(width) });
      }, RESIZE_TRACK_DEBOUNCE_MS);
    },
    toggleMaximize() {
      // Drag-width is intentionally preserved across maximize cycles so the
      // user's chosen width is restored when leaving maximized state.
      const willMaximize = !this.isMaximized;
      const width = Math.round(
        this.duoChatGlobalState.aiPanelDragWidth ?? this.defaultPanelWidthPx,
      );
      if (willMaximize) {
        EventsTracker.trackPanelMaximized({ value: width });
      } else {
        EventsTracker.trackPanelMinimized({ value: width });
      }
      toggleMaximized();
    },
  },
};
</script>

<template>
  <div class="ai-related-panels gl-contents" data-testid="ai-related-panels">
    <div class="ai-panel-wrapper">
      <accessible-panel-resizer
        v-if="isPanelOpen && isDesktop && !isMaximized"
        :value="duoChatGlobalState.aiPanelDragWidth"
        :default-size="defaultPanelWidthPx"
        :min-size="$options.MIN_PANEL_PX"
        :max-size="computedMaxPx"
        side="left"
        :aria-label="$options.i18n.resizeLabel"
        @input="handleResize"
      />
      <ai-content-container
        v-if="isPanelOpen"
        :style="panelWidthStyle"
        :title="currentTabTitle"
        :show-back-button="showSessionBackButton"
        :is-maximized="isMaximized"
        :show-loading-state="isShowingAgentSession"
        @close-panel="closePanel"
        @go-back="handleGoBack"
        @toggle-maximize="toggleMaximize"
      >
        <template
          #active-tab="{
            showSessionId,
            showSessionDropdownTooltip,
            toggleText,
            items,
            showSessionDropdown,
            hideSessionDropdown,
            handleTitleChange,
            handleSubtitleChange,
            handleSessionIdChanged,
          }"
        >
          <router-view-with-slot #default="{ Component }">
            <component
              :is="Component"
              ref="content-component"
              :user-id="userId"
              :project-id="projectId"
              :namespace-id="namespaceId"
              :root-namespace-id="rootNamespaceId"
              :resource-id="resourceId"
              :metadata="metadata"
              :selected-agent="selectedAgent"
              :user-model-selection-enabled="userModelSelectionEnabled"
              class="gl-h-full"
              @change-title="handleTitleChange"
              @change-subtitle="handleSubtitleChange"
              @session-id-changed="handleSessionIdChanged"
            >
              <template #header>
                <gl-disclosure-dropdown
                  v-if="showSessionId"
                  v-gl-tooltip="showSessionDropdownTooltip"
                  icon="ellipsis_v"
                  category="tertiary"
                  text-sr-only
                  size="small"
                  :toggle-text="toggleText"
                  :items="items"
                  no-caret
                  @shown="showSessionDropdown"
                  @hidden="hideSessionDropdown"
                />
              </template>
            </component>
          </router-view-with-slot>
        </template>
      </ai-content-container>
    </div>
    <navigation-rail
      :is-expanded="isPanelOpen"
      :show-suggestions-tab="false"
      :show-sessions-tab="showSessionsTab"
      :chat-disabled-reason="chatDisabledReason"
      :project-id="projectId"
      :namespace-id="namespaceId"
      :is-agentic-mode="isAgenticMode"
      :explore-ai-catalog-path="exploreAiCatalogPath"
      :show-chat-disabled-nav="shouldShowBlockedState"
      @handle-tab-toggle="handleTabToggle"
      @new-chat="() => handleTabToggle('new')"
      @new-chat-error="handleNewChatError"
    />
  </div>
</template>
