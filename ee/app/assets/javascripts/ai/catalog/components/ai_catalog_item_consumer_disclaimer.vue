<script>
import { GlAlert, GlSprintf } from '@gitlab/ui';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import { FLOW_TRIGGER_TYPE_SCHEDULE } from 'ee/ai/duo_agents_platform/constants';
import {
  AI_CATALOG_TYPE_AGENT,
  AI_CATALOG_TYPE_FLOW,
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
  AI_CATALOG_ITEM_CONSUMER_DISCLAIMER_TEXTS,
} from '../constants';

export default {
  name: 'AiCatalogItemConsumerDisclaimer',
  components: {
    GlAlert,
    GlSprintf,
    HelpPageLink,
  },
  props: {
    itemType: {
      type: String,
      required: true,
      validator: (value) =>
        [AI_CATALOG_TYPE_AGENT, AI_CATALOG_TYPE_FLOW, AI_CATALOG_TYPE_THIRD_PARTY_FLOW].includes(
          value,
        ),
    },
    canEnable: {
      type: Boolean,
      required: false,
      default: false,
    },
    triggerTypes: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  computed: {
    disclaimerTexts() {
      return AI_CATALOG_ITEM_CONSUMER_DISCLAIMER_TEXTS[this.itemType];
    },
    isAgent() {
      return this.itemType === AI_CATALOG_TYPE_AGENT;
    },
    hasScheduledTrigger() {
      return this.triggerTypes.includes(FLOW_TRIGGER_TYPE_SCHEDULE.value);
    },
    hasEventTrigger() {
      return this.triggerTypes.some((type) => type !== FLOW_TRIGGER_TYPE_SCHEDULE.value);
    },
    // Returns null when no trigger is selected, so nothing renders until there is
    // something to describe.
    flowDisclaimer() {
      if (this.hasScheduledTrigger && this.hasEventTrigger) {
        return this.disclaimerTexts.combinedAccess;
      }
      if (this.hasScheduledTrigger) {
        return this.disclaimerTexts.scheduleAccess;
      }
      if (this.hasEventTrigger) {
        return this.disclaimerTexts.compositeIdentity;
      }
      return null;
    },
  },
};
</script>

<template>
  <div v-if="canEnable" class="gl-text-subtle">
    <ul v-if="isAgent" class="gl-mb-0 gl-pl-5">
      <li>{{ disclaimerTexts.enabledForMembers }}</li>
      <li>{{ disclaimerTexts.projectAccess }}</li>
    </ul>
    <p v-else-if="flowDisclaimer" class="gl-mb-0">
      <gl-sprintf :message="flowDisclaimer">
        <template #link="{ content }">
          <help-page-link href="user/permissions" anchor="roles">{{ content }}</help-page-link>
        </template>
        <template #ci="{ content }">
          <help-page-link href="user/duo_agent_platform/composite_identity">{{
            content
          }}</help-page-link>
        </template>
      </gl-sprintf>
    </p>
  </div>
  <gl-alert v-else variant="info" :dismissible="false">
    {{ disclaimerTexts.restricted }}
  </gl-alert>
</template>
