import createResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql.json';
import fanOutResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.json';
import mergedResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.merged.json';
import perTriggerResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.per_trigger.json';
import toggledOffResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.toggled_off.json';
import createMockApollo from 'helpers/mock_apollo_helper';
import securityScanProfileCreateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql';
import securityScanProfileUpdateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql';
import {
  isTriggerConfigurable,
  mapScanProfileVariables,
  buildScanProfileUpdateInput,
  buildScanProfileCreateInput,
  readScanProfileTriggers,
} from 'ee/security_configuration/graphql/scan_profiles/map_scan_profile_variables';

const SCAN_TYPE = 'SECRET_DETECTION';
const PROFILE_ID = 'gid://gitlab/Security::ScanProfile/10';
const NAMESPACE_ID = 'gid://gitlab/Group/7';
const PREFIX = 'registry.gitlab.com/security-products';
const ALL_TRIGGERS = ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE', 'GIT_PUSH_EVENT'];
const PROFILE_CONFIGURATION = { secureAnalyzersPrefix: PREFIX, historicScan: true };

const mutate = async ({ mutation, response, input }) => {
  const handler = jest.fn().mockResolvedValue(response);
  const { defaultClient } = createMockApollo([[mutation, handler]]);
  const { data } = await defaultClient.mutate({ mutation, variables: { input } });

  return { data, handler };
};

const update = async ({ response, input }) => {
  const { data, handler } = await mutate({
    mutation: securityScanProfileUpdateMutation,
    response,
    input,
  });

  return { handler, scanProfile: data.securityScanProfileUpdate.scanProfile };
};

const updateInput = (overrides = {}) =>
  buildScanProfileUpdateInput({
    profileId: PROFILE_ID,
    scanType: SCAN_TYPE,
    enabledTriggers: ALL_TRIGGERS,
    profileConfiguration: PROFILE_CONFIGURATION,
    ...overrides,
  });

it('treats every secret detection trigger except GIT_PUSH_EVENT as configurable', () => {
  expect(isTriggerConfigurable(SCAN_TYPE, 'MERGE_REQUEST_PIPELINE')).toBe(true);
  expect(isTriggerConfigurable(SCAN_TYPE, 'DEFAULT_BRANCH_PIPELINE')).toBe(true);
  expect(isTriggerConfigurable(SCAN_TYPE, 'GIT_PUSH_EVENT')).toBe(false);
});

it('sends every enabled trigger bare when no variables are set', () => {
  const triggers = mapScanProfileVariables({ scanType: SCAN_TYPE, enabledTriggers: ALL_TRIGGERS });

  expect(triggers).toEqual([
    { triggerType: 'MERGE_REQUEST_PIPELINE' },
    { triggerType: 'DEFAULT_BRANCH_PIPELINE' },
    { triggerType: 'GIT_PUSH_EVENT' },
  ]);
});

it('fans profile-level variables out to each configurable trigger', async () => {
  const input = updateInput();

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: fanOutResponse, input });
  const { enabledTriggers, triggerConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(enabledTriggers).toHaveLength(3);
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: PROFILE_CONFIGURATION,
    DEFAULT_BRANCH_PIPELINE: PROFILE_CONFIGURATION,
  });
});

it('keeps trigger-level variables with their own trigger', async () => {
  const triggerConfigurations = {
    MERGE_REQUEST_PIPELINE: { historicScan: false, excludedPaths: ['spec/fixtures/**'] },
    DEFAULT_BRANCH_PIPELINE: { historicScan: true },
  };
  const input = updateInput({ profileConfiguration: undefined, triggerConfigurations });

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: perTriggerResponse, input });
  const { triggerConfigurations: storedConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: {
            secretDetection: { historicScan: false, excludedPaths: ['spec/fixtures/**'] },
          },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: { historicScan: true } },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(storedConfigurations).toEqual(triggerConfigurations);
});

it('lets a trigger-level value override the profile-level one key by key', async () => {
  const input = updateInput({
    triggerConfigurations: {
      MERGE_REQUEST_PIPELINE: { historicScan: false },
      GIT_PUSH_EVENT: { historicScan: true },
    },
  });

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: mergedResponse, input });
  const { triggerConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: {
            secretDetection: { secureAnalyzersPrefix: PREFIX, historicScan: false },
          },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: { secureAnalyzersPrefix: PREFIX, historicScan: false },
    DEFAULT_BRANCH_PIPELINE: PROFILE_CONFIGURATION,
  });
});

it('drops a toggled-off trigger from the payload and sees it destroyed in the response', async () => {
  const input = updateInput({ enabledTriggers: ['MERGE_REQUEST_PIPELINE', 'GIT_PUSH_EVENT'] });

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: toggledOffResponse, input });
  const { enabledTriggers, triggerConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });

  expect(enabledTriggers).toHaveLength(2);
  expect(enabledTriggers).not.toContain('DEFAULT_BRANCH_PIPELINE');
  expect(triggerConfigurations).toEqual({ MERGE_REQUEST_PIPELINE: PROFILE_CONFIGURATION });
});

it('creates a profile with its name, description and the same trigger mapping', async () => {
  const input = buildScanProfileCreateInput({
    namespaceId: NAMESPACE_ID,
    scanType: SCAN_TYPE,
    name: 'Nightly secret detection',
    description: 'Scans the default branch overnight',
    enabledTriggers: ALL_TRIGGERS,
    profileConfiguration: PROFILE_CONFIGURATION,
  });

  const { data, handler } = await mutate({
    mutation: securityScanProfileCreateMutation,
    response: createResponse,
    input,
  });
  const { scanProfile } = data.securityScanProfileCreate;
  const { triggerConfigurations } = readScanProfileTriggers(scanProfile.triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      namespaceId: NAMESPACE_ID,
      scanType: SCAN_TYPE,
      name: 'Nightly secret detection',
      description: 'Scans the default branch overnight',
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(scanProfile).toMatchObject({
    name: 'Nightly secret detection',
    description: 'Scans the default branch overnight',
    scanType: SCAN_TYPE,
  });
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: PROFILE_CONFIGURATION,
    DEFAULT_BRANCH_PIPELINE: PROFILE_CONFIGURATION,
  });
});
