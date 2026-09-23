import { formatEventName, getClientType } from 'ee/agent_artifacts/utils';

describe('getClientType', () => {
  it.each([null, undefined])('returns the GitLab Duo default when agentType is %s', (agentType) => {
    expect(getClientType({ agentType })).toEqual({
      name: 'GitLab Duo',
      icon: 'tanuki-ai',
    });
  });

  it.each([
    ['claude-code', 'Claude Code'],
    ['opencode', 'OpenCode'],
  ])('returns the named entry for known agent type %s', (agentType, name) => {
    expect(getClientType({ agentType })).toEqual({ name });
  });

  it('humanises unknown agent types instead of falling back to GitLab Duo', () => {
    expect(getClientType({ agentType: 'some-new-agent' })).toEqual({ name: 'Some new agent' });
  });
});

describe('formatEventName', () => {
  describe('with ai_ prefix', () => {
    it.each([
      ['ai_agent_session_ended', 'Agent session ended'],
      ['ai_llm_input_sent', 'Llm input sent'],
      ['ai_tool_invoked', 'Tool invoked'],
    ])('converts %s to %s', (input, expected) => {
      expect(formatEventName(input)).toBe(expected);
    });
  });

  describe('without ai_ prefix', () => {
    it('capitalises the first letter and replaces underscores with spaces', () => {
      expect(formatEventName('tool_execution')).toBe('Tool execution');
    });
  });

  describe('falsy input guard', () => {
    it.each([null, undefined, ''])('returns an empty string for %s', (input) => {
      expect(formatEventName(input)).toBe('');
    });
  });
});
