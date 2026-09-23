export const GITLAB_DEFAULT_MODEL = '';
export const SUPPRESS_DEFAULT_MODEL_MODAL_KEY = 'suppress_default_model_modal';

// Ref prefix AIGW assigns to the load-balanced default pseudo-model, only present
// when a feature uses load-balanced defaults. See AIGW get_definitions.py:
// https://gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/-/blob/2b3e6537fcc4e7db74ce04508a28871ecb7d4e0d/ai_gateway/api/v1/models/get_definitions.py#L22
export const LOAD_BALANCED_MODEL_REF_PREFIX = '__default__';

export const AGENTIC_CHAT_FEATURE = 'duo_agent_platform_agentic_chat';
export const DUO_DEVELOPER_FEATURE = 'duo_developer';
