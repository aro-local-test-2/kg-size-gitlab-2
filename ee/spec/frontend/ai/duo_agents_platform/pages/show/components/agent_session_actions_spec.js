import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import AgentSessionActions from 'ee/ai/duo_agents_platform/pages/show/components/agent_session_actions.vue';

describe('AgentSessionActions', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AgentSessionActions, {
      propsData: { status: 'CREATED', canUpdateWorkflow: true, ...props },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findCancelWrapper = () => wrapper.findByTestId('cancel-session-wrapper');
  const findAllButtons = () => wrapper.findAllComponents(GlButton);
  const findIconButton = () => wrapper.findComponentByTestId('cancel-session-icon-button');
  const findTextButton = () => wrapper.findComponentByTestId('cancel-session-button');
  const findDetailsToggle = () => wrapper.findComponentByTestId('toggle-session-details-button');

  describe('when session is not cancelable', () => {
    it.each(['FINISHED', 'FAILED', 'STOPPED'])('does not render for %s status', (status) => {
      createComponent({ status });
      expect(findCancelWrapper().exists()).toBe(false);
    });
  });

  describe('session details toggle', () => {
    describe('when showDetailsToggle is false', () => {
      beforeEach(() => createComponent());

      it('does not render the toggle', () => {
        expect(findDetailsToggle().exists()).toBe(false);
      });
    });

    describe('when showDetailsToggle is true', () => {
      beforeEach(() => createComponent({ showDetailsToggle: true }));

      it('renders the toggle alongside the cancel button', () => {
        expect(findDetailsToggle().exists()).toBe(true);
        expect(findAllButtons()).toHaveLength(2);
      });

      it('renders a fixed icon and label', () => {
        expect(findDetailsToggle().props('icon')).toBe('chevron-double-lg-left');
        expect(findDetailsToggle().attributes('aria-label')).toBe('Session details');
      });

      describe('when clicked', () => {
        beforeEach(() => findDetailsToggle().vm.$emit('click'));

        it('emits toggle-details', () => {
          expect(wrapper.emitted('toggle-details')).toHaveLength(1);
        });
      });

      describe('when the session is not cancelable', () => {
        beforeEach(() => createComponent({ status: 'FINISHED', showDetailsToggle: true }));

        it('still renders the toggle', () => {
          expect(findCancelWrapper().exists()).toBe(false);
          expect(findDetailsToggle().exists()).toBe(true);
        });
      });
    });

    describe('when detailsDrawerId is provided', () => {
      beforeEach(() =>
        createComponent({
          showDetailsToggle: true,
          detailsDrawerId: 'session-details-info-drawer-1',
        }),
      );

      it('points aria-controls at the drawer', () => {
        expect(findDetailsToggle().attributes('aria-controls')).toBe(
          'session-details-info-drawer-1',
        );
      });
    });

    describe('when details are expanded', () => {
      beforeEach(() => createComponent({ showDetailsToggle: true, detailsExpanded: true }));

      it('reports the expanded state', () => {
        expect(findDetailsToggle().attributes('aria-expanded')).toBe('true');
      });
    });

    describe('when details are collapsed', () => {
      beforeEach(() => createComponent({ showDetailsToggle: true, detailsExpanded: false }));

      it('reports the collapsed state', () => {
        expect(findDetailsToggle().attributes('aria-expanded')).toBe('false');
      });
    });
  });

  describe('when session is cancelable', () => {
    describe('when isSidePanel is false', () => {
      beforeEach(() => createComponent());

      it('renders only the text cancel button', () => {
        expect(findAllButtons()).toHaveLength(1);
        expect(findTextButton().exists()).toBe(true);
        expect(findIconButton().exists()).toBe(false);
      });

      it('emits cancel-session when clicked', () => {
        findTextButton().vm.$emit('click');
        expect(wrapper.emitted('cancel-session')).toHaveLength(1);
      });

      describe('when user has permission', () => {
        it('enables the button', () => {
          expect(findTextButton().props('disabled')).toBe(false);
        });

        it('has the gl-tooltip directive bound', () => {
          expect(getBinding(findCancelWrapper().element, 'gl-tooltip')).toBeDefined();
        });

        it('shows no tooltip text', () => {
          expect(findCancelWrapper().attributes('title')).toBe('');
        });
      });

      describe('when user lacks permission', () => {
        beforeEach(() => createComponent({ canUpdateWorkflow: false }));

        it('disables the button', () => {
          expect(findTextButton().props('disabled')).toBe(true);
        });

        it('shows the no-permission tooltip', () => {
          expect(findCancelWrapper().attributes('title')).toBe(
            'You do not have permission to cancel this session.',
          );
        });
      });
    });

    describe('when isSidePanel is true', () => {
      beforeEach(() => createComponent({ isSidePanel: true }));

      it('renders only the icon cancel button', () => {
        expect(findAllButtons()).toHaveLength(1);
        expect(findIconButton().exists()).toBe(true);
        expect(findTextButton().exists()).toBe(false);
      });

      it('emits cancel-session when clicked', () => {
        findIconButton().vm.$emit('click');
        expect(wrapper.emitted('cancel-session')).toHaveLength(1);
      });

      describe('when user has permission', () => {
        it('enables the button', () => {
          expect(findIconButton().props('disabled')).toBe(false);
        });

        it('shows the cancel tooltip', () => {
          expect(getBinding(findCancelWrapper().element, 'gl-tooltip')).toBeDefined();
          expect(findCancelWrapper().attributes('title')).toBe('Cancel session');
        });
      });

      describe('when user lacks permission', () => {
        beforeEach(() => createComponent({ isSidePanel: true, canUpdateWorkflow: false }));

        it('disables the button', () => {
          expect(findIconButton().props('disabled')).toBe(true);
        });

        it('shows the no-permission tooltip', () => {
          expect(findCancelWrapper().attributes('title')).toBe(
            'You do not have permission to cancel this session.',
          );
        });
      });
    });
  });
});
