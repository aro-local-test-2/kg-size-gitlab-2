import { GlSkeletonLoader, GlSprintf, GlTruncate } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentFlowHeader from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_header.vue';
import AgentStatusBadge from 'ee/ai/shared/widgets/agent_status_badge.vue';
import AgentFlowTriggeredUser from 'ee/ai/duo_agents_platform/components/common/agent_flow_triggered_user.vue';
import AgentSessionActions from 'ee/ai/duo_agents_platform/pages/show/components/agent_session_actions.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { mockUser1 } from 'ee_jest/ai/mocks';

jest.mock('~/lib/utils/datetime/timeago_utility');

const VALID_DATE = '2024-01-15T10:00:00.000Z';

describe('AgentFlowHeader', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AgentFlowHeader, {
      propsData: { isLoading: false, ...props },
      stubs: { GlSprintf },
    });
  };

  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findPageHeader = () => wrapper.find('header');
  const findPageTitle = () => wrapper.findByTestId('agent-flow-page-title');
  const findStatusBadge = () => wrapper.findComponent(AgentStatusBadge);
  const findLastUpdated = () => wrapper.findByTestId('agent-flow-last-updated');
  const findStartedAt = () => wrapper.findByTestId('agent-flow-started-at');
  const findSeparator = () => wrapper.findByTestId('timestamp-separator');
  const findSessionActions = () => wrapper.findComponent(AgentSessionActions);
  const findProjectName = () => wrapper.findByTestId('agent-flow-project-name');
  const findProjectLabel = () => findProjectName().findComponent(GlTruncate);
  const findProjectSeparator = () => wrapper.findByTestId('project-separator');
  const findTriggeredUser = () => wrapper.findComponent(AgentFlowTriggeredUser);

  describe('when loading', () => {
    beforeEach(() => createComponent({ isLoading: true }));

    it('renders the skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('does not render the page header', () => {
      expect(findPageHeader().exists()).toBe(false);
    });
  });

  describe('when not loading', () => {
    beforeEach(() => createComponent());

    it('renders the page header', () => {
      expect(findPageHeader().exists()).toBe(true);
    });

    it('does not render the skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(false);
    });
  });

  describe('when isSidePanelView is false', () => {
    it('renders the title', () => {
      createComponent({ title: 'My custom title' });
      expect(findPageTitle().text()).toBe('My custom title');
    });

    describe('session actions', () => {
      beforeEach(() => createComponent({ status: 'RUNNING', canUpdateWorkflow: true }));

      it('passes correct props to AgentSessionActions', () => {
        expect(findSessionActions().props()).toMatchObject({
          status: 'RUNNING',
          canUpdateWorkflow: true,
          isSidePanel: false,
        });
      });

      it('emits cancel-session when AgentSessionActions emits it', () => {
        findSessionActions().vm.$emit('cancel-session');
        expect(wrapper.emitted('cancel-session')).toHaveLength(1);
      });
    });

    describe('session details toggle', () => {
      beforeEach(() =>
        createComponent({
          showDetailsToggle: true,
          detailsExpanded: false,
          detailsDrawerId: 'session-details-info-drawer-1',
        }),
      );

      it('passes the toggle props to AgentSessionActions', () => {
        expect(findSessionActions().props()).toMatchObject({
          showDetailsToggle: true,
          detailsExpanded: false,
          detailsDrawerId: 'session-details-info-drawer-1',
        });
      });

      describe('when AgentSessionActions emits toggle-details', () => {
        beforeEach(() => findSessionActions().vm.$emit('toggle-details'));

        it('emits toggle-details', () => {
          expect(wrapper.emitted('toggle-details')).toHaveLength(1);
        });
      });
    });

    describe('status badge', () => {
      describe('when status is provided', () => {
        beforeEach(() => createComponent({ status: 'RUNNING', humanStatus: 'Running' }));

        it('renders with correct props', () => {
          expect(findStatusBadge().props()).toMatchObject({
            status: 'RUNNING',
            humanStatus: 'Running',
          });
        });
      });

      describe('when no status is provided', () => {
        beforeEach(() => createComponent());

        it('does not render', () => {
          expect(findStatusBadge().exists()).toBe(false);
        });
      });
    });

    describe('started at', () => {
      describe('when createdAt is a valid date', () => {
        beforeEach(() => createComponent({ createdAt: VALID_DATE, user: mockUser1 }));

        it('renders', () => {
          expect(findStartedAt().exists()).toBe(true);
        });

        it('renders a TimeAgoTooltip with the createdAt value', () => {
          expect(findStartedAt().findComponent(TimeAgoTooltip).props('time')).toBe(VALID_DATE);
        });

        it('renders the triggered user inside the slot', () => {
          expect(findStartedAt().findComponent(AgentFlowTriggeredUser).props('user')).toEqual(
            mockUser1,
          );
        });
      });

      describe.each(['', 'not-a-date'])('when createdAt is "%s"', (createdAt) => {
        beforeEach(() => createComponent({ createdAt }));

        it('does not render', () => {
          expect(findStartedAt().exists()).toBe(false);
        });
      });
    });

    describe('last updated', () => {
      describe.each(['FINISHED', 'FAILED', 'STOPPED'])('when status is %s', (status) => {
        beforeEach(() => createComponent({ status, updatedAt: VALID_DATE }));

        it('renders', () => {
          expect(findLastUpdated().exists()).toBe(true);
        });

        it('renders a TimeAgoTooltip with the updatedAt value', () => {
          expect(findLastUpdated().findComponent(TimeAgoTooltip).props('time')).toBe(VALID_DATE);
        });
      });

      describe('when status is non-terminal', () => {
        beforeEach(() => createComponent({ status: 'RUNNING', updatedAt: VALID_DATE }));

        it('does not render', () => {
          expect(findLastUpdated().exists()).toBe(false);
        });
      });

      describe.each(['', 'not-a-date'])('when updatedAt is "%s"', (updatedAt) => {
        beforeEach(() => createComponent({ status: 'FINISHED', updatedAt }));

        it('does not render even for a terminal status', () => {
          expect(findLastUpdated().exists()).toBe(false);
        });
      });
    });

    describe('separator dot', () => {
      describe('when status is terminal, updatedAt and createdAt are valid', () => {
        beforeEach(() =>
          createComponent({ status: 'FINISHED', updatedAt: VALID_DATE, createdAt: VALID_DATE }),
        );

        it('renders', () => {
          expect(findSeparator().exists()).toBe(true);
        });
      });

      describe('when createdAt is absent', () => {
        beforeEach(() => createComponent({ status: 'FINISHED', updatedAt: VALID_DATE }));

        it('does not render', () => {
          expect(findSeparator().exists()).toBe(false);
        });
      });

      describe('when updatedAt is absent', () => {
        beforeEach(() => createComponent({ status: 'FINISHED', createdAt: VALID_DATE }));

        it('does not render', () => {
          expect(findSeparator().exists()).toBe(false);
        });
      });

      describe('when status is non-terminal', () => {
        beforeEach(() =>
          createComponent({ status: 'RUNNING', updatedAt: VALID_DATE, createdAt: VALID_DATE }),
        );

        it('does not render', () => {
          expect(findSeparator().exists()).toBe(false);
        });
      });
    });
  });

  describe('when isSidePanelView is true', () => {
    beforeEach(() => createComponent({ isSidePanelView: true }));

    it('renders the page header', () => {
      expect(findPageHeader().exists()).toBe(true);
    });

    it('does not render the page title', () => {
      expect(findPageTitle().exists()).toBe(false);
    });

    describe('status badge', () => {
      describe('when status is provided', () => {
        beforeEach(() =>
          createComponent({ isSidePanelView: true, status: 'RUNNING', humanStatus: 'Running' }),
        );

        it('renders with correct props', () => {
          expect(findStatusBadge().props()).toMatchObject({
            status: 'RUNNING',
            humanStatus: 'Running',
          });
        });
      });

      describe('when no status is provided', () => {
        it('does not render', () => {
          expect(findStatusBadge().exists()).toBe(false);
        });
      });
    });

    describe('last updated', () => {
      describe('when updatedAt is a valid date', () => {
        beforeEach(() =>
          createComponent({ isSidePanelView: true, updatedAt: new Date().toISOString() }),
        );

        it('renders the last updated timestamp', () => {
          expect(findLastUpdated().exists()).toBe(true);
        });
      });

      it.each([
        ['', 'empty'],
        ['not-a-date', 'invalid'],
      ])('does not render when updatedAt is %s (%s)', (updatedAt) => {
        createComponent({ isSidePanelView: true, updatedAt });
        expect(findLastUpdated().exists()).toBe(false);
      });
    });

    describe('started at', () => {
      describe('when createdAt is a valid date', () => {
        beforeEach(() => createComponent({ isSidePanelView: true, createdAt: VALID_DATE }));

        it('does not render', () => {
          expect(findStartedAt().exists()).toBe(false);
        });
      });
    });

    describe('project name', () => {
      describe('when webPath is provided', () => {
        beforeEach(() =>
          createComponent({
            isSidePanelView: true,
            project: {
              fullPath: 'my-group/my-project',
              webPath: '/my-project',
            },
          }),
        );

        it('renders as a link', () => {
          expect(findProjectName().attributes('href')).toBe('/my-project');
        });

        it('renders the full path with a middle truncation and tooltip', () => {
          expect(findProjectLabel().props()).toMatchObject({
            text: 'my-group / my-project',
            position: 'middle',
            withTooltip: true,
          });
        });

        it('renders the separator dot', () => {
          expect(findProjectSeparator().exists()).toBe(true);
        });
      });

      describe('when webPath is not provided', () => {
        beforeEach(() =>
          createComponent({ isSidePanelView: true, project: { fullPath: 'my-group/my-project' } }),
        );

        it('renders as plain text without a link', () => {
          expect(findProjectLabel().props('text')).toBe('my-group / my-project');
          expect(findProjectName().attributes('href')).toBeUndefined();
        });
      });

      describe('when no project is provided', () => {
        beforeEach(() => createComponent({ isSidePanelView: true }));

        it('does not render', () => {
          expect(findProjectName().exists()).toBe(false);
        });

        it('does not render the separator dot', () => {
          expect(findProjectSeparator().exists()).toBe(false);
        });
      });
    });

    describe('triggered user', () => {
      beforeEach(() => createComponent({ isSidePanelView: true, user: mockUser1 }));

      it('passes the user prop to AgentFlowTriggeredUser', () => {
        expect(findTriggeredUser().props('user')).toEqual(mockUser1);
      });
    });

    describe('session actions', () => {
      beforeEach(() => {
        createComponent({ isSidePanelView: true, status: 'RUNNING', canUpdateWorkflow: true });
      });

      it('passes correct props to AgentSessionActions', () => {
        expect(findSessionActions().props()).toMatchObject({
          status: 'RUNNING',
          canUpdateWorkflow: true,
          isSidePanel: true,
        });
      });

      it('does not offer the details toggle', () => {
        createComponent({ isSidePanelView: true, showDetailsToggle: true });

        expect(findSessionActions().props('showDetailsToggle')).toBe(false);
      });

      it('emits cancel-session when AgentSessionActions emits it', () => {
        findSessionActions().vm.$emit('cancel-session');
        expect(wrapper.emitted('cancel-session')).toHaveLength(1);
      });
    });
  });
});
