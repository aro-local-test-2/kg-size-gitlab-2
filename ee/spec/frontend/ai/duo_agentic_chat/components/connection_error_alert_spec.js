import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ConnectionErrorAlert from 'ee/ai/duo_agentic_chat/components/connection_error_alert.vue';

describe('ConnectionErrorAlert', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(ConnectionErrorAlert, {
      stubs: { GlAlert },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findDescription = () => wrapper.find('p');
  const findRetryButton = () => wrapper.findComponentByTestId('retry-button');

  beforeEach(() => {
    createComponent();
  });

  it('renders a non-dismissible danger alert', () => {
    expect(findAlert().props('variant')).toBe('danger');
    expect(findAlert().props('dismissible')).toBe(false);
  });

  it('renders the title and description', () => {
    expect(findAlert().props('title')).toBe('Connection lost');
    expect(findDescription().text()).toBe('GitLab Duo will resume once reconnected.');
  });

  it('renders the retry button', () => {
    expect(findRetryButton().text()).toBe('Reconnect');
  });

  it('emits retry when the retry button is clicked', () => {
    findRetryButton().vm.$emit('click');

    expect(wrapper.emitted('retry')).toHaveLength(1);
  });

  it('does not emit retry before the button is clicked', () => {
    expect(wrapper.emitted('retry')).toBeUndefined();
  });
});
