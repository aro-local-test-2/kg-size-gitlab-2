import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ThreadLoadErrorEmptyState from 'ee/ai/duo_agentic_chat/components/thread_load_error_empty_state.vue';

describe('ThreadLoadErrorEmptyState', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(ThreadLoadErrorEmptyState);
  };

  const findContainer = () => wrapper.findByTestId('thread-load-error-empty-state');
  const findHeading = () => wrapper.find('h2');
  const findDescription = () => wrapper.find('p');
  const findRetryButton = () => wrapper.findComponentByTestId('thread-load-error-retry-button');
  const findNewChatButton = () =>
    wrapper.findComponentByTestId('thread-load-error-new-chat-button');

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the container', () => {
      expect(findContainer().exists()).toBe(true);
    });

    it('renders the heading', () => {
      expect(findHeading().text()).toBe('Chat could not be loaded');
    });

    it('renders the description', () => {
      expect(findDescription().text()).toBe(
        'Your messages are still saved. Try again, or start a new chat.',
      );
    });

    it('renders the retry button', () => {
      expect(findRetryButton().exists()).toBe(true);
    });

    it('renders the new chat button', () => {
      expect(findNewChatButton().exists()).toBe(true);
    });
  });

  describe('events', () => {
    beforeEach(() => {
      createComponent();
    });

    it('emits retry-thread-load when the retry button is clicked', () => {
      findRetryButton().vm.$emit('click');

      expect(wrapper.emitted('retry-thread-load')).toHaveLength(1);
    });

    it('emits new-chat when the new chat button is clicked', () => {
      findNewChatButton().vm.$emit('click');

      expect(wrapper.emitted('new-chat')).toHaveLength(1);
    });
  });
});
