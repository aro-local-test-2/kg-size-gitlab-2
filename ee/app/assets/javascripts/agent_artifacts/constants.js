import { s__ } from '~/locale';

// Keyed by the raw `agentType` wire values. Entries without an `icon` render an
// initial-letter avatar instead of a sprite.
export const CLIENT_TYPES = {
  'claude-code': { name: s__('AgentArtifacts|Claude Code') },
  opencode: { name: s__('AgentArtifacts|OpenCode') },
};

export const DEFAULT_CLIENT_TYPE = {
  name: s__('AgentArtifacts|GitLab Duo'),
  icon: 'tanuki-ai',
};
