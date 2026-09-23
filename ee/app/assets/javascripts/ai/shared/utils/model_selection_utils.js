import { __, s__, sprintf } from '~/locale';
import { GITLAB_DEFAULT_MODEL } from 'ee/ai/model_selection/constants';

export const formatDefaultModelData = (defaultModel) => {
  const { name, modelProvider, modelDescription, costIndicator } = defaultModel;

  const formattedModelText = sprintf(__('%{modelName} - Default'), { modelName: name }) || '';

  return {
    text: formattedModelText,
    value: GITLAB_DEFAULT_MODEL,
    provider: modelProvider,
    description: modelDescription,
    costIndicator,
  };
};

export const buildAutoModelOption = () => ({
  text: s__('ModelSelection|Auto'),
  value: GITLAB_DEFAULT_MODEL,
  description: s__(
    'ModelSelection|GitLab dynamically routes each request to the most suitable model',
  ),
});

export const reorderAutoOptionFirst = (models) => {
  const autoOption = models.find(({ value }) => value === GITLAB_DEFAULT_MODEL);

  if (!autoOption) return models;

  return [autoOption, ...models.filter(({ value }) => value !== GITLAB_DEFAULT_MODEL)];
};
