import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoChatAlerts from 'ee/ai/duo_agentic_chat/components/duo_chat_alerts.vue';

describe('DuoChatAlerts', () => {
  let wrapper;

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(DuoChatAlerts, { propsData });
  };

  const findInfoAlert = () => wrapper.findComponentByTestId('chat-info');
  const findErrorAlert = () => wrapper.findComponentByTestId('chat-error');

  describe('with nothing to report', () => {
    it('renders no alert', () => {
      createComponent();

      expect(wrapper.findAllComponents(GlAlert)).toHaveLength(0);
    });
  });

  describe('with an info message', () => {
    beforeEach(() => {
      createComponent({ info: 'Chat is running elsewhere' });
    });

    it('renders it as a non-dismissible info alert', () => {
      expect(findInfoAlert().props()).toMatchObject({ variant: 'info', dismissible: false });
      expect(findInfoAlert().text()).toBe('Chat is running elsewhere');
    });

    it('renders no error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('with an error message', () => {
    beforeEach(() => {
      createComponent({ error: 'Something went wrong' });
    });

    it('renders it as a non-dismissible danger alert', () => {
      expect(findErrorAlert().props()).toMatchObject({ variant: 'danger', dismissible: false });
      expect(findErrorAlert().text()).toBe('Something went wrong');
    });

    it('renders no info alert', () => {
      expect(findInfoAlert().exists()).toBe(false);
    });
  });

  describe('with both messages', () => {
    it('renders the info alert above the error alert', () => {
      createComponent({ info: 'Chat is running elsewhere', error: 'Something went wrong' });

      expect(wrapper.findAllComponents(GlAlert)).toHaveLength(2);
      expect(findInfoAlert().element.compareDocumentPosition(findErrorAlert().element)).toBe(
        Node.DOCUMENT_POSITION_FOLLOWING,
      );
    });
  });
});
