import {
  sortFeatureSettingsByTitle,
  sortFeatureSettingsByReleaseStateThenTitle,
} from 'ee/ai/shared/feature_settings/utils';

const setting = (title, releaseState = 'GA') => ({ title, releaseState });
const titlesOf = (featureSettings) => featureSettings.map(({ title }) => title);

describe('feature settings utils', () => {
  describe('sortFeatureSettingsByTitle', () => {
    it('orders the feature settings alphabetically by title', () => {
      const sorted = sortFeatureSettingsByTitle([
        setting('Security Review'),
        setting('Agents & flows'),
        setting('Agentic Code Review'),
      ]);

      expect(titlesOf(sorted)).toEqual([
        'Agentic Code Review',
        'Agents & flows',
        'Security Review',
      ]);
    });

    it.each([null, undefined, ''])('tolerates a %p title and orders it first', (title) => {
      const sorted = sortFeatureSettingsByTitle([setting('Agents & flows'), setting(title)]);

      expect(titlesOf(sorted)).toEqual([title, 'Agents & flows']);
    });

    it('does not mutate the given array', () => {
      const featureSettings = [setting('Security Review'), setting('Agents & flows')];

      sortFeatureSettingsByTitle(featureSettings);

      expect(titlesOf(featureSettings)).toEqual(['Security Review', 'Agents & flows']);
    });
  });

  describe('sortFeatureSettingsByReleaseStateThenTitle', () => {
    it('orders by release state before title', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Troubleshoot Job', 'EXPERIMENT'),
        setting('Explain Code', 'BETA'),
        setting('General Chat', 'GA'),
      ]);

      expect(titlesOf(sorted)).toEqual(['General Chat', 'Explain Code', 'Troubleshoot Job']);
    });

    it('keeps a beta feature below a GA feature that is later in the alphabet', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Secret Vulnerability False Positive Detection', 'GA'),
        setting('Resolve Dependency Bump Breaking Changes', 'BETA'),
      ]);

      expect(titlesOf(sorted)).toEqual([
        'Secret Vulnerability False Positive Detection',
        'Resolve Dependency Bump Breaking Changes',
      ]);
    });

    it('orders alphabetically by title within a release state', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Security Review', 'BETA'),
        setting('SAST Vulnerability Resolution', 'BETA'),
        setting('Resolve Dependency Bump Breaking Changes', 'BETA'),
      ]);

      expect(titlesOf(sorted)).toEqual([
        'Resolve Dependency Bump Breaking Changes',
        'SAST Vulnerability Resolution',
        'Security Review',
      ]);
    });

    it('orders a feature setting with an unrecognised release state last', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Agents & flows', 'SOMETHING_NEW'),
        setting('Security Review', 'EXPERIMENT'),
      ]);

      expect(titlesOf(sorted)).toEqual(['Security Review', 'Agents & flows']);
    });

    it('does not mutate the given array', () => {
      const featureSettings = [setting('Explain Code', 'BETA'), setting('General Chat', 'GA')];

      sortFeatureSettingsByReleaseStateThenTitle(featureSettings);

      expect(titlesOf(featureSettings)).toEqual(['Explain Code', 'General Chat']);
    });
  });
});
