import { nextTick } from 'vue';
import { GlDrawer } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { PanelBreakpointInstance } from '~/panel_breakpoint_instance';
import AgentFlowDetails from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_details.vue';
import AgentFlowHeader from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_header.vue';
import AgentFlowDetailsPanel from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_details_panel.vue';
import AgentFlowDetailsOverlay from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_details_overlay.vue';
import { toggleInfoToggle } from 'ee/ai/graphql';
import AgentTodos from 'ee/ai/duo_agents_platform/pages/show/components/agent_todos.vue';
import AgentActivityLogs from 'ee/ai/duo_agents_platform/pages/show/components/agent_activity_logs.vue';
import AgentFlowErrorAlert from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_error_alert.vue';
import AgentFlowLinkedItems from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_linked_items.vue';
import NoCreditsBanner from 'ee/ai/duo_agents_platform/components/common/no_credits_banner.vue';
import UsageBillingForbiddenBanner from 'ee/ai/duo_agents_platform/components/common/usage_billing_forbidden_banner.vue';

import {
  mockDuoMessages,
  mockUser1,
  mockWorkItem,
  mockMergeRequest,
  mockWorkItemLinks,
  mockMergeRequestLinks,
  mockNoteLinks,
} from 'ee_jest/ai/mocks';

jest.mock('ee/ai/graphql', () => ({
  ...jest.requireActual('ee/ai/graphql'),
  toggleInfoToggle: jest.fn(),
}));

describe('AgentFlowDetails', () => {
  let wrapper;
  let breakpointHandler;

  const setBreakpoint = (current) => {
    jest
      .spyOn(PanelBreakpointInstance, 'isDesktop')
      .mockReturnValue(['lg', 'xl'].includes(current));
  };

  beforeEach(() => {
    setBreakpoint('xl');
    jest.spyOn(PanelBreakpointInstance, 'addBreakpointListener').mockImplementation((handler) => {
      breakpointHandler = handler;
    });
    jest.spyOn(PanelBreakpointInstance, 'removeBreakpointListener').mockImplementation(() => {});
  });

  const defaultProject = {
    id: 'gid://gitlab/Project/1',
    name: 'Test Project',
    fullPath: 'gitlab-org/test-project',
    namespace: {
      id: 'gid://gitlab/Group/1',
      name: 'gitlab-org',
    },
  };

  const defaultProps = {
    isLoading: false,
    status: 'RUNNING',
    humanStatus: 'Running',
    agentFlowDefinition: 'software_development',
    aiCatalogItemPath: '/explore/ai-catalog/flows/1799',
    title: '',
    duoMessages: mockDuoMessages,
    allExecutorUrls: ['https://gitlab.com/gitlab-org/gitlab/-/jobs/123'],
    createdAt: '2023-01-01T00:54:00Z',
    updatedAt: '2024-01-02T00:34:00Z',
    user: mockUser1,
    workflowId: '123',
    canUpdateWorkflow: true,
    workItem: mockWorkItem,
    mergeRequest: mockMergeRequest,
    workItemLinks: mockWorkItemLinks,
    mergeRequestLinks: mockMergeRequestLinks,
    noteLinks: mockNoteLinks,
    project: defaultProject,
  };

  const createComponent = ({ props = {}, provide = {}, apolloData = {} } = {}) => {
    wrapper = shallowMountExtended(AgentFlowDetails, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide: {
        isSidePanelView: false,
        creditsAvailable: true,
        ...provide,
      },
      data() {
        return {
          infoToggleStates: {},
          ...apolloData,
        };
      },
    });
  };

  const findAgentFlowHeader = () => wrapper.findComponent(AgentFlowHeader);
  const findAgentFlowDetailsPanel = () => wrapper.findComponent(AgentFlowDetailsPanel);
  const findAgentTodos = () => wrapper.findComponent(AgentTodos);
  const findAgentActivityLogs = () => wrapper.findComponent(AgentActivityLogs);
  const findAgentFlowLinkedItems = () => wrapper.findComponent(AgentFlowLinkedItems);
  const findErrorAlert = () => wrapper.findComponent(AgentFlowErrorAlert);
  const findNoCreditsBanner = () => wrapper.findComponent(NoCreditsBanner);
  const findUsageBillingForbiddenBanner = () => wrapper.findComponent(UsageBillingForbiddenBanner);
  const findContainer = () => wrapper.findByTestId('agent-flow-details-wrapper');
  const findDetailsOverlay = () => wrapper.findComponent(AgentFlowDetailsOverlay);

  describe('when not in side panel view', () => {
    beforeEach(() => {
      createComponent({ provide: { isSidePanelView: false } });
    });

    it('renders the agent flow header', () => {
      expect(findAgentFlowHeader().exists()).toBe(true);
    });

    it('renders the info and activity logs components', () => {
      expect(findAgentFlowDetailsPanel().exists()).toBe(true);
      expect(findAgentActivityLogs().exists()).toBe(true);
    });

    it('renders the agent todos component', () => {
      expect(findAgentTodos().exists()).toBe(true);
    });

    it('renders the agent todos above the activity log', () => {
      expect(
        findAgentTodos().element.compareDocumentPosition(findAgentActivityLogs().element),
      ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
    });
  });

  describe('when in side panel view', () => {
    beforeEach(() => {
      createComponent({ provide: { isSidePanelView: true } });
    });

    it('renders the agent flow header in side panel mode', () => {
      expect(findAgentFlowHeader().exists()).toBe(true);
      expect(findAgentFlowHeader().props('isSidePanelView')).toBe(true);
    });

    it('renders the activity logs component', () => {
      expect(findAgentActivityLogs().exists()).toBe(true);
    });

    it('renders the agent todos component', () => {
      expect(findAgentTodos().exists()).toBe(true);
    });

    it('passes isSidePanelView to AgentTodos', () => {
      expect(findAgentTodos().props('isSidePanelView')).toBe(true);
    });
  });

  describe('props passing', () => {
    beforeEach(() => {
      createComponent();
    });

    it('passes duoMessages to AgentActivityLogs', () => {
      expect(findAgentActivityLogs().props('duoMessages')).toEqual(mockDuoMessages);
    });

    it('passes duoMessages, status, and isSidePanelView to AgentTodos', () => {
      expect(findAgentTodos().props()).toEqual({
        duoMessages: mockDuoMessages,
        status: defaultProps.status,
        isSidePanelView: false,
      });
    });

    it('passes linked item props to AgentFlowLinkedItems', () => {
      expect(findAgentFlowLinkedItems().props()).toMatchObject({
        workItemLinks: mockWorkItemLinks,
        mergeRequestLinks: mockMergeRequestLinks,
        noteLinks: mockNoteLinks,
        workItem: mockWorkItem,
        mergeRequest: mockMergeRequest,
      });
    });

    it('passes correct props to AgentFlowDetailsPanel', () => {
      expect(findAgentFlowDetailsPanel().props()).toMatchObject({
        isLoading: defaultProps.isLoading,
        agentFlowDefinition: defaultProps.agentFlowDefinition,
        aiCatalogItemPath: defaultProps.aiCatalogItemPath,
        flowVersion: '',
        modelName: '',
        modelIdentifier: '',
        createdAt: defaultProps.createdAt,
        updatedAt: defaultProps.updatedAt,
        allExecutorUrls: defaultProps.allExecutorUrls,
        project: defaultProps.project,
      });
    });

    it('passes correct props to AgentFlowHeader', () => {
      expect(findAgentFlowHeader().props()).toMatchObject({
        isLoading: defaultProps.isLoading,
        title: defaultProps.title,
        status: defaultProps.status,
        humanStatus: defaultProps.humanStatus,
        createdAt: defaultProps.createdAt,
        updatedAt: defaultProps.updatedAt,
        project: defaultProps.project,
        user: defaultProps.user,
        canUpdateWorkflow: defaultProps.canUpdateWorkflow,
      });
    });
  });

  describe('session details toggle', () => {
    const findRail = () => wrapper.findByTestId('session-details-rail');
    const findDrawer = () => wrapper.findComponent(GlDrawer);
    const findDrawerInfo = () => findDrawer().findComponent(AgentFlowDetailsPanel);
    const resizeTo = (breakpoint) => {
      setBreakpoint(breakpoint);
      breakpointHandler();
    };

    describe('when in side panel view', () => {
      beforeEach(() => {
        setBreakpoint('md');
        createComponent({
          provide: { isSidePanelView: true },
        });
      });

      it('does not offer the toggle or a drawer', () => {
        expect(findAgentFlowHeader().props('showDetailsToggle')).toBe(false);
        expect(findDrawer().exists()).toBe(false);
      });
    });

    describe('when the panel is at least lg', () => {
      beforeEach(() => {
        setBreakpoint('lg');
        createComponent();
      });

      it('does not offer the toggle', () => {
        expect(findAgentFlowHeader().props('showDetailsToggle')).toBe(false);
      });

      it('renders the rail beside the content and no drawer', () => {
        expect(findRail().exists()).toBe(true);
        expect(findDrawer().exists()).toBe(false);
      });
    });

    describe.each(['md', 'sm'])('when the panel is %s', (breakpoint) => {
      beforeEach(() => {
        setBreakpoint(breakpoint);
        createComponent();
      });

      it('offers the toggle', () => {
        expect(findAgentFlowHeader().props('showDetailsToggle')).toBe(true);
      });

      it('renders the details in a closed drawer instead of the layout', () => {
        expect(findRail().exists()).toBe(false);
        expect(findDrawer().props('open')).toBe(false);
        expect(findAgentFlowHeader().props('detailsExpanded')).toBe(false);
      });

      it('links the header toggle to the drawer', () => {
        expect(findDrawer().attributes('id')).toBe(findAgentFlowHeader().props('detailsDrawerId'));
      });

      it('passes sidebar drawer props', () => {
        expect(findDrawer().props()).toMatchObject({
          variant: 'sidebar',
          headerSticky: true,
          zIndex: DRAWER_Z_INDEX,
        });
        expect(findDrawer().attributes('aria-label')).toBe('Session details');
      });

      describe('when the header emits toggle-details', () => {
        beforeEach(async () => {
          findAgentFlowHeader().vm.$emit('toggle-details');
          await nextTick();
        });

        it('opens the drawer with the details inside', () => {
          expect(findDrawer().props('open')).toBe(true);
          expect(findDrawerInfo().exists()).toBe(true);
          expect(findAgentFlowHeader().props('detailsExpanded')).toBe(true);
        });

        describe('when the header emits toggle-details again', () => {
          beforeEach(async () => {
            findAgentFlowHeader().vm.$emit('toggle-details');
            await nextTick();
          });

          it('closes the drawer', () => {
            expect(findDrawer().props('open')).toBe(false);
            expect(findAgentFlowHeader().props('detailsExpanded')).toBe(false);
          });
        });

        describe('when the drawer emits close', () => {
          beforeEach(async () => {
            findDrawer().vm.$emit('close');
            await nextTick();
          });

          it('closes the drawer', () => {
            expect(findDrawer().props('open')).toBe(false);
            expect(findAgentFlowHeader().props('detailsExpanded')).toBe(false);
          });
        });
      });

      describe('when the drawer is opened from a focused element and closes itself', () => {
        let opener;

        beforeEach(async () => {
          opener = document.createElement('button');
          document.body.appendChild(opener);
          opener.focus();

          findAgentFlowHeader().vm.$emit('toggle-details');
          await nextTick();
          findDrawer().vm.$emit('close');
          await nextTick();
        });

        afterEach(() => {
          opener.remove();
        });

        it('returns focus to that element', () => {
          expect(document.activeElement).toBe(opener);
        });
      });
    });

    describe('when the panel is resized across the lg breakpoint', () => {
      beforeEach(() => {
        setBreakpoint('sm');
        createComponent();
      });

      it('replaces the drawer with the open rail and hides the toggle at lg', async () => {
        findAgentFlowHeader().vm.$emit('toggle-details');
        await nextTick();
        expect(findDrawer().props('open')).toBe(true);

        resizeTo('lg');
        await nextTick();

        expect(findDrawer().exists()).toBe(false);
        expect(findRail().exists()).toBe(true);
        expect(findAgentFlowHeader().props('showDetailsToggle')).toBe(false);
      });

      it('returns to a closed drawer once it shrinks below lg', async () => {
        resizeTo('lg');
        await nextTick();
        expect(findRail().exists()).toBe(true);

        resizeTo('md');
        await nextTick();

        expect(findRail().exists()).toBe(false);
        expect(findDrawer().props('open')).toBe(false);
        expect(findAgentFlowHeader().props('showDetailsToggle')).toBe(true);
      });
    });

    describe('when the panel is resized between two drawer breakpoints', () => {
      beforeEach(async () => {
        setBreakpoint('md');
        createComponent();
        findAgentFlowHeader().vm.$emit('toggle-details');
        await nextTick();

        resizeTo('sm');
        await nextTick();
      });

      it('keeps the drawer open', () => {
        expect(findDrawer().props('open')).toBe(true);
        expect(findAgentFlowHeader().props('detailsExpanded')).toBe(true);
      });
    });

    describe('when destroyed', () => {
      it('removes the breakpoint listener', () => {
        setBreakpoint('sm');
        createComponent();

        wrapper.destroy();

        expect(PanelBreakpointInstance.removeBreakpointListener).toHaveBeenCalledWith(
          breakpointHandler,
        );
      });
    });
  });

  describe('cancel-session event', () => {
    beforeEach(() => {
      createComponent();
    });

    it('emits cancel-session when AgentFlowHeader emits it', () => {
      findAgentFlowHeader().vm.$emit('cancel-session');

      expect(wrapper.emitted('cancel-session')).toEqual([[]]);
    });
  });

  describe('session details overlay', () => {
    describe('in side panel view', () => {
      beforeEach(() => {
        createComponent({ provide: { isSidePanelView: true } });
      });

      it('renders the info overlay', () => {
        expect(findDetailsOverlay().exists()).toBe(true);
      });

      it('does not render the full info list', () => {
        expect(findAgentFlowDetailsPanel().exists()).toBe(false);
      });

      it('passes the session details to the overlay', () => {
        expect(findDetailsOverlay().props()).toMatchObject({
          workflowId: defaultProps.workflowId,
          agentFlowDefinition: defaultProps.agentFlowDefinition,
          aiCatalogItemPath: defaultProps.aiCatalogItemPath,
          allExecutorUrls: defaultProps.allExecutorUrls,
        });
      });

      describe('when the overlay is toggled', () => {
        beforeEach(() => findDetailsOverlay().vm.$emit('toggle'));

        it('persists the toggled state for the session', () => {
          expect(toggleInfoToggle).toHaveBeenCalledWith(defaultProps.workflowId, 'ai_panel');
        });
      });

      it('renders the overlay outside the two-column layout wrapper', () => {
        expect(findContainer().findComponent(AgentFlowDetailsOverlay).exists()).toBe(false);
      });
    });

    describe('session information toggle', () => {
      describe('when session info is visible', () => {
        beforeEach(() => {
          createComponent({
            provide: { isSidePanelView: true },
            apolloData: { infoToggleStates: { 'ai_panel:123': true } },
          });
        });

        it('opens the overlay', () => {
          expect(findDetailsOverlay().props('visible')).toBe(true);
        });
      });

      describe('when session info is not visible', () => {
        beforeEach(() => {
          createComponent({ provide: { isSidePanelView: true } });
        });

        it('closes the overlay', () => {
          expect(findDetailsOverlay().props('visible')).toBe(false);
        });
      });
    });

    describe('in page view', () => {
      beforeEach(() => {
        createComponent({ provide: { isSidePanelView: false } });
      });

      it('does not render the overlay', () => {
        expect(findDetailsOverlay().exists()).toBe(false);
      });
    });
  });

  describe('error alert', () => {
    describe('when status is not FAILED', () => {
      beforeEach(() => {
        createComponent({ props: { status: 'RUNNING' } });
      });

      it('does not render', () => {
        expect(findErrorAlert().exists()).toBe(false);
      });
    });

    describe('when status is FAILED', () => {
      beforeEach(() => {
        createComponent({ props: { status: 'FAILED' } });
      });

      it('renders', () => {
        expect(findErrorAlert().exists()).toBe(true);
      });

      it('hides after being dismissed', async () => {
        findErrorAlert().vm.$emit('dismiss');
        await nextTick();

        expect(findErrorAlert().exists()).toBe(false);
      });
    });

    describe('when status is FAILED and billing is forbidden', () => {
      beforeEach(() => {
        createComponent({
          props: { status: 'FAILED' },
          provide: { creditsAvailable: false, billingForbidden: true },
        });
      });

      it('does not render the error alert', () => {
        expect(findErrorAlert().exists()).toBe(false);
      });

      it('renders the billing forbidden banner instead', () => {
        expect(findUsageBillingForbiddenBanner().exists()).toBe(true);
      });
    });
  });

  describe('no credits banner', () => {
    describe('when credits are available', () => {
      beforeEach(() => {
        createComponent({ provide: { creditsAvailable: true } });
      });

      it('does not render', () => {
        expect(findNoCreditsBanner().exists()).toBe(false);
      });
    });

    describe('when credits are not available', () => {
      beforeEach(() => {
        createComponent({ provide: { creditsAvailable: false } });
      });

      it('renders', () => {
        expect(findNoCreditsBanner().exists()).toBe(true);
      });
    });

    describe('when credits are not available and billing is forbidden', () => {
      beforeEach(() => {
        createComponent({ provide: { creditsAvailable: false, billingForbidden: true } });
      });

      it('does not render', () => {
        expect(findNoCreditsBanner().exists()).toBe(false);
      });
    });
  });

  describe('usage billing forbidden banner', () => {
    describe('when credits are available', () => {
      beforeEach(() => {
        createComponent({ provide: { creditsAvailable: true, billingForbidden: true } });
      });

      it('does not render', () => {
        expect(findUsageBillingForbiddenBanner().exists()).toBe(false);
      });
    });

    describe('when billing is not forbidden', () => {
      beforeEach(() => {
        createComponent({ provide: { creditsAvailable: false, billingForbidden: false } });
      });

      it('does not render', () => {
        expect(findUsageBillingForbiddenBanner().exists()).toBe(false);
      });
    });

    describe('when credits are unavailable and billing is forbidden', () => {
      beforeEach(() => {
        createComponent({ provide: { creditsAvailable: false, billingForbidden: true } });
      });

      it('renders', () => {
        expect(findUsageBillingForbiddenBanner().exists()).toBe(true);
      });
    });
  });
});
