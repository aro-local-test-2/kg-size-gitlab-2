import { s__, createListFormat } from '~/locale';

// The seven settings an ancestor group can lock, under the label the UI already
// shows, following formatServerValidations. A field with no entry here is
// dropped, not shown by its raw attribute name.
const FIELD_LABELS = {
  lock_duo_features_enabled: s__('AiPowered|GitLab Duo availability'),
  lock_duo_remote_flows_enabled: s__('DuoAgentPlatform|Allow flow execution'),
  lock_duo_foundational_flows_enabled: s__('DuoAgentPlatform|Allow foundational flows'),
  lock_duo_custom_agents_enabled: s__('AiPowered|Allow custom agents'),
  lock_duo_custom_flows_enabled: s__('AiPowered|Allow custom flows'),
  lock_duo_external_agents_enabled: s__('AiPowered|Allow external agents'),
  lock_tool_approval_for_session_enabled: s__('AiPowered|Tool approval for sessions'),
};

// Each fragment is already translated, so the join is plain concatenation and
// not an externalized template (doc/development/i18n/externalization.md,
// "Splitting sentences").
export const formatSettingsErrorMessage = (error, defaultMessage = '') => {
  const fields = error?.response?.data?.message;

  if (!fields || typeof fields !== 'object' || Array.isArray(fields)) {
    return defaultMessage;
  }

  const sentences = Object.entries(fields)
    .map(([field, messages]) => {
      const label = FIELD_LABELS[field.replace('namespace_settings.', '')];
      const message = [].concat(messages).filter(Boolean).join(', ');

      return label && message ? `${label} ${message}` : null;
    })
    .filter(Boolean);

  if (!sentences.length) {
    return defaultMessage;
  }

  return `${defaultMessage} ${createListFormat({ type: 'conjunction' }).format(sentences)}`;
};
