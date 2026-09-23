import { getModelConfigurationPath } from 'ee/ai/settings/components/functional_verifications/utils';

describe('getModelConfigurationPath', () => {
  it('returns the features route when a path is given', () => {
    expect(getModelConfigurationPath('/admin/gitlab_duo/model_selection')).toBe(
      '/admin/gitlab_duo/model_selection/features',
    );
  });

  it('returns an empty string when no path is given', () => {
    expect(getModelConfigurationPath('')).toBe('');
  });
});
