<script>
import { GlButton, GlIcon, GlTableLite } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';

export default {
  name: 'ScanTriggersDetail',
  components: {
    CrudComponent,
    GlButton,
    GlIcon,
    GlTableLite,
  },
  props: {
    profileHelpLink: {
      type: String,
      required: false,
      default: () => '',
    },
    triggers: {
      type: Array,
      required: true,
    },
  },
  data() {
    return {
      collapsed: true,
    };
  },
  methods: {
    variablesLabel(title) {
      return sprintf(s__('ScanProfiles|Analyzer settings for %{trigger}'), { trigger: title });
    },
    variableRows(trigger) {
      return trigger.variableRows ?? [];
    },
  },
  fields: [
    { key: 'setting', label: s__('ScanProfiles|Variable') },
    { key: 'value', label: s__('ScanProfiles|Value') },
  ],
};
</script>

<template>
  <div>
    <crud-component
      v-for="trigger in triggers"
      :key="trigger.anchor"
      :is-collapsible="true"
      :collapsed="collapsed"
      :description="trigger.subtitle"
      :anchor-id="trigger.anchor"
      body-class="!gl-p-3"
    >
      <template #title>
        <gl-icon v-if="trigger.icon" :name="trigger.icon" />
        {{ trigger.title }}
      </template>

      <p class="gl-mb-4">
        {{ trigger.description }}
      </p>

      <div v-if="trigger.targetBranch || trigger.scope || trigger.results" class="gl-mb-4">
        <p v-if="trigger.targetBranch" class="gl-m-0 gl-mb-1">
          <strong>{{ s__('ScanProfiles|Target branch:') }}</strong> {{ trigger.targetBranch }}
        </p>
        <p v-if="trigger.scope" class="gl-m-0 gl-mb-1">
          <strong>{{ s__('ScanProfiles|Scope:') }}</strong> {{ trigger.scope }}
        </p>
        <p v-if="trigger.results" class="gl-m-0 gl-mb-1">
          <strong>{{ s__('ScanProfiles|Results:') }}</strong> {{ trigger.results }}
        </p>
      </div>

      <gl-table-lite
        v-if="variableRows(trigger).length"
        :items="variableRows(trigger)"
        :fields="$options.fields"
        stacked="sm"
        table-class="!gl-mb-4"
        :aria-label="variablesLabel(trigger.title)"
        data-testid="trigger-variables-table"
      >
        <template #cell(setting)="{ item }">
          <code>{{ item.setting }}</code>
        </template>
        <template #cell(value)="{ item }">
          <span class="gl-break-anywhere">{{ item.value }}</span>
        </template>
      </gl-table-lite>

      <gl-button
        v-if="trigger.helpLink || profileHelpLink"
        variant="default"
        size="small"
        icon="external-link"
        :href="trigger.helpLink || profileHelpLink"
        target="_blank"
      >
        {{ s__('ScanProfiles|View documentation') }}
      </gl-button>
    </crud-component>
  </div>
</template>
