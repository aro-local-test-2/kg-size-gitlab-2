import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ThreadLoadingEmptyState from 'ee/ai/duo_agentic_chat/components/thread_loading_empty_state.vue';

describe('ThreadLoadingEmptyState', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(ThreadLoadingEmptyState);
  };

  const findContainer = () => wrapper.findByTestId('thread-loading-empty-state');
  const findLoadingIcon = () => wrapper.findComponent({ name: 'GlLoadingIcon' });
  const findDescription = () => wrapper.find('p');

  beforeEach(() => {
    createComponent();
  });

  it('renders the container', () => {
    expect(findContainer().exists()).toBe(true);
  });

  it('renders a loading icon', () => {
    expect(findLoadingIcon().exists()).toBe(true);
  });

  it('renders the loading message', () => {
    expect(findDescription().text()).toBe('Loading your conversation...');
  });
});
