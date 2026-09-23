import initSettingsPanels from '~/settings_panels';
import { initSettingsToggles } from '~/group_settings/settings_toggles';
import { initGroupSecretsManagerSettings } from 'ee/groups/settings/permissions';

initSettingsPanels();
initSettingsToggles();
initGroupSecretsManagerSettings();
