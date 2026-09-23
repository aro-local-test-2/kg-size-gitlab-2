import { isEqual } from 'lodash-es';
import { s__ } from '~/locale';
import {
  SCAN_PROFILE_CATEGORIES,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
  SCAN_TRIGGER_DEFINITIONS,
} from '~/security_configuration/constants';

export const scanTypeName = (scanType) => SCAN_PROFILE_CATEGORIES[scanType]?.name || scanType;

export const scanTypeHelpLink = (scanType) => SCAN_PROFILE_CATEGORIES[scanType]?.helpLink;

export const resolveTriggers = (triggers) =>
  (triggers ?? []).map((triggerType) => SCAN_TRIGGER_DEFINITIONS[triggerType]).filter(Boolean);

export const managedByLabel = ({ gitlabRecommended }) =>
  gitlabRecommended ? s__('ScanProfiles|GitLab') : s__('ScanProfiles|Custom');

const SECRET_DETECTION_CONFIGURATION_TYPE = 'SecretDetectionConfiguration';
const UNCONFIGURABLE_TRIGGER_TYPES_BY_SCAN_TYPE = {
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: ['GIT_PUSH_EVENT'],
};
export const isTriggerConfigurable = (scanType, triggerType) =>
  !(UNCONFIGURABLE_TRIGGER_TYPES_BY_SCAN_TYPE[scanType] ?? []).includes(triggerType);

const configuredTriggerSettings = (triggerSettings = []) =>
  triggerSettings.filter((triggerSetting) => {
    const { __typename: typeName } = triggerSetting.configuration ?? {};
    return typeName === SECRET_DETECTION_CONFIGURATION_TYPE;
  });

const isSetConfigurationValue = (value) => {
  if (Array.isArray(value)) return value.length > 0;
  return value !== null && value !== undefined && value !== '';
};

/**
 * Classify a profile's per-trigger configuration into one row per setting.
 *
 * @param {string} scanType Scan type of the profile.
 * @param {string[]} [triggers] Enabled trigger types.
 * @param {Object[]} [triggerSettings] One `{ triggerType, configuration }` per trigger.
 * @returns {{profileRows: Object[], rowsByTrigger: Map, hasConfigurableTriggers: boolean}}
 *   `profileRows` holds one entry per set setting. Each carries `triggerValues`, one
 *   `{ triggerType, value }` per enabled trigger that sets it, and either the `value` every
 *   enabled configurable trigger shares or `varies: true` where they disagree. A trigger that
 *   leaves a setting unset is absent from `triggerValues` rather than present with no value.
 *   `rowsByTrigger` maps each enabled trigger type to its own `{ setting, value }` rows, every
 *   setting it sets rather than only the ones that differ.
 *   `hasConfigurableTriggers` is false when no enabled trigger accepts configuration.
 */
export const classifyConfigurationVariables = ({
  scanType,
  triggers = [],
  triggerSettings = [],
} = {}) => {
  const enabledTypes = triggers.filter((triggerType) =>
    isTriggerConfigurable(scanType, triggerType),
  );
  const configurationByTrigger = new Map(
    configuredTriggerSettings(triggerSettings).map(({ triggerType, configuration }) => [
      triggerType,
      configuration,
    ]),
  );
  const settings = [
    ...new Set(
      enabledTypes.flatMap((triggerType) =>
        Object.keys(configurationByTrigger.get(triggerType) ?? {}).filter(
          (key) => key !== '__typename',
        ),
      ),
    ),
  ];

  const profileRows = settings
    .map((setting) => ({
      setting,
      triggerValues: enabledTypes
        .map((triggerType) => ({
          triggerType,
          value: configurationByTrigger.get(triggerType)?.[setting],
        }))
        .filter(({ value }) => isSetConfigurationValue(value)),
    }))
    .filter(({ triggerValues }) => triggerValues.length > 0)
    .map((row) => {
      const sharesOneValue =
        row.triggerValues.length === enabledTypes.length &&
        row.triggerValues.every(({ value }) => isEqual(value, row.triggerValues[0].value));

      return sharesOneValue
        ? { ...row, value: row.triggerValues[0].value }
        : { ...row, varies: true };
    });

  const rowsByTrigger = new Map(
    enabledTypes.map((triggerType) => [
      triggerType,
      settings
        .map((setting) => ({
          setting,
          value: configurationByTrigger.get(triggerType)?.[setting],
        }))
        .filter(({ value }) => isSetConfigurationValue(value)),
    ]),
  );

  return { profileRows, rowsByTrigger, hasConfigurableTriggers: enabledTypes.length > 0 };
};
