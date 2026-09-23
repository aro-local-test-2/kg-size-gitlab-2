import {
  classifyConfigurationVariables,
  isTriggerConfigurable,
  managedByLabel,
  resolveTriggers,
  scanTypeHelpLink,
  scanTypeName,
} from 'ee/security_configuration/components/scan_profiles/utils';
import {
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

const MERGE_REQUEST = 'MERGE_REQUEST_PIPELINE';
const DEFAULT_BRANCH = 'DEFAULT_BRANCH_PIPELINE';
const GIT_PUSH = 'GIT_PUSH_EVENT';

const HISTORIC_SCAN = 'historicScan';
const EXCLUDED_PATHS = 'excludedPaths';

const buildConfiguration = (values) => ({
  __typename: 'SecretDetectionConfiguration',
  secureAnalyzersPrefix: null,
  imageSuffix: null,
  historicScan: null,
  logOptions: null,
  excludedPaths: null,
  rulesetGitReference: null,
  ...values,
});

const buildSetting = (triggerType, values) => ({
  triggerType,
  configuration: values ? buildConfiguration(values) : null,
});

const classify = ({ triggers, triggerSettings, scanType = SCAN_PROFILE_TYPE_SECRET_DETECTION }) =>
  classifyConfigurationVariables({ scanType, triggers, triggerSettings });

describe('scan profile utils', () => {
  describe('scanTypeName', () => {
    it('names a known scan type', () => {
      expect(scanTypeName(SCAN_PROFILE_TYPE_SECRET_DETECTION)).toBe('Secret detection');
    });

    it('falls back to the raw value for an unknown scan type', () => {
      expect(scanTypeName('NOT_A_SCANNER')).toBe('NOT_A_SCANNER');
    });
  });

  describe('scanTypeHelpLink', () => {
    it('links to the help page for a known scan type', () => {
      expect(scanTypeHelpLink(SCAN_PROFILE_TYPE_SAST)).toBe(
        '/help/user/application_security/sast/_index',
      );
    });

    it('has no link for an unknown scan type', () => {
      expect(scanTypeHelpLink('NOT_A_SCANNER')).toBeUndefined();
    });
  });

  describe('managedByLabel', () => {
    it.each([
      [true, 'GitLab'],
      [false, 'Custom'],
    ])('labels a profile with gitlabRecommended %s as %s', (gitlabRecommended, label) => {
      expect(managedByLabel({ gitlabRecommended })).toBe(label);
    });
  });

  describe('resolveTriggers', () => {
    it('resolves each trigger type to its definition', () => {
      const triggers = resolveTriggers(['MERGE_REQUEST_PIPELINE', 'GIT_PUSH_EVENT']);

      expect(triggers.map(({ anchor }) => anchor)).toEqual([
        'merge-request-pipeline',
        'secret-push-protection',
      ]);
    });

    it('drops trigger types with no definition', () => {
      const triggers = resolveTriggers(['MERGE_REQUEST_PIPELINE', 'NOT_A_TRIGGER']);

      expect(triggers.map(({ anchor }) => anchor)).toEqual(['merge-request-pipeline']);
    });

    it.each([null, undefined, []])('returns an empty list for %p', (triggers) => {
      expect(resolveTriggers(triggers)).toEqual([]);
    });
  });

  describe('isTriggerConfigurable', () => {
    it.each`
      scanType                              | triggerType      | expected
      ${SCAN_PROFILE_TYPE_SECRET_DETECTION} | ${MERGE_REQUEST} | ${true}
      ${SCAN_PROFILE_TYPE_SECRET_DETECTION} | ${GIT_PUSH}      | ${false}
      ${SCAN_PROFILE_TYPE_SECRET_DETECTION} | ${'FUTURE_TYPE'} | ${true}
      ${'SAST'}                             | ${GIT_PUSH}      | ${true}
    `('is $expected for $scanType and $triggerType', ({ scanType, triggerType, expected }) => {
      expect(isTriggerConfigurable(scanType, triggerType)).toBe(expected);
    });
  });

  describe('classifyConfigurationVariables', () => {
    describe('hasConfigurableTriggers', () => {
      it.each`
        description                            | triggers                     | expected
        ${'a configurable trigger is enabled'} | ${[MERGE_REQUEST, GIT_PUSH]} | ${true}
        ${'only the unconfigurable one is'}    | ${[GIT_PUSH]}                | ${false}
        ${'no trigger is enabled'}             | ${[]}                        | ${false}
      `('is $expected when $description', ({ triggers, expected }) => {
        expect(classify({ triggers, triggerSettings: [] }).hasConfigurableTriggers).toBe(expected);
      });
    });

    describe('when every configurable trigger is enabled', () => {
      const triggers = [MERGE_REQUEST, DEFAULT_BRANCH, GIT_PUSH];

      it('returns a shared value with a row per trigger', () => {
        const { profileRows } = classify({
          triggers,
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true }),
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
            buildSetting(GIT_PUSH, null),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            value: true,
            triggerValues: [
              { triggerType: MERGE_REQUEST, value: true },
              { triggerType: DEFAULT_BRANCH, value: true },
            ],
          },
        ]);
      });

      it('returns varies and a row per disagreeing trigger', () => {
        const { profileRows } = classify({
          triggers,
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: false }),
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            varies: true,
            triggerValues: [
              { triggerType: MERGE_REQUEST, value: false },
              { triggerType: DEFAULT_BRANCH, value: true },
            ],
          },
        ]);
      });

      it('treats set on one and unset on the other as varying', () => {
        const { profileRows } = classify({
          triggers,
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true }),
            buildSetting(DEFAULT_BRANCH, {}),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            varies: true,
            triggerValues: [{ triggerType: MERGE_REQUEST, value: true }],
          },
        ]);
      });
    });

    describe('when a configurable trigger is disabled', () => {
      it('ignores it and reports the enabled trigger value as the profile value', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, GIT_PUSH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true }),
            buildSetting(GIT_PUSH, null),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            value: true,
            triggerValues: [{ triggerType: MERGE_REQUEST, value: true }],
          },
        ]);
      });

      it('returns trigger values for the enabled triggers', () => {
        const { profileRows } = classify({
          triggers: [DEFAULT_BRANCH, GIT_PUSH],
          triggerSettings: [
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
            buildSetting(GIT_PUSH, { historicScan: false }),
          ],
        });

        expect(profileRows[0].triggerValues).toEqual([
          { triggerType: DEFAULT_BRANCH, value: true },
        ]);
      });
    });

    describe('values it should leave out', () => {
      it('returns nothing when no field is set', () => {
        const { profileRows, hasConfigurableTriggers } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [buildSetting(MERGE_REQUEST, {}), buildSetting(DEFAULT_BRANCH, {})],
        });

        expect(profileRows).toEqual([]);
        expect(hasConfigurableTriggers).toBe(true);
      });

      it('ignores configuration on a trigger that cannot be configured', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH, GIT_PUSH],
          triggerSettings: [buildSetting(GIT_PUSH, { historicScan: true })],
        });

        expect(profileRows).toEqual([]);
      });

      it('returns nothing when the only enabled trigger cannot be configured', () => {
        const { profileRows, hasConfigurableTriggers } = classify({
          triggers: [GIT_PUSH],
          triggerSettings: [buildSetting(GIT_PUSH, null)],
        });

        expect(profileRows).toEqual([]);
        expect(hasConfigurableTriggers).toBe(false);
      });

      it('returns nothing when called with no arguments', () => {
        const { profileRows, hasConfigurableTriggers } = classifyConfigurationVariables();

        expect(profileRows).toEqual([]);
        expect(hasConfigurableTriggers).toBe(false);
      });
    });

    describe('what counts as unset', () => {
      it.each`
        description       | value
        ${'empty list'}   | ${[]}
        ${'empty string'} | ${''}
        ${'null'}         | ${null}
      `('ignores a field set to an $description', ({ value }) => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { logOptions: value }),
            buildSetting(DEFAULT_BRANCH, { logOptions: value }),
          ],
        });

        expect(profileRows).toEqual([]);
      });

      it('keeps a field set to false', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: false }),
            buildSetting(DEFAULT_BRANCH, { historicScan: false }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].setting).toBe(HISTORIC_SCAN);
        expect(profileRows[0].value).toBe(false);
      });
    });

    describe('configuration of another scan type', () => {
      it('ignores a configuration that is not secret detection', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            {
              triggerType: MERGE_REQUEST,
              configuration: {
                __typename: 'AutoRemediationConfiguration',
                historicScan: true,
                excludedPaths: ['spec/'],
              },
            },
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            varies: true,
            triggerValues: [{ triggerType: DEFAULT_BRANCH, value: true }],
          },
        ]);
      });
    });

    describe('rowsByTrigger', () => {
      it('returns every setting a trigger sets', () => {
        const { rowsByTrigger } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true, excludedPaths: ['spec/'] }),
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
          ],
        });

        expect(rowsByTrigger.get(MERGE_REQUEST)).toEqual([
          { setting: 'historicScan', value: true },
          { setting: 'excludedPaths', value: ['spec/'] },
        ]);
        expect(rowsByTrigger.get(DEFAULT_BRANCH)).toEqual([
          { setting: 'historicScan', value: true },
        ]);
      });
    });

    describe('comparing values', () => {
      it.each`
        first         | second
        ${['a, b']}   | ${['a', 'b']}
        ${['b', 'a']} | ${['a', 'b']}
        ${['a', 'b']} | ${['a', 'c']}
      `('treats $first and $second as varying', ({ first, second }) => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { excludedPaths: first }),
            buildSetting(DEFAULT_BRANCH, { excludedPaths: second }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].varies).toBe(true);
      });

      it('promotes an identical list to the profile value', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { excludedPaths: ['a', 'b'] }),
            buildSetting(DEFAULT_BRANCH, { excludedPaths: ['a', 'b'] }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].setting).toBe(EXCLUDED_PATHS);
        expect(profileRows[0].value).toEqual(['a', 'b']);
      });
    });

    describe('values', () => {
      it.each`
        field                      | value
        ${'secureAnalyzersPrefix'} | ${'my-registry'}
        ${'imageSuffix'}           | ${'FIPS'}
      `('passes $field through as stored', ({ field, value }) => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { [field]: value }),
            buildSetting(DEFAULT_BRANCH, { [field]: value }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].value).toEqual(value);
      });
    });
  });
});
