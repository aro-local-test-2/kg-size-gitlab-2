<script>
import { GlIcon, GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import {
  SESSION_RUNNING_STATUSES,
  SESSION_INPUT_REQUIRED_STATUSES,
  SESSION_FAILED_STATUSES,
  SESSION_STATUS_PAUSED,
  SESSION_STATUS_FINISHED,
} from 'ee/ai/duo_agents_platform/constants';

const VIEW_SESSION_LABEL = s__('DuoAgentsPlatform|View session #%{sessionId}');

const NOTE_SESSION_BAR_STATUS_CONFIGS = [
  {
    matches: (status) => SESSION_FAILED_STATUSES.has(status),
    phrase: s__('DuoAgentsPlatform|%{agentName} was unable to complete your request'),
    icon: { name: 'error', variant: 'danger' },
  },
  {
    matches: (status) => status === SESSION_STATUS_PAUSED,
    phrase: s__('DuoAgentsPlatform|%{agentName} is paused'),
    icon: { name: 'pause', variant: 'subtle' },
  },
  {
    matches: (status) => SESSION_INPUT_REQUIRED_STATUSES.has(status),
    phrase: s__('DuoAgentsPlatform|%{agentName} needs input'),
    icon: { name: 'warning-solid', variant: 'warning' },
  },
  {
    matches: (status) => SESSION_RUNNING_STATUSES.has(status),
    phrases: [
      s__('DuoAgentsPlatform|%{agentName} is investigating...'),
      s__('DuoAgentsPlatform|%{agentName} is thinking...'),
      s__('DuoAgentsPlatform|%{agentName} is pondering...'),
      s__('DuoAgentsPlatform|%{agentName} is working...'),
    ],
    icon: null,
  },
];

export default {
  name: 'NoteSessionBar',
  components: { GlIcon, GlLoadingIcon, GlSprintf },
  props: {
    agentName: {
      type: String,
      required: true,
    },
    sessionId: {
      type: String,
      required: true,
    },
    isReply: {
      type: Boolean,
      required: true,
    },
    status: {
      type: String,
      required: false,
      default: null,
    },
  },
  data() {
    const runningConfig = NOTE_SESSION_BAR_STATUS_CONFIGS.find(({ phrases }) => phrases);
    return {
      runningPhrase:
        runningConfig.phrases[Math.floor(Math.random() * runningConfig.phrases.length)],
    };
  },
  computed: {
    hideSessionBar() {
      return !this.status || this.status === SESSION_STATUS_FINISHED;
    },
    activeConfig() {
      return NOTE_SESSION_BAR_STATUS_CONFIGS.find(({ matches }) => matches(this.status));
    },
    isRunning() {
      return SESSION_RUNNING_STATUSES.has(this.status);
    },
    showStatusIcon() {
      return Boolean(this.activeConfig?.icon);
    },
    statusIcon() {
      return this.activeConfig?.icon ?? null;
    },
    phraseTemplate() {
      if (!this.activeConfig) return null;
      return this.isRunning ? this.runningPhrase : this.activeConfig.phrase;
    },
    numericSessionId() {
      return getIdFromGraphQLId(this.sessionId);
    },
    viewSessionLabel() {
      return sprintf(VIEW_SESSION_LABEL, { sessionId: this.numericSessionId });
    },
  },
  methods: {
    openSession() {
      eventHub.$emit(SHOW_SESSION, { id: this.numericSessionId });
    },
  },
};
</script>

<template>
  <div
    v-if="!hideSessionBar"
    class="gl-mt-3 gl-flex"
    :class="
      isReply
        ? 'gl-mb-3 gl-mr-3'
        : 'gl-border-t gl-border-subtle gl-border-t-solid dark:gl-border-t-section'
    "
    data-testid="note-session-bar-wrapper"
  >
    <button
      type="button"
      :aria-label="viewSessionLabel"
      :class="[
        'gl-flex gl-w-full gl-items-center gl-justify-between gl-rounded-base gl-border-solid gl-border-subtle gl-bg-transparent gl-px-4 gl-py-3 gl-text-default hover:gl-bg-alpha-dark-8 hover:gl-text-default dark:hover:gl-bg-alpha-light-8',
        isReply ? 'gl-border-1' : 'gl-border-none',
      ]"
      data-testid="note-session-bar"
      @click="openSession"
    >
      <span class="gl-flex gl-items-center gl-gap-2">
        <gl-loading-icon
          v-if="isRunning"
          size="sm"
          variant="dots"
          inline
          data-testid="note-session-bar-spinner"
        />
        <gl-icon
          v-else-if="showStatusIcon"
          :name="statusIcon.name"
          :size="14"
          :variant="statusIcon.variant"
          data-testid="note-session-bar-status-icon"
        />
        <span data-testid="note-session-bar-text" class="gl-ml-3">
          <gl-sprintf :message="phraseTemplate">
            <template #agentName>
              <strong>{{ agentName }}</strong>
            </template>
          </gl-sprintf>
        </span>
      </span>
      <gl-icon name="chevron-right" :size="14" data-testid="note-session-bar-chevron" />
    </button>
  </div>
</template>
