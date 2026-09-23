import { GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import NoteSessionBar from 'ee/ai/shared/widgets/note_session_bar.vue';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';

describe('NoteSessionBar component', () => {
  let wrapper;

  const defaultProps = {
    agentName: 'Code Review',
    sessionId: 'gid://gitlab/DuoWorkflow/42',
    isReply: false,
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(NoteSessionBar, {
      propsData: { ...defaultProps, ...props },
      stubs: { GlSprintf },
    });
  };

  const findWrapper = () => wrapper.findByTestId('note-session-bar-wrapper');
  const findBar = () => wrapper.findByTestId('note-session-bar');
  const findText = () => wrapper.findByTestId('note-session-bar-text');
  const findSpinner = () => wrapper.findByTestId('note-session-bar-spinner');
  const findStatusIcon = () => wrapper.findComponentByTestId('note-session-bar-status-icon');

  describe('when status is null (no status)', () => {
    it('does not render the bar', () => {
      createComponent();
      expect(findBar().exists()).toBe(false);
    });
  });

  describe('when status is finished', () => {
    it('does not render the bar', () => {
      createComponent({ status: 'finished' });
      expect(findBar().exists()).toBe(false);
    });
  });

  describe('when the bar is visible', () => {
    beforeEach(() => createComponent({ status: 'created' }));

    it('has a "View session" aria-label including the session id', () => {
      expect(findBar().attributes('aria-label')).toBe('View session #42');
    });
  });

  describe('isReply prop', () => {
    describe('when isReply is true', () => {
      beforeEach(() => createComponent({ status: 'running', isReply: true }));

      it('applies correct styles', () => {
        expect(findWrapper().classes()).toContain('gl-mr-3');
        expect(findBar().classes()).toContain('gl-border-1');
        expect(findBar().classes()).toContain('gl-rounded-base');
        expect(findBar().classes()).not.toContain('gl-rounded-t-none');
      });
    });

    describe('when isReply is false', () => {
      beforeEach(() => createComponent({ status: 'running', isReply: false }));

      it('applies border-top to the wrapper', () => {
        expect(findWrapper().classes()).toContain('gl-border-t');
        expect(findWrapper().classes()).toContain('gl-border-t-solid');
        expect(findWrapper().classes()).not.toContain('gl-mr-3');
      });
    });
  });

  describe.each(['created', 'running'])('when status is %s', (status) => {
    beforeEach(() => {
      jest.spyOn(Math, 'random').mockReturnValue(0);
      createComponent({ status });
    });

    it('renders the bar', () => {
      expect(findBar().exists()).toBe(true);
    });

    it('shows a loading spinner', () => {
      expect(findSpinner().exists()).toBe(true);
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    });

    it('does not show a status icon', () => {
      expect(findStatusIcon().exists()).toBe(false);
    });

    it('emits SHOW_SESSION with the session id when clicked', () => {
      jest.spyOn(eventHub, '$emit');
      findBar().trigger('click');
      expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 42 });
    });

    it('renders the agent name in bold within the running phrase', () => {
      expect(findText().find('strong').text()).toBe('Code Review');
      expect(findText().text()).toContain('Code Review is investigating...');
    });
  });

  describe('when status is paused', () => {
    beforeEach(() => createComponent({ status: 'paused' }));

    it('renders', () => {
      expect(findWrapper().exists()).toBe(true);
    });

    it('shows a pause icon with subtle variant', () => {
      expect(findStatusIcon().exists()).toBe(true);
      expect(findStatusIcon().props('name')).toBe('pause');
      expect(findStatusIcon().props('variant')).toBe('subtle');
    });

    it('does not show a spinner', () => {
      expect(findSpinner().exists()).toBe(false);
    });

    it('renders the agent name in bold within the paused phrase', () => {
      expect(findText().find('strong').text()).toBe('Code Review');
      expect(findText().text()).toContain('Code Review is paused');
    });
  });

  describe.each(['input_required', 'plan_approval_required', 'tool_call_approval_required'])(
    'when status is %s',
    (status) => {
      beforeEach(() => createComponent({ status }));

      it('renders the bar', () => {
        expect(findBar().exists()).toBe(true);
      });

      it('shows a warning icon with the warning variant', () => {
        expect(findStatusIcon().exists()).toBe(true);
        expect(findStatusIcon().props('name')).toBe('warning-solid');
        expect(findStatusIcon().props('variant')).toBe('warning');
      });

      it('does not show a spinner', () => {
        expect(findSpinner().exists()).toBe(false);
      });

      it('renders the agent name in bold within the needs input phrase', () => {
        expect(findText().find('strong').text()).toBe('Code Review');
        expect(findText().text()).toContain('Code Review needs input');
      });
    },
  );

  describe.each(['failed', 'stopped'])('when status is %s', (status) => {
    beforeEach(() => createComponent({ status }));

    it('renders the bar', () => {
      expect(findBar().exists()).toBe(true);
    });

    it('shows an error icon with danger variant', () => {
      expect(findStatusIcon().exists()).toBe(true);
      expect(findStatusIcon().props('name')).toBe('error');
      expect(findStatusIcon().props('variant')).toBe('danger');
    });

    it('does not show a spinner', () => {
      expect(findSpinner().exists()).toBe(false);
    });

    it('renders the agent name in bold within the unable to complete phrase', () => {
      expect(findText().find('strong').text()).toBe('Code Review');
      expect(findText().text()).toContain('Code Review was unable to complete your request');
    });
  });
});
