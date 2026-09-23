import { GITLAB_DEFAULT_MODEL } from 'ee/ai/model_selection/constants';
import {
  formatDefaultModelData,
  buildAutoModelOption,
  reorderAutoOptionFirst,
} from 'ee/ai/shared/utils/model_selection_utils';

describe('formatDefaultModelData', () => {
  it('returns formatted default model data', () => {
    const defaultModelData = {
      name: 'Claude Sonnet 4.5',
      ref: GITLAB_DEFAULT_MODEL,
      modelProvider: 'Anthropic',
      modelDescription: 'Fast, cost-effective responses.',
      costIndicator: '$$$',
    };

    expect(formatDefaultModelData(defaultModelData)).toEqual({
      text: 'Claude Sonnet 4.5 - Default',
      value: GITLAB_DEFAULT_MODEL,
      provider: 'Anthropic',
      description: 'Fast, cost-effective responses.',
      costIndicator: '$$$',
    });
  });
});

describe('buildAutoModelOption', () => {
  it('builds the default "Auto" option', () => {
    expect(buildAutoModelOption()).toEqual({
      text: 'Auto',
      value: GITLAB_DEFAULT_MODEL,
      description: 'GitLab dynamically routes each request to the most suitable model',
    });
  });
});

describe('reorderAutoOptionFirst', () => {
  it('moves the "Auto" option to the top of the list', () => {
    const models = [
      { text: 'Claude Sonnet 4.0', value: 'claude_sonnet_4_20250514' },
      { text: 'Auto', value: GITLAB_DEFAULT_MODEL },
      { text: 'Claude Sonnet 4.6', value: 'claude_sonnet_4_6' },
    ];

    expect(reorderAutoOptionFirst(models)).toEqual([
      { text: 'Auto', value: GITLAB_DEFAULT_MODEL },
      { text: 'Claude Sonnet 4.0', value: 'claude_sonnet_4_20250514' },
      { text: 'Claude Sonnet 4.6', value: 'claude_sonnet_4_6' },
    ]);
  });

  it('returns the list unchanged when there is no "Auto" option', () => {
    const models = [
      { text: 'Claude Sonnet 4.0', value: 'claude_sonnet_4_20250514' },
      { text: 'Claude Sonnet 4.6', value: 'claude_sonnet_4_6' },
    ];

    expect(reorderAutoOptionFirst(models)).toBe(models);
  });
});
