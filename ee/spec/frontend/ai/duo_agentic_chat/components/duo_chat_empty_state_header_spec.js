import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoChatEmptyStateHeader from 'ee/ai/duo_agentic_chat/components/duo_chat_empty_state_header.vue';

describe('DuoChatEmptyStateHeader', () => {
  let wrapper;

  beforeEach(() => {
    wrapper = shallowMountExtended(DuoChatEmptyStateHeader);
  });

  it('renders the default Duo Agent Platform copy', () => {
    expect(wrapper.findByRole('heading').text()).toBe('GitLab Duo Agent Platform');
    expect(wrapper.find('p').text()).toBe(
      'Collaborate with AI agents to accomplish tasks and answer questions, or use a multi-agent flow to solve a complex problem.',
    );
  });
});
