import { SCAN_PROFILE_TYPE_SECRET_DETECTION } from '~/security_configuration/constants';

// Scan profile configuration is stored per trigger, so there is nowhere to put a profile-level value.
// Until profile-level storage exists, fake it by writing the same configuration to every trigger that accepts one.

const CONFIGURATION_INPUT_KEYS = {
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: 'secretDetection',
};

// Mirrors UNCONFIGURABLE_TRIGGER_TYPES_BY_SCAN_TYPE in ee/app/models/security/scan_profile_trigger.rb
const UNCONFIGURABLE_TRIGGER_TYPES = {
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: ['GIT_PUSH_EVENT'],
};

export const isTriggerConfigurable = (scanType, triggerType) =>
  Boolean(CONFIGURATION_INPUT_KEYS[scanType]) &&
  !(UNCONFIGURABLE_TRIGGER_TYPES[scanType] ?? []).includes(triggerType);

/**
 * Builds the `triggers` input for the `securityScanProfileCreate` and
 * `securityScanProfileUpdate` mutations.
 *
 * @param {string} scanType Scan type of the profile.
 * @param {string[]} [enabledTriggers] Full desired set of trigger types; any type left out is
 *   destroyed by the mutation rather than disabled.
 * @param {Object} [profileConfiguration] Values applied to every configurable trigger.
 * @param {Object} [triggerConfigurations] Values keyed by trigger type; these win key by key over
 *   the matching `profileConfiguration` ones.
 * @returns {Object[]} One entry per enabled trigger, bare where no configuration applies.
 */
export const mapScanProfileVariables = ({
  scanType,
  enabledTriggers = [],
  profileConfiguration,
  triggerConfigurations = {},
}) => {
  const configurationKey = CONFIGURATION_INPUT_KEYS[scanType];

  return enabledTriggers.map((triggerType) => {
    if (!isTriggerConfigurable(scanType, triggerType)) {
      return { triggerType };
    }

    const configuration = { ...profileConfiguration, ...triggerConfigurations[triggerType] };

    if (!Object.keys(configuration).length) {
      return { triggerType };
    }

    return { triggerType, configuration: { [configurationKey]: configuration } };
  });
};

export const buildScanProfileUpdateInput = ({
  profileId,
  scanType,
  enabledTriggers,
  profileConfiguration,
  triggerConfigurations,
  stripDefaults = false,
}) => ({
  id: profileId,
  stripDefaults,
  triggers: mapScanProfileVariables({
    scanType,
    enabledTriggers,
    profileConfiguration,
    triggerConfigurations,
  }),
});

export const buildScanProfileCreateInput = ({
  namespaceId,
  scanType,
  name,
  description,
  enabledTriggers,
  profileConfiguration,
  triggerConfigurations,
  stripDefaults = false,
}) => ({
  namespaceId,
  scanType,
  name,
  description,
  stripDefaults,
  triggers: mapScanProfileVariables({
    scanType,
    enabledTriggers,
    profileConfiguration,
    triggerConfigurations,
  }),
});

export const readScanProfileTriggers = (triggerSettings = []) => ({
  enabledTriggers: triggerSettings.map(({ triggerType }) => triggerType),
  triggerConfigurations: Object.fromEntries(
    triggerSettings
      .map(({ triggerType, configuration }) => [
        triggerType,
        Object.fromEntries(
          Object.entries(configuration ?? {}).filter(
            ([key, value]) => key !== '__typename' && value !== null,
          ),
        ),
      ])
      .filter(([, values]) => Object.keys(values).length),
  ),
});
