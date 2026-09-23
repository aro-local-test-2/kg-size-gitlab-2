import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { makeMockUserCalloutDismisser } from 'helpers/mock_user_callout_dismisser';
import setWindowLocation from 'helpers/set_window_location_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import * as urlUtility from '~/lib/utils/url_utility';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import workItemParticipantsQuery from '~/work_items/graphql/work_item_participants.query.graphql';
import WorkItemDecisionLog from 'ee/work_items/components/decision_log/work_item_decision_log.vue';
import DecisionLogHeaderButton from 'ee/work_items/components/decision_log/decision_log_header_button.vue';
import DecisionLogOnboardingPopover from 'ee/work_items/components/decision_log/decision_log_onboarding_popover.vue';
import DecisionLogPanel from 'ee/work_items/components/decision_log/decision_log_panel.vue';
import decisionLogQuery from 'ee/work_items/components/decision_log/graphql/decision_log.query.graphql';
import {
  decisionLogResponse,
  mockDecisions,
  mockFullPath as fullPath,
  mockWorkItemId as workItemId,
  mockWorkItemIid as workItemIid,
} from './mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

const buildUser = (id, name) => ({
  __typename: 'UserCore',
  id: `gid://gitlab/User/${id}`,
  name,
  username: name.toLowerCase().replace(' ', '.'),
  avatarUrl: '/avatar.png',
  webUrl: `/${name}`,
  webPath: `/${name}`,
});

const participants = [buildUser(1, 'Avery Patel'), buildUser(2, 'Jordan Lee')];

const workItem = { id: workItemId, iid: workItemIid };

const participantsResponse = (nodes = participants) => ({
  data: {
    namespace: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      workItem: {
        __typename: 'WorkItem',
        id: workItemId,
        widgets: [
          {
            __typename: 'WorkItemWidgetParticipants',
            type: 'PARTICIPANTS',
            participants: { __typename: 'UserCoreConnection', count: nodes.length, nodes },
          },
        ],
      },
    },
  },
});

describe('WorkItemDecisionLog', () => {
  let wrapper;
  let dismissCallout;

  const workItemWebUrl = 'http://gdk.test/group/project/-/work_items/1';

  const createComponent = ({
    hasPanelPortal = true,
    isPanelOpen = false,
    decisionsHandler = jest.fn().mockResolvedValue(decisionLogResponse()),
    shouldShowCallout = true,
    participantsHandler = jest.fn().mockResolvedValue(participantsResponse()),
    ...props
  } = {}) => {
    wrapper = shallowMountExtended(WorkItemDecisionLog, {
      apolloProvider: createMockApollo([
        [decisionLogQuery, decisionsHandler],
        [workItemParticipantsQuery, participantsHandler],
      ]),
      provide: { fullPath, isGroup: true },
      propsData: { workItem, workItemWebUrl, hasPanelPortal, isPanelOpen, ...props },
      stubs: {
        DecisionLogPanel: true,
        UserCalloutDismisser: makeMockUserCalloutDismisser({
          dismiss: dismissCallout,
          shouldShowCallout,
        }),
      },
    });
  };

  const findHeaderButton = () => wrapper.findComponent(DecisionLogHeaderButton);
  const findOnboardingPopover = () => wrapper.findComponent(DecisionLogOnboardingPopover);
  const findPanel = () => wrapper.findComponent(DecisionLogPanel);
  const triggerPopstate = () => window.dispatchEvent(new PopStateEvent('popstate'));

  beforeEach(() => {
    dismissCallout = jest.fn();
    setWindowLocation('/');
  });

  describe('while the query is in flight', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the button', () => {
      expect(findHeaderButton().exists()).toBe(true);
    });

    it('has nothing to count yet, and reports the query as loading to the panel', () => {
      expect(findHeaderButton().props('count')).toBe(0);
      expect(findPanel().props('isLoading')).toBe(true);
      expect(findPanel().props('decisions')).toEqual([]);
    });
  });

  describe('once the query answers', () => {
    let decisionsHandler;

    beforeEach(async () => {
      decisionsHandler = jest.fn().mockResolvedValue(decisionLogResponse());
      createComponent({ decisionsHandler });
      await waitForPromises();
    });

    it('asks the server for the decision log of this work item', () => {
      expect(decisionsHandler).toHaveBeenCalledWith({ fullPath, iid: workItemIid });
    });

    it('stops reporting the query as loading', () => {
      expect(findPanel().props('isLoading')).toBe(false);
    });

    it('counts the fetched decisions on the button and in the panel', () => {
      expect(findHeaderButton().props('count')).toBe(3);
      expect(findPanel().props('decisions')).toHaveLength(3);
    });

    it('hands the work item URL to the panel', () => {
      expect(findPanel().props('workItemWebUrl')).toBe(workItemWebUrl);
    });

    it('hands the fetched decisions to the panel', () => {
      expect(findPanel().props('decisions')).toEqual(mockDecisions);
    });
  });

  describe('when some of the fetched decisions are archived', () => {
    beforeEach(async () => {
      const [first, ...rest] = mockDecisions;
      const nodes = [{ ...first, state: 'ARCHIVED' }, ...rest];

      createComponent({
        decisionsHandler: jest.fn().mockResolvedValue(decisionLogResponse(nodes)),
      });
      await waitForPromises();
    });

    it('leaves the archived ones out of the button count', () => {
      expect(findHeaderButton().props('count')).toBe(2);
    });

    it('still hands every decision to the panel, which decides what to show', () => {
      expect(findPanel().props('decisions')).toHaveLength(3);
    });
  });

  describe('when the work item has no decision log widget', () => {
    beforeEach(async () => {
      const response = decisionLogResponse();
      response.data.namespace.workItem.features.decisionLog = null;

      createComponent({ decisionsHandler: jest.fn().mockResolvedValue(response) });
      await waitForPromises();
    });

    it('reports no decisions', () => {
      expect(findPanel().props('decisions')).toEqual([]);
      expect(findHeaderButton().props('count')).toBe(0);
    });
  });

  describe('when the query fails', () => {
    beforeEach(async () => {
      createComponent({
        decisionsHandler: jest.fn().mockRejectedValue(new Error('Query failed')),
      });
      await waitForPromises();
    });

    it('tells the user the decision log could not be fetched', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Something went wrong when fetching the decision log. Please try again.',
        captureError: true,
        error: expect.any(Error),
      });
    });
  });

  describe('when the panel is open', () => {
    beforeEach(() => {
      createComponent({ isPanelOpen: true });
    });

    it('opens the panel', () => {
      expect(findPanel().props('open')).toBe(true);
    });

    describe('when the panel asks to close', () => {
      beforeEach(() => {
        findPanel().vm.$emit('close');
      });

      it('emits request-panel with no panel', () => {
        expect(wrapper.emitted('request-panel')).toEqual([[null]]);
      });
    });

    describe('when the button asks to close', () => {
      beforeEach(() => {
        findHeaderButton().vm.$emit('close');
      });

      it('emits request-panel with no panel', () => {
        expect(wrapper.emitted('request-panel')).toEqual([[null]]);
      });
    });
  });

  describe('when the button asks to open the panel', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('requests the decision log panel', () => {
      findHeaderButton().vm.$emit('open');

      expect(wrapper.emitted('request-panel')).toEqual([['decision-log']]);
    });
  });

  describe('when there is no panel portal to render into', () => {
    let visitUrlSpy;

    beforeEach(() => {
      visitUrlSpy = jest.spyOn(urlUtility, 'visitUrl').mockImplementation(() => {});
    });

    describe('and the full page can be reached', () => {
      beforeEach(async () => {
        createComponent({ hasPanelPortal: false });
        await waitForPromises();
      });

      it('hands off to the full page with the panel requested', () => {
        findHeaderButton().vm.$emit('open');

        expect(visitUrlSpy).toHaveBeenCalledWith(`${workItemWebUrl}?show=decision-log`);
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });
    });

    describe('and there is no url to hand off to', () => {
      beforeEach(async () => {
        createComponent({ hasPanelPortal: false, workItemWebUrl: '' });
        await waitForPromises();
      });

      it('falls back to the panel', () => {
        findHeaderButton().vm.$emit('open');

        expect(visitUrlSpy).not.toHaveBeenCalled();
        expect(wrapper.emitted('request-panel')).toEqual([['decision-log']]);
      });
    });
  });

  describe('the workspace the work item lives in', () => {
    beforeEach(() => {
      createComponent();
    });

    it('is handed to the panel, so the decider dropdown can search it', () => {
      expect(findPanel().props()).toMatchObject({ fullPath, isGroup: true });
    });
  });

  describe('deciders', () => {
    describe('once the participants answer', () => {
      let participantsHandler;

      beforeEach(async () => {
        participantsHandler = jest.fn().mockResolvedValue(participantsResponse());
        createComponent({ participantsHandler });
        await waitForPromises();
      });

      it('asks for the participants of this work item', () => {
        expect(participantsHandler).toHaveBeenCalledWith({
          fullPath,
          iid: workItemIid,
          useWorkItemFeatures: false,
        });
      });

      it('offers every participant to the panel as a decider', () => {
        expect(findPanel().props('participants')).toEqual(participants);
      });
    });

    describe('when the work item has no participants', () => {
      beforeEach(async () => {
        createComponent({
          participantsHandler: jest.fn().mockResolvedValue(participantsResponse([])),
        });
        await waitForPromises();
      });

      it('offers no deciders', () => {
        expect(findPanel().props('participants')).toEqual([]);
      });
    });

    describe('when the participants query fails', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException').mockImplementation(() => {});
        createComponent({ participantsHandler: jest.fn().mockRejectedValue(new Error('nope')) });
        await waitForPromises();
      });

      it('reports the failure without an alert, because the log itself still reads', () => {
        expect(Sentry.captureException).toHaveBeenCalled();
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('offers no deciders', () => {
        expect(findPanel().props('participants')).toEqual([]);
      });
    });
  });

  describe('when the url requests the decision log', () => {
    beforeEach(() => {
      setWindowLocation('?show=decision-log');
    });

    describe('on the full page', () => {
      beforeEach(() => {
        createComponent();
      });

      it('requests the decision log panel', () => {
        expect(wrapper.emitted('request-panel')).toEqual([['decision-log']]);
      });
    });

    describe('and there is no panel portal to render into', () => {
      beforeEach(() => {
        createComponent({ hasPanelPortal: false });
      });

      it('does not request a panel', () => {
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });
    });
  });

  describe('when the url requests another panel', () => {
    beforeEach(() => {
      setWindowLocation('?show=workplan');
      createComponent();
    });

    it('does not request a panel', () => {
      expect(wrapper.emitted('request-panel')).toBeUndefined();
    });
  });

  describe('the onboarding popover', () => {
    describe('when the user has not seen it yet', () => {
      beforeEach(async () => {
        createComponent();
        await nextTick();
      });

      it('anchors it to the button it is introducing', () => {
        expect(findHeaderButton().attributes('id')).toMatch(/^decision-log-button-/);
        expect(findOnboardingPopover().props('target')).toBe(findHeaderButton().attributes('id'));
      });

      it('reports the log as untouched', () => {
        expect(findOnboardingPopover().props('hasOpenedDecisionLog')).toBe(false);
      });

      describe('when the popover asks to be dismissed', () => {
        beforeEach(() => {
          findOnboardingPopover().vm.$emit('dismiss');
        });

        it('records the dismissal against the user, so it does not come back', () => {
          expect(dismissCallout).toHaveBeenCalled();
        });
      });

      describe('when the user opens the log instead', () => {
        beforeEach(async () => {
          findHeaderButton().vm.$emit('open');
          await nextTick();
        });

        it('reports the log as opened, which retires the popover', () => {
          expect(findOnboardingPopover().props('hasOpenedDecisionLog')).toBe(true);
        });
      });
    });

    describe('when the panel was already open before the popover mounted', () => {
      beforeEach(async () => {
        createComponent({ isPanelOpen: true });
        await nextTick();
      });

      it('reports the log as opened', () => {
        expect(findOnboardingPopover().props('hasOpenedDecisionLog')).toBe(true);
      });
    });

    describe('when the url deep links to the log', () => {
      beforeEach(async () => {
        setWindowLocation('?show=decision-log');
        createComponent();
        await nextTick();
      });

      it('reports the log as opened', () => {
        expect(findOnboardingPopover().props('hasOpenedDecisionLog')).toBe(true);
      });
    });

    describe('when the user has already seen it', () => {
      beforeEach(async () => {
        createComponent({ shouldShowCallout: false });
        await nextTick();
      });

      it('is not rendered', () => {
        expect(findOnboardingPopover().exists()).toBe(false);
      });
    });
  });

  describe('on popstate', () => {
    describe('when the user navigates back to the deep link', () => {
      beforeEach(() => {
        createComponent();

        setWindowLocation('?show=decision-log');
        triggerPopstate();
      });

      it('requests the decision log panel', () => {
        expect(wrapper.emitted('request-panel')).toEqual([['decision-log']]);
      });
    });

    describe('when the param is gone', () => {
      beforeEach(() => {
        setWindowLocation('?show=decision-log');
        createComponent({ isPanelOpen: true });

        setWindowLocation('/');
        triggerPopstate();
      });

      it('requests no panel', () => {
        expect(wrapper.emitted('request-panel')).toEqual([[null]]);
      });
    });

    describe('when the url names another panel', () => {
      beforeEach(() => {
        setWindowLocation('?show=decision-log');
        createComponent({ isPanelOpen: true });

        setWindowLocation('?show=workplan');
        triggerPopstate();
      });

      it('leaves the panel state alone', () => {
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });
    });

    describe('when the panel is already in the requested state', () => {
      beforeEach(() => {
        setWindowLocation('?show=decision-log');
        createComponent({ isPanelOpen: true });

        triggerPopstate();
      });

      it('does not request a panel', () => {
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });
    });

    describe('when the component is destroyed', () => {
      beforeEach(() => {
        createComponent();
        wrapper.destroy();

        setWindowLocation('?show=decision-log');
        triggerPopstate();
      });

      it('does not request a panel', () => {
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });
    });

    describe('when there is no panel portal to render into', () => {
      beforeEach(() => {
        createComponent({ hasPanelPortal: false });

        setWindowLocation('?show=decision-log');
        triggerPopstate();
      });

      it('does not request a panel', () => {
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });
    });
  });
});
