<script>
import { GlAvatar, GlAvatarLink, GlTooltipDirective } from '@gitlab/ui';
import { getNumericId } from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'AgentFlowTriggeredUser',
  components: {
    GlAvatar,
    GlAvatarLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    user: {
      required: false,
      type: Object,
      default: () => ({}),
    },
  },
  computed: {
    userId() {
      return getNumericId(this.user?.id);
    },
    userUsername() {
      return this.user?.username || '';
    },
    userWebUrl() {
      return this.user?.webUrl || '';
    },
    userName() {
      return this.user?.name || '';
    },
    userAvatarUrl() {
      return this.user?.avatarUrl || '';
    },
  },
};
</script>
<template>
  <span class="gl-inline-flex gl-items-center gl-gap-2">
    <gl-avatar-link
      v-gl-tooltip.bottom
      :href="userWebUrl"
      :data-user-id="userId"
      :data-username="userUsername"
      :title="userName"
      class="js-user-link gl-inline-flex gl-items-center gl-gap-2 gl-text-inherit gl-no-underline hover:gl-text-link hover:gl-underline"
    >
      <gl-avatar :src="userAvatarUrl" :alt="userName" :label="userName" :size="16" />
      @{{ userUsername }}
    </gl-avatar-link>
  </span>
</template>
