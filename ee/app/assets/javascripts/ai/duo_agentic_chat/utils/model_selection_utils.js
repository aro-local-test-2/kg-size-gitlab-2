import { getStorageValue, saveStorageValue, removeStorageValue } from '~/lib/utils/local_storage';

import { GITLAB_DEFAULT_MODEL } from 'ee/ai/model_selection/constants';
import {
  DUO_AGENTIC_CHAT_RECENT_MODELS_KEY,
  DUO_AGENTIC_CHAT_SELECTED_MODEL_KEY,
} from 'ee/ai/constants';
import { MAX_RECENT_MODELS } from '../constants';

export const getModel = (availableModels, modelValue) => {
  return availableModels?.find((item) => item.value === modelValue);
};

export const getDefaultModel = (availableModels) => {
  return getModel(availableModels, GITLAB_DEFAULT_MODEL);
};

export const clearSavedModel = () => {
  try {
    removeStorageValue(DUO_AGENTIC_CHAT_SELECTED_MODEL_KEY);
    return true;
  } catch (error) {
    return false;
  }
};

export const getSavedModel = (availableModels) => {
  try {
    const savedModel = getStorageValue(DUO_AGENTIC_CHAT_SELECTED_MODEL_KEY)?.value;

    // Validate that the saved model still exists
    if (!getModel(availableModels, savedModel?.value)) {
      clearSavedModel();
      return null;
    }

    return savedModel;
  } catch {
    return null;
  }
};

export const getCurrentModel = ({ availableModels, pinnedModel, selectedModel }) => {
  return (
    pinnedModel ||
    selectedModel ||
    getSavedModel(availableModels) ||
    getDefaultModel(availableModels)
  );
};

export const saveModel = (model) => {
  try {
    saveStorageValue(DUO_AGENTIC_CHAT_SELECTED_MODEL_KEY, model);
    return true;
  } catch (error) {
    return false;
  }
};

export const isModelSelectionDisabled = (pinnedModel) => {
  return Boolean(pinnedModel);
};

// Refs of the models the user picked most recently, newest first. Refs rather
// than whole models, so a model that changed name or left the catalog is
// resolved against the current list instead of rendered from a stale copy.
export const getRecentModelRefs = () => {
  try {
    const { value } = getStorageValue(DUO_AGENTIC_CHAT_RECENT_MODELS_KEY);

    return Array.isArray(value) ? value : [];
  } catch {
    return [];
  }
};

// Returns the updated list so the caller can render it without reading back
// from storage, which also keeps the group correct when the write fails.
export const recordRecentModelRef = (ref) => {
  const refs = [ref, ...getRecentModelRefs().filter((it) => it !== ref)].slice(
    0,
    MAX_RECENT_MODELS,
  );

  try {
    saveStorageValue(DUO_AGENTIC_CHAT_RECENT_MODELS_KEY, refs);
  } catch {
    // A full or unavailable store only costs the user their recents.
  }

  return refs;
};
