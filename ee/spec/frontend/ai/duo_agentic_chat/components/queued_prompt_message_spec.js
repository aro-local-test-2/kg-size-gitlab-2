import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import QueuedPromptMessage from 'ee/ai/duo_agentic_chat/components/queued_prompt_message.vue';

describe('QueuedPromptMessage', () => {
  let wrapper;

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(QueuedPromptMessage, {
      propsData: { content: 'queued prompt', ...propsData },
    });
  };

  const findBubble = () => wrapper.findByTestId('queued-prompt-message');
  const findLabel = () => wrapper.findByTestId('queued-prompt-label');
  const findRemoveButton = () => wrapper.findComponentByTestId('queued-prompt-remove-button');

  beforeEach(() => {
    createComponent();
  });

  it('renders the prompt content in an italic bubble', () => {
    expect(findBubble().text()).toContain('queued prompt');
    expect(wrapper.find('.gl-italic').text()).toContain('queued prompt');
  });

  it('renders a "Queued" label', () => {
    expect(findLabel().text()).toBe('Queued');
  });

  it('renders a tertiary, icon-only close button', () => {
    const button = findRemoveButton();

    expect(button.exists()).toBe(true);
    expect(button.props()).toMatchObject({ category: 'tertiary', icon: 'close' });
  });

  it('emits remove when the close button is clicked', () => {
    findRemoveButton().vm.$emit('click');

    expect(wrapper.emitted('remove')).toHaveLength(1);
  });

  it('exposes the remove action via an aria-label', () => {
    expect(findRemoveButton().attributes('aria-label')).toBe('Remove queued prompt');
  });

  it('shows a "Remove" tooltip on the close button', () => {
    expect(findRemoveButton().attributes('title')).toBe('Remove');
  });

  it('renders the button as a GlButton', () => {
    expect(wrapper.findComponent(GlButton).exists()).toBe(true);
  });
});
