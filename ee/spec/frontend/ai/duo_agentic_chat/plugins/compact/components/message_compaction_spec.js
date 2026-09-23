import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import MessageCompaction from 'ee/ai/duo_agentic_chat/plugins/compact/components/message_compaction.vue';

describe('MessageCompaction', () => {
  let wrapper;

  const findDelimiter = () => wrapper.findByTestId('compaction-delimiter');

  beforeEach(() => {
    wrapper = shallowMountExtended(MessageCompaction);
  });

  it('announces that the conversation was compacted', () => {
    expect(findDelimiter().text()).toBe('Conversation compacted');
  });

  it('sits the label between two rules, so it reads as a divider rather than a message', () => {
    expect(findDelimiter().findAll('hr')).toHaveLength(2);
  });
});
