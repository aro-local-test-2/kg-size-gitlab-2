<script>
import { GlButton, GlDisclosureDropdown, GlTooltipDirective, GlSkeletonLoader } from '@gitlab/ui';
import { __, sprintf } from '~/locale';
import { copyToClipboard } from '~/lib/utils/copy_to_clipboard';
import showGlobalToast from '~/vue_shared/plugins/global_toast';
import {
  AGENTIC_CHAT_SHOW_ROUTE,
  AGENTIC_CHAT_HISTORY_ROUTE,
  CLASSIC_CHAT_SHOW_ROUTE,
  CLASSIC_CHAT_HISTORY_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import PanelActions from '~/vue_shared/components/panel_actions.vue';
import panelTitleQuery from '../graphql/panel_title.query.graphql';

const CONVERSATION_LIST_ROUTES = [AGENTIC_CHAT_HISTORY_ROUTE, CLASSIC_CHAT_HISTORY_ROUTE];

export default {
  name: 'AiContentContainer',
  components: {
    GlButton,
    GlDisclosureDropdown,
    GlSkeletonLoader,
    PanelActions,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  i18n: {
    closeButtonLabel: __('Close panel'),
    moreOptionsLabel: __('More options'),
    copySessionIdTooltip: __('Copy Chat Session ID: %{id}'),
    sessionIdCopiedToast: __('Session ID copied to clipboard'),
    sessionIdCopyFailedToast: __('Could not copy session ID'),
  },
  props: {
    title: {
      type: String,
      required: true,
    },
    showBackButton: {
      type: Boolean,
      required: false,
      default: false,
    },
    isMaximized: {
      type: Boolean,
      required: true,
    },
    showLoadingState: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['close-panel', 'go-back', 'toggle-maximize'],
  apollo: {
    panelTitleState: {
      query: panelTitleQuery,
      update(data) {
        return data;
      },
    },
  },
  data() {
    return {
      currentTitle: null,
      currentSubtitle: null,
      panelTitleState: null,
      sessionId: null,
      isSessionDropdownVisible: false,
    };
  },
  computed: {
    panelTitle() {
      return this.panelTitleState?.panelTitle || '';
    },
    goBackTitle() {
      return __('Go back');
    },
    maximizeButtonLabel() {
      return this.isMaximized ? __('Minimize panel') : __('Maximize panel');
    },
    showSessionId() {
      return this.sessionId && this.$route?.name === AGENTIC_CHAT_SHOW_ROUTE;
    },
    // Classic chat hides its own chat header, so it has no slot to render the
    // session menu into. Render it in the panel header instead.
    showPanelSessionId() {
      return this.sessionId && this.$route?.name === CLASSIC_CHAT_SHOW_ROUTE;
    },
    sessionText() {
      return sprintf(this.$options.i18n.copySessionIdTooltip, { id: this.sessionId });
    },
    sessionIdItems() {
      return [
        {
          text: this.sessionText,
          action: () => {
            this.copySessionIdToClipboard();
          },
        },
      ];
    },
    showSessionDropdownTooltip() {
      return !this.isSessionDropdownVisible ? this.$options.i18n.moreOptionsLabel : '';
    },
    displayTitle() {
      return this.panelTitle || this.currentTitle || this.title;
    },
  },
  watch: {
    title: {
      handler() {
        this.currentTitle = null;
        this.currentSubtitle = null;
        this.resetPanelOverrides();
      },
    },
    '$route.path': {
      handler() {
        this.resetPanelOverrides();
      },
    },
  },
  methods: {
    resetPanelOverrides() {
      this.panelTitleState = null;
    },
    handleGoBack() {
      this.$emit('go-back');
    },
    handleTitleChange(title) {
      // A child title describes a single conversation, so the route-derived
      // heading wins on conversation-list routes.
      if (CONVERSATION_LIST_ROUTES.includes(this.$route?.name)) {
        return;
      }

      this.currentTitle = title || null;
    },
    handleSubtitleChange(subtitle) {
      this.currentSubtitle = subtitle || null;
    },
    handleSessionIdChanged(sessionId) {
      this.sessionId = sessionId;
    },
    showSessionDropdown() {
      this.isSessionDropdownVisible = true;
    },
    hideSessionDropdown() {
      this.isSessionDropdownVisible = false;
    },
    async copySessionIdToClipboard() {
      try {
        await copyToClipboard(this.sessionId);
        showGlobalToast(this.$options.i18n.sessionIdCopiedToast);
      } catch {
        showGlobalToast(this.$options.i18n.sessionIdCopyFailedToast);
      }
    },
  },
};
</script>

<template>
  <aside
    id="ai-panel-portal"
    :aria-label="title"
    class="ai-panel paneled-view js-paneled-view [contain:strict]"
  >
    <div class="panel-header">
      <div class="panel-header-inner">
        <div class="panel-header-inner-text">
          <gl-button
            v-gl-tooltip.bottom
            class="lg:gl-flex"
            :class="{ '!gl-hidden': !showBackButton }"
            icon="go-back"
            category="tertiary"
            :aria-label="goBackTitle"
            :title="goBackTitle"
            data-testid="content-container-back-button"
            @click="handleGoBack"
          />
          <div class="gl-flex gl-w-full gl-flex-col gl-self-center">
            <gl-skeleton-loader v-if="showLoadingState && !panelTitle" :lines="1" />
            <div v-else>
              <h3 class="gl-m-0 gl-truncate gl-text-sm" data-testid="content-container-title">
                {{ displayTitle }}
              </h3>
              <h4
                v-if="currentSubtitle"
                class="gl-m-0 gl-truncate gl-text-sm gl-font-normal gl-text-subtle"
                data-testid="content-container-subtitle"
              >
                {{ currentSubtitle }}
              </h4>
            </div>
          </div>
        </div>

        <panel-actions>
          <gl-disclosure-dropdown
            v-if="showPanelSessionId"
            v-gl-tooltip="showSessionDropdownTooltip"
            icon="ellipsis_v"
            category="tertiary"
            text-sr-only
            size="small"
            :toggle-text="$options.i18n.moreOptionsLabel"
            :items="sessionIdItems"
            no-caret
            data-testid="content-container-session-dropdown"
            @shown="showSessionDropdown"
            @hidden="hideSessionDropdown"
          />

          <template #panel-controls>
            <gl-button
              v-gl-tooltip.bottom
              class="gl-hidden lg:gl-flex"
              :icon="isMaximized ? 'minimize' : 'maximize'"
              category="tertiary"
              size="small"
              :aria-label="maximizeButtonLabel"
              :title="maximizeButtonLabel"
              data-testid="content-container-maximize-button"
              @click="$emit('toggle-maximize')"
            />
            <gl-button
              v-gl-tooltip.bottom
              icon="close"
              category="tertiary"
              size="small"
              :aria-label="$options.i18n.closeButtonLabel"
              :title="$options.i18n.closeButtonLabel"
              data-testid="content-container-close-button"
              @click="$emit('close-panel', false)"
            />
          </template>
        </panel-actions>
      </div>
    </div>
    <div
      class="panel-content-inner ai-panel-content-inner gl-flex gl-min-h-0 gl-grow gl-flex-col"
      data-testid="ai-panel-content"
    >
      <slot
        name="active-tab"
        :show-session-id="showSessionId"
        :show-session-dropdown-tooltip="showSessionDropdownTooltip"
        :toggle-text="$options.i18n.moreOptionsLabel"
        :items="sessionIdItems"
        :show-session-dropdown="showSessionDropdown"
        :hide-session-dropdown="hideSessionDropdown"
        :handle-title-change="handleTitleChange"
        :handle-subtitle-change="handleSubtitleChange"
        :handle-session-id-changed="handleSessionIdChanged"
      ></slot>
    </div>
  </aside>
</template>
