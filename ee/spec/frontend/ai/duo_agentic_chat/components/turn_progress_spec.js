import { DuoChatLoader } from '@gitlab/duo-ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CompactingIndicator from 'ee/ai/duo_agentic_chat/components/compacting_indicator.vue';
import TurnProgress from 'ee/ai/duo_agentic_chat/components/turn_progress.vue';
import { MOCK_COMPACT_PROMPT_MESSAGE } from 'ee_jest/ai/duo_agentic_chat/components/mock_data';

describe('TurnProgress', () => {
  let wrapper;

  const agentMessage = { role: 'assistant', message_type: 'agent', content: 'Done.' };
  const userMessage = { role: 'user', content: 'Summarise this file for me' };

  const createComponent = ({ isLoading = true, messages = [] } = {}) => {
    wrapper = shallowMountExtended(TurnProgress, { propsData: { isLoading, messages } });
  };

  const findResponseLoader = () => wrapper.findComponent(DuoChatLoader);
  const findCompactingIndicator = () => wrapper.findComponent(CompactingIndicator);

  describe('when a compact prompt is the last thing the user sent', () => {
    beforeEach(() => createComponent({ messages: [agentMessage, MOCK_COMPACT_PROMPT_MESSAGE] }));

    it('reports the compaction instead of a generic response', () => {
      expect(findCompactingIndicator().exists()).toBe(true);
      expect(findResponseLoader().exists()).toBe(false);
    });
  });

  describe('when the turn is an ordinary one', () => {
    beforeEach(() => createComponent({ messages: [userMessage] }));

    it('reports a generic response', () => {
      expect(findResponseLoader().exists()).toBe(true);
      expect(findCompactingIndicator().exists()).toBe(false);
    });

    // duo-ui's own default is the shorter "GitLab Duo", so leaving this unset would
    // quietly reword the sentence the loader renders.
    it('names the chat in the loader sentence', () => {
      expect(findResponseLoader().props('toolName')).toBe('GitLab Duo Agentic Chat');
    });
  });

  // Stopping the workflow adds nothing to the log, so the log alone cannot say the
  // compaction is over. Only the turn ending can.
  describe('when no turn is in flight', () => {
    beforeEach(() =>
      createComponent({ isLoading: false, messages: [MOCK_COMPACT_PROMPT_MESSAGE] }),
    );

    it('reports nothing', () => {
      expect(findCompactingIndicator().exists()).toBe(false);
      expect(findResponseLoader().exists()).toBe(false);
    });
  });

  describe('when the compaction has landed and the turn continues', () => {
    beforeEach(() =>
      createComponent({
        messages: [MOCK_COMPACT_PROMPT_MESSAGE, { role: 'tool', message_type: 'tool' }],
      }),
    );

    it('stops reporting the compaction', () => {
      expect(findCompactingIndicator().exists()).toBe(false);
      expect(findResponseLoader().exists()).toBe(true);
    });
  });

  it('reports nothing for an empty log', () => {
    createComponent();

    expect(findCompactingIndicator().exists()).toBe(false);
    expect(findResponseLoader().exists()).toBe(true);
  });
});
