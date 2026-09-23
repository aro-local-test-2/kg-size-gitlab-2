<script>
import CeOrganizationSettingsGeneralApp from '~/organizations/settings/general/components/app.vue';
import PolicyStoreSettings from './policy_store_settings.vue';

const POLICY_STORE_SETTINGS_ID = 'organization-settings-policy-store';

export default {
  name: 'OrganizationSettingsGeneralAppEE',
  components: { CeOrganizationSettingsGeneralApp, PolicyStoreSettings },
  inject: {
    policyStoreExperimentAvailable: { default: false },
  },
  POLICY_STORE_SETTINGS_ID,
};
</script>

<template>
  <ce-organization-settings-general-app>
    <template #ee-settings-sections="{ expandedProp, onToggleExpand }">
      <policy-store-settings
        v-if="policyStoreExperimentAvailable"
        :id="$options.POLICY_STORE_SETTINGS_ID"
        :expanded="expandedProp($options.POLICY_STORE_SETTINGS_ID)"
        @toggle-expand="onToggleExpand($options.POLICY_STORE_SETTINGS_ID, $event)"
      />
    </template>
  </ce-organization-settings-general-app>
</template>
