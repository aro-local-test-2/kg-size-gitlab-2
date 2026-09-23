<script>
import { DuoChatLoader } from '@gitlab/duo-ui';
import { s__ } from '~/locale';
import { TURN_PROGRESS } from '../constants';
import { isCompactPromptMessage } from '../utils/messages_utils';
import CompactingIndicator from './compacting_indicator.vue';

export default {
  name: 'TurnProgress',
  components: {
    CompactingIndicator,
    DuoChatLoader,
  },
  props: {
    /**
     * Whether a turn is in flight. Nothing is reported without one, so cancelling or
     * reloading retires the report rather than stranding it on screen.
     */
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * The raw message log, not the transcript the chat renders: the compact plugin
     * drops the `/compact` prompt from what renders, so the message the user sent is
     * the only surviving record that this turn is a compaction.
     */
    messages: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  computed: {
    progress() {
      if (!this.isLoading) return TURN_PROGRESS.NONE;

      return isCompactPromptMessage(this.messages.at(-1))
        ? TURN_PROGRESS.COMPACTING
        : TURN_PROGRESS.RESPONSE;
    },
  },
  i18n: {
    // Mirrors the chat's own title, which is what the view passed before this component
    // owned the loader. duo-ui's default is the shorter "GitLab Duo".
    TOOL_NAME: s__('DuoAgenticChat|GitLab Duo Agentic Chat'),
  },
  TURN_PROGRESS,
};
</script>

<template>
  <duo-chat-loader
    v-if="progress === $options.TURN_PROGRESS.RESPONSE"
    :tool-name="$options.i18n.TOOL_NAME"
    data-testid="response-loader"
  />
  <compacting-indicator v-else-if="progress === $options.TURN_PROGRESS.COMPACTING" />
</template>
