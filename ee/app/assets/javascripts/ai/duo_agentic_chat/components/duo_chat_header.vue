<script>
import { GlAvatar, GlTooltipDirective, GlSkeletonLoader } from '@gitlab/ui';
import { agentAvatarEntityId } from 'ee/ai/utils';
import { DUO_CHAT_VIEWS } from 'ee/ai/constants';
import { s__ } from '~/locale';
import DuoChatAlerts from './duo_chat_alerts.vue';

export const i18n = {
  CHAT_TITLE: s__('DuoChat|GitLab Duo Chat'),
};

export default {
  name: 'DuoChatHeader',
  components: {
    DuoChatAlerts,
    GlAvatar,
    GlSkeletonLoader,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    title: {
      type: String,
      required: false,
      default: i18n.CHAT_TITLE,
    },
    agentId: {
      type: String,
      required: false,
      default: null,
    },
    agentAvatarUrl: {
      type: String,
      required: false,
      default: null,
    },
    error: {
      type: String,
      required: false,
      default: '',
    },
    info: {
      type: String,
      required: false,
      default: '',
    },
    currentView: {
      type: String,
      required: true,
    },
  },
  computed: {
    showSubheader() {
      return this.currentView !== DUO_CHAT_VIEWS.LIST;
    },
    avatarEntityId() {
      // GlAvatar derives its identicon color from `entityId` (entityId % 7 + 1), not `entityName`.
      // Without an agent id it defaults to 0, so every avatar resolves to the same color (bg1/red).
      return agentAvatarEntityId(this.agentId);
    },
  },
  i18n,
};
</script>

<template>
  <header
    data-testid="chat-header"
    class="gl-sticky gl-top-0 gl-z-9999 gl-shrink-0 gl-bg-default gl-p-0"
  >
    <div
      v-if="showSubheader"
      class="drawer-title gl-border-b gl-flex gl-items-center gl-justify-start gl-gap-4 gl-px-4 gl-pb-2 gl-pt-2"
      data-testid="chat-subheader"
    >
      <div class="gl-flex gl-grow gl-items-center gl-gap-3">
        <gl-avatar
          v-if="agentId"
          :size="32"
          :entity-id="avatarEntityId"
          :entity-name="title"
          :src="agentAvatarUrl"
          shape="circle"
          class="gl-shrink-0"
        />
        <div v-else class="gl-h-7 gl-w-7 gl-shrink-0" data-testid="agent-avatar-skeleton">
          <gl-skeleton-loader :width="32" :height="32">
            <circle cx="16" cy="16" r="16" />
          </gl-skeleton-loader>
        </div>
        <div class="gl-flex gl-flex-col gl-justify-center">
          <h3 class="gl-my-0 gl-line-clamp-1 gl-text-lg gl-text-default gl-break-anywhere">
            {{ title }}
          </h3>
        </div>
      </div>
      <div class="gl-flex gl-gap-3">
        <slot name="subheader"></slot>
      </div>
    </div>

    <duo-chat-alerts :info="info" :error="error" />
  </header>
</template>
