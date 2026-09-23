import { GlSkeletonLoader, GlToggle } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import setWindowLocation from 'helpers/set_window_location_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DecisionLogPanel from 'ee/work_items/components/decision_log/decision_log_panel.vue';
import DecisionLogFormModal from 'ee/work_items/components/decision_log/decision_log_form_modal.vue';
import DecisionLogItem from 'ee/work_items/components/decision_log/decision_log_item.vue';
import archiveDecisionMutation from 'ee/work_items/components/decision_log/graphql/archive_decision.mutation.graphql';
import createDecisionMutation from 'ee/work_items/components/decision_log/graphql/create_decision.mutation.graphql';
import updateDecisionMutation from 'ee/work_items/components/decision_log/graphql/update_decision.mutation.graphql';
import decisionLogQuery from 'ee/work_items/components/decision_log/graphql/decision_log.query.graphql';
import { createAlert } from '~/alert';
import toast from '~/vue_shared/plugins/global_toast';
import * as urlUtility from '~/lib/utils/url_utility';
import {
  buildMockDecision,
  decisionLogResponse,
  mockDecision,
  mockDecisions,
  mockFullPath,
  mockWorkItemIid,
} from './mock_data';

jest.mock('~/alert');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(VueApollo);

const participants = [{ id: 'gid://gitlab/User/1', name: 'Avery Patel' }];
const workItemId = 'gid://gitlab/WorkItem/7';
const workItemWebUrl = 'http://test.host/group/-/work_items/7';

const editedFields = {
  title: 'Ship SAML first, SCIM follows',
  resolvedBy: participants[0],
  description: 'The MVP needs authentication before it needs provisioning.',
  resolutionRationale: 'Splitting them would leave the MVP with accounts nothing creates.',
  sourceLink: '',
};

// Mirrors the decision the form opened on, so nothing counts as changed.
const unchangedFields = {
  title: mockDecision.title,
  description: mockDecision.description,
  resolutionRationale: mockDecision.resolutionRationale,
  sourceLink: '',
};

const updateSuccess = (decision = {}) => ({
  data: {
    workItemDecisionUpdate: {
      __typename: 'WorkItemDecisionUpdatePayload',
      decision: { ...mockDecision, ...decision },
      errors: [],
    },
  },
});

const createdDecision = buildMockDecision({
  id: 'gid://gitlab/WorkItems::Decision/99',
  title: 'Ship SAML first, SCIM follows',
});

const createSuccess = () => ({
  data: { workItemDecisionCreate: { decision: createdDecision, errors: [] } },
});

const MountingPortalStub = {
  name: 'MountingPortal',
  template: '<div data-testid="mounting-portal-stub"><slot /></div>',
};

const DynamicPanelStub = {
  name: 'DynamicPanel',
  props: ['header'],
  template: '<div data-testid="dynamic-panel"><slot /></div>',
};

const GlEmptyStateStub = {
  name: 'GlEmptyState',
  props: ['title', 'description'],
  template: '<div><slot name="actions" /></div>',
};

const logVariables = { fullPath: mockFullPath, iid: mockWorkItemIid };

const archivePayload = (errors = []) => ({
  data: {
    workItemDecisionArchive: {
      __typename: 'WorkItemDecisionArchivePayload',
      // The backend returns the decision whether or not it archived it, and only moves the state
      // when it did. Apollo normalises the record by id, which is what updates the cached log.
      decision: { ...mockDecisions[0], state: errors.length ? 'RESOLVED' : 'ARCHIVED' },
      errors,
    },
  },
});

describe('DecisionLogPanel', () => {
  let wrapper;
  let apolloProvider;
  let updateResolver;
  let createHandler;
  let archiveHandler;

  const decisions = mockDecisions;

  const createComponent = ({
    open = true,
    updateHandler = jest.fn().mockResolvedValue(updateSuccess()),
    archiveMutationHandler = jest.fn().mockResolvedValue(archivePayload()),
    createDecisionHandler = jest.fn().mockResolvedValue(createSuccess()),
    ...props
  } = {}) => {
    updateResolver = updateHandler;
    archiveHandler = archiveMutationHandler;
    createHandler = createDecisionHandler;

    apolloProvider = createMockApollo([
      [archiveDecisionMutation, archiveHandler],
      [createDecisionMutation, createHandler],
      [updateDecisionMutation, updateResolver],
    ]);

    // Both the created decision and the archived state land in the list the parent fetched, so
    // the cache has to hold that query for either update to read.
    apolloProvider.defaultClient.cache.writeQuery({
      query: decisionLogQuery,
      variables: logVariables,
      ...decisionLogResponse(),
    });

    wrapper = shallowMountExtended(DecisionLogPanel, {
      apolloProvider,
      propsData: {
        open,
        workItemId,
        workItemIid: mockWorkItemIid,
        decisions,
        participants,
        fullPath: mockFullPath,
        isGroup: true,
        workItemWebUrl,
        ...props,
      },
      stubs: {
        MountingPortal: MountingPortalStub,
        DynamicPanel: DynamicPanelStub,
        GlEmptyState: GlEmptyStateStub,
        // The toggle names itself through its label slot, which the default stub drops.
        GlToggle: stubComponent(GlToggle, { template: '<div><slot name="label"></slot></div>' }),
      },
    });
  };

  const findPanel = () => wrapper.findComponentByTestId('decision-log-panel');
  const findCount = () => wrapper.findByTestId('decision-log-count');
  const findShowArchivedToggle = () => wrapper.findComponentByTestId('show-archived-toggle');
  const findEmptyState = () => wrapper.findComponentByTestId('decision-log-empty-state');
  const findAllItems = () => wrapper.findAllComponents(DecisionLogItem);
  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findNewDecisionButton = () => wrapper.findComponentByTestId('new-decision-button');
  const findFormModal = () => wrapper.findComponent(DecisionLogFormModal);
  const pressEscape = () => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
  const cachedDecisions = () =>
    apolloProvider.defaultClient.readQuery({ query: decisionLogQuery, variables: logVariables })
      ?.namespace?.workItem?.features?.decisionLog?.decisions?.nodes ?? [];
  const cachedStates = () => cachedDecisions().map(({ state }) => state);

  beforeEach(() => {
    setWindowLocation('/');
    jest.spyOn(urlUtility, 'updateHistory').mockImplementation(() => {});
  });

  afterEach(() => {
    apolloProvider = null;
  });

  describe('when open', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the panel', () => {
      expect(findPanel().exists()).toBe(true);
    });

    it('titles the panel "Decision log"', () => {
      expect(findPanel().props('header')).toBe('Decision log');
    });

    it('heads the list with the number of decisions', () => {
      expect(findCount().text()).toBe('3 decisions');
      expect(findAllItems()).toHaveLength(3);
      expect(findEmptyState().exists()).toBe(false);
    });

    it('keeps the archived toggle away while nothing is archived', () => {
      expect(findShowArchivedToggle().exists()).toBe(false);
    });

    it('passes each decision through to its item', () => {
      expect(findAllItems().wrappers.map((item) => item.props('decision'))).toEqual(decisions);
    });

    it('gives every item the work item URL its copy link needs', () => {
      expect(findAllItems().wrappers.map((item) => item.props('workItemWebUrl'))).toEqual(
        decisions.map(() => workItemWebUrl),
      );
    });

    it('tells every item that no decision is targeted', () => {
      expect(findAllItems().wrappers.map((item) => item.props('targetAnchor'))).toEqual(
        decisions.map(() => ''),
      );
    });

    it('offers a New decision button', () => {
      expect(findNewDecisionButton().text()).toBe('New decision');
    });

    it('keeps the form closed', () => {
      expect(findFormModal().props('visible')).toBe(false);
    });

    it('deep-links the panel', () => {
      expect(urlUtility.updateHistory).toHaveBeenCalledWith({
        url: expect.stringContaining('show=decision-log'),
      });
    });

    describe('when the panel asks to close', () => {
      beforeEach(() => {
        findPanel().vm.$emit('close');
      });

      it('emits close', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('when an item sends the reader off to its comment', () => {
      beforeEach(() => {
        findAllItems().at(0).vm.$emit('view-comment');
      });

      it('emits close', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('when the user presses Escape', () => {
      beforeEach(() => {
        pressEscape();
      });

      it('emits close', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('when the New decision button is clicked', () => {
      beforeEach(async () => {
        findNewDecisionButton().vm.$emit('click');
        await nextTick();
      });

      it('opens the form for a new decision', () => {
        expect(findFormModal().props()).toMatchObject({ visible: true, decision: null });
      });

      it('passes the participants to the form', () => {
        expect(findFormModal().props('participants')).toEqual(participants);
      });

      it('passes the workspace to the form, so the decider dropdown can search', () => {
        expect(findFormModal().props()).toMatchObject({
          fullPath: 'group/project',
          isGroup: true,
        });
      });

      describe('when the form hides', () => {
        beforeEach(async () => {
          findFormModal().vm.$emit('hide');
          await nextTick();
        });

        it('closes the form', () => {
          expect(findFormModal().props('visible')).toBe(false);
        });
      });

      describe('when the form saves', () => {
        beforeEach(async () => {
          findFormModal().vm.$emit('save', editedFields);
          await waitForPromises();
        });

        it('records the decision against the work item', () => {
          expect(createHandler).toHaveBeenCalledWith({
            input: {
              workItemId,
              title: null,
              description: editedFields.description,
              sourceLink: null,
              resolution: {
                decision: editedFields.title,
                rationale: editedFields.resolutionRationale,
                resolvedById: participants[0].id,
              },
            },
          });
        });

        it('closes the form', () => {
          expect(findFormModal().props('visible')).toBe(false);
        });

        it('confirms the decision was created', () => {
          expect(toast).toHaveBeenCalledWith('Decision created.');
        });

        it('adds the new decision to the top of the cached list', () => {
          const cached = apolloProvider.clients.defaultClient.cache.readQuery({
            query: decisionLogQuery,
            variables: { fullPath: mockFullPath, iid: mockWorkItemIid },
          });

          expect(cached.namespace.workItem.features.decisionLog.decisions.nodes[0].id).toBe(
            createdDecision.id,
          );
        });
      });

      describe('while the decision is being saved', () => {
        it('tells the form it is saving and stops once the decision is saved', async () => {
          findFormModal().vm.$emit('save', editedFields);
          await nextTick();

          expect(findFormModal().props('saving')).toBe(true);

          await waitForPromises();

          expect(findFormModal().props('saving')).toBe(false);
        });
      });

      describe('when the link field is filled in', () => {
        it('sends it as the source link', async () => {
          const sourceLink = 'http://test.host/group/-/work_items/7#note_1';
          findFormModal().vm.$emit('save', { ...editedFields, sourceLink });
          await waitForPromises();

          expect(createHandler).toHaveBeenCalledWith(
            expect.objectContaining({ input: expect.objectContaining({ sourceLink }) }),
          );
        });
      });

      describe('when the fields are padded with whitespace', () => {
        beforeEach(async () => {
          findFormModal().vm.$emit('save', {
            ...editedFields,
            title: '   Move to weekly releases   ',
            sourceLink: '   ',
          });
          await waitForPromises();
        });

        it('trims the decision text', () => {
          expect(createHandler).toHaveBeenCalledWith(
            expect.objectContaining({
              input: expect.objectContaining({
                resolution: expect.objectContaining({ decision: 'Move to weekly releases' }),
              }),
            }),
          );
        });

        it('sends no source link, because a blank link points nowhere', () => {
          expect(createHandler).toHaveBeenCalledWith(
            expect.objectContaining({ input: expect.objectContaining({ sourceLink: null }) }),
          );
        });
      });

      describe('when recording the decision fails', () => {
        beforeEach(async () => {
          createComponent({
            createDecisionHandler: jest.fn().mockRejectedValue(new Error('nope')),
          });
          findNewDecisionButton().vm.$emit('click');
          await nextTick();
          findFormModal().vm.$emit('save', editedFields);
          await waitForPromises();
        });

        it('tells the user the decision was not saved', () => {
          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message: 'Something went wrong when saving the decision. Please try again.',
            }),
          );
        });

        it('leaves the form open', () => {
          expect(findFormModal().props('visible')).toBe(true);
        });

        it('does not confirm anything was created', () => {
          expect(toast).not.toHaveBeenCalled();
        });
      });
    });
  });

  describe('when a decision asks to be edited', () => {
    beforeEach(async () => {
      createComponent();
      findAllItems().at(0).vm.$emit('edit');
      await nextTick();
    });

    it('opens the form on that decision', () => {
      expect(findFormModal().props()).toMatchObject({ visible: true, decision: decisions[0] });
    });

    describe('when the form saves', () => {
      beforeEach(async () => {
        findFormModal().vm.$emit('save', editedFields);
        await waitForPromises();
      });

      it('saves the edited fields against that decision', () => {
        expect(updateResolver).toHaveBeenCalledWith({
          input: {
            id: decisions[0].id,
            title: editedFields.title,
            description: editedFields.description,
            resolutionRationale: editedFields.resolutionRationale,
          },
        });
      });

      it('closes the form', () => {
        expect(findFormModal().props('visible')).toBe(false);
      });
    });
  });

  describe('when only one field changed', () => {
    beforeEach(async () => {
      createComponent();
      findAllItems().at(0).vm.$emit('edit');
      await nextTick();
      findFormModal().vm.$emit('save', {
        ...editedFields,
        ...unchangedFields,
        title: 'A new title',
      });
      await waitForPromises();
    });

    it('sends that field alone, because the mutation rejects blank values', () => {
      expect(updateResolver).toHaveBeenCalledWith({
        input: { id: decisions[0].id, title: 'A new title' },
      });
    });
  });

  describe('when the user cleared a field', () => {
    beforeEach(async () => {
      createComponent();
      findAllItems().at(0).vm.$emit('edit');
      await nextTick();
      findFormModal().vm.$emit('save', { ...unchangedFields, resolutionRationale: '' });
      await waitForPromises();
    });

    it('leaves that field untouched, because the mutation cannot store a blank value', () => {
      expect(updateResolver).not.toHaveBeenCalled();
    });
  });

  describe('when nothing changed', () => {
    beforeEach(async () => {
      createComponent();
      findAllItems().at(0).vm.$emit('edit');
      await nextTick();
      findFormModal().vm.$emit('save', unchangedFields);
      await waitForPromises();
    });

    it('sends no mutation, because the mutation rejects an empty payload', () => {
      expect(updateResolver).not.toHaveBeenCalled();
    });

    it('closes the form', () => {
      expect(findFormModal().props('visible')).toBe(false);
    });
  });

  describe('when the mutation reports an error', () => {
    beforeEach(async () => {
      createComponent({
        updateHandler: jest.fn().mockResolvedValue({
          data: {
            workItemDecisionUpdate: {
              __typename: 'WorkItemDecisionUpdatePayload',
              decision: mockDecision,
              errors: ["Title can't be blank"],
            },
          },
        }),
      });
      findAllItems().at(0).vm.$emit('edit');
      await nextTick();
      findFormModal().vm.$emit('save', editedFields);
      await waitForPromises();
    });

    it('tells the user the decision was not saved', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Something went wrong when saving the decision. Please try again.',
        }),
      );
    });
  });

  describe('when saving an edited decision fails', () => {
    beforeEach(async () => {
      createComponent({ updateHandler: jest.fn().mockRejectedValue(new Error()) });
      findAllItems().at(0).vm.$emit('edit');
      await nextTick();
      findFormModal().vm.$emit('save', editedFields);
      await waitForPromises();
    });

    it('tells the user the decision was not saved', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Something went wrong when saving the decision. Please try again.',
        }),
      );
    });

    it('keeps the form open, so the changes are not lost', () => {
      expect(findFormModal().props('visible')).toBe(true);
    });
  });

  describe('when a decision asks to be archived', () => {
    beforeEach(async () => {
      createComponent();
      findAllItems().at(0).vm.$emit('archive');
      await waitForPromises();
    });

    it('archives the decision, without asking the user to confirm', () => {
      expect(archiveHandler).toHaveBeenCalledWith({ input: { id: decisions[0].id } });
    });

    it('tells the user the decision was archived', () => {
      expect(toast).toHaveBeenCalledWith('Decision archived.');
    });

    it('keeps the decision in the log, marked as archived', () => {
      expect(cachedDecisions().map(({ id }) => id)).toEqual(decisions.map(({ id }) => id));
      expect(cachedStates()).toEqual(['ARCHIVED', 'RESOLVED', 'RESOLVED']);
    });
  });

  describe('when archiving a decision fails', () => {
    beforeEach(async () => {
      createComponent({ archiveMutationHandler: jest.fn().mockRejectedValue(new Error()) });
      findAllItems().at(0).vm.$emit('archive');
      await waitForPromises();
    });

    it('tells the user the decision is still there', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Something went wrong when archiving the decision. Please try again.',
        }),
      );
    });

    it('leaves the decision unarchived', () => {
      expect(cachedStates()).toEqual(['RESOLVED', 'RESOLVED', 'RESOLVED']);
    });

    it('raises no toast', () => {
      expect(toast).not.toHaveBeenCalled();
    });
  });

  describe('when the server refuses to archive the decision', () => {
    beforeEach(async () => {
      createComponent({
        archiveMutationHandler: jest
          .fn()
          .mockResolvedValue(archivePayload(['Only resolved decisions can be archived'])),
      });
      findAllItems().at(0).vm.$emit('archive');
      await waitForPromises();
    });

    it('tells the user the decision is still there', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Something went wrong when archiving the decision. Please try again.',
        }),
      );
    });

    it('leaves the decision unarchived', () => {
      expect(cachedStates()).toEqual(['RESOLVED', 'RESOLVED', 'RESOLVED']);
    });

    it('raises no toast', () => {
      expect(toast).not.toHaveBeenCalled();
    });
  });

  describe('when the log holds archived decisions', () => {
    const archived = buildMockDecision({
      id: 'gid://gitlab/WorkItems::Decision/50',
      state: 'ARCHIVED',
    });
    const activeAndArchived = [...mockDecisions, archived];

    beforeEach(() => {
      createComponent({ decisions: activeAndArchived });
    });

    it('offers a toggle that names how many decisions are archived', () => {
      expect(findShowArchivedToggle().text()).toBe('Show archived (1)');
    });

    it('starts with the toggle off', () => {
      expect(findShowArchivedToggle().props('value')).toBe(false);
    });

    it('leaves the archived decisions out of the list', () => {
      expect(findAllItems().wrappers.map((item) => item.props('decision'))).toEqual(mockDecisions);
    });

    it('leaves the archived decisions out of the heading count', () => {
      expect(findCount().text()).toBe('3 decisions');
    });

    describe('when the toggle is turned on', () => {
      beforeEach(async () => {
        findShowArchivedToggle().vm.$emit('change', true);
        await nextTick();
      });

      it('adds the archived decisions to the list', () => {
        expect(findAllItems().wrappers.map((item) => item.props('decision'))).toEqual(
          activeAndArchived,
        );
      });

      it('keeps the heading counting only the active decisions', () => {
        expect(findCount().text()).toBe('3 decisions');
      });

      describe('when the toggle is turned off again', () => {
        beforeEach(async () => {
          findShowArchivedToggle().vm.$emit('change', false);
          await nextTick();
        });

        it('takes the archived decisions back out of the list', () => {
          expect(findAllItems().wrappers.map((item) => item.props('decision'))).toEqual(
            mockDecisions,
          );
        });
      });
    });
  });

  describe('when every decision in the log is archived', () => {
    const archived = mockDecisions.map((decision) => ({ ...decision, state: 'ARCHIVED' }));

    beforeEach(() => {
      createComponent({ decisions: archived });
    });

    it('shows no decisions until the reader asks for them', () => {
      expect(findAllItems()).toHaveLength(0);
      expect(findShowArchivedToggle().text()).toBe('Show archived (3)');
    });

    it('counts none of them in the heading', () => {
      expect(findCount().text()).toBe('0 decisions');
    });

    describe('when the toggle is turned on', () => {
      beforeEach(async () => {
        findShowArchivedToggle().vm.$emit('change', true);
        await nextTick();
      });

      it('shows all of them', () => {
        expect(findAllItems()).toHaveLength(3);
      });
    });
  });

  describe('when closed', () => {
    beforeEach(() => {
      createComponent({ open: false });
    });

    it('does not render the panel', () => {
      expect(findPanel().exists()).toBe(false);
    });

    it('does not touch the url', () => {
      expect(urlUtility.updateHistory).not.toHaveBeenCalled();
    });

    describe('when the user presses Escape', () => {
      beforeEach(() => {
        pressEscape();
      });

      it('does not emit close', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });
  });

  describe('with no decisions', () => {
    beforeEach(() => {
      createComponent({ decisions: [] });
    });

    it('shows an empty state instead of the list', () => {
      expect(findEmptyState().exists()).toBe(true);
      expect(findCount().exists()).toBe(false);
      expect(findAllItems()).toHaveLength(0);
    });

    it('explains how decisions get captured', () => {
      expect(findEmptyState().props()).toMatchObject({
        title: 'No decisions yet',
      });
    });

    it('offers the New decision button as the empty state action', () => {
      expect(findNewDecisionButton().text()).toBe('New decision');
      expect(findNewDecisionButton().props('variant')).toBe('confirm');
    });

    describe('when the empty state button is clicked', () => {
      beforeEach(async () => {
        findNewDecisionButton().vm.$emit('click');
        await nextTick();
      });

      it('opens the form for a new decision', () => {
        expect(findFormModal().props()).toMatchObject({ visible: true, decision: null });
      });
    });
  });

  describe('while the decisions are loading', () => {
    beforeEach(() => {
      createComponent({ decisions: [], isLoading: true });
    });

    it('holds the empty state back, because nothing has been fetched yet', () => {
      expect(findSkeleton().exists()).toBe(true);
      expect(findEmptyState().exists()).toBe(false);
      expect(findAllItems()).toHaveLength(0);
    });
  });

  describe('when Escape belongs to something else', () => {
    let focused;

    const focus = (element) => {
      focused = element;
      document.body.appendChild(focused);
      focused.focus();
    };

    afterEach(() => {
      focused?.remove();
      focused = undefined;
      document.body.classList.remove('modal-open');
    });

    describe.each(['INPUT', 'TEXTAREA'])('when focus is in a %s', (tagName) => {
      beforeEach(() => {
        focus(document.createElement(tagName));
        createComponent();

        pressEscape();
      });

      it('does not emit close', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });

    describe('when focus is in a rich text field', () => {
      beforeEach(() => {
        const editor = document.createElement('div');
        editor.setAttribute('contenteditable', 'true');
        editor.tabIndex = 0;
        focus(editor);
        createComponent();

        pressEscape();
      });

      it('does not emit close', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });

    describe('when a modal is open', () => {
      beforeEach(() => {
        document.body.classList.add('modal-open');
        createComponent();

        pressEscape();
      });

      it('does not emit close', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });
  });

  describe('when the decision log show param is set', () => {
    beforeEach(() => {
      setWindowLocation('?show=decision-log');
      createComponent();
    });

    it('does not rewrite the url', () => {
      expect(urlUtility.updateHistory).not.toHaveBeenCalled();
    });

    describe('when the panel closes', () => {
      beforeEach(async () => {
        await wrapper.setProps({ open: false });
      });

      it('clears the param', () => {
        expect(urlUtility.updateHistory).toHaveBeenCalledWith({
          url: expect.not.stringContaining('show='),
        });
      });
    });
  });

  describe('when the reader arrived on a decision anchor', () => {
    beforeEach(() => {
      setWindowLocation('?show=decision-log#decision_1');
      createComponent();
    });

    it('tells every item which decision is targeted', () => {
      expect(findAllItems().wrappers.map((item) => item.props('targetAnchor'))).toEqual(
        decisions.map(() => 'decision_1'),
      );
    });

    // Pasting a link while the panel is already open changes only the hash, so the browser fires
    // hashchange instead of reloading.
    describe('when the hash moves to another decision without a reload', () => {
      beforeEach(async () => {
        setWindowLocation('#decision_2');
        window.dispatchEvent(new HashChangeEvent('hashchange'));
        await nextTick();
      });

      it('hands the new anchor down', () => {
        expect(findAllItems().wrappers.map((item) => item.props('targetAnchor'))).toEqual(
          decisions.map(() => 'decision_2'),
        );
      });
    });

    describe('when the panel is destroyed', () => {
      beforeEach(() => {
        wrapper.destroy();
        setWindowLocation('#decision_2');
      });

      it('stops listening for hash changes', () => {
        expect(() => window.dispatchEvent(new HashChangeEvent('hashchange'))).not.toThrow();
      });
    });

    describe('when the panel closes', () => {
      beforeEach(async () => {
        await wrapper.setProps({ open: false });
      });

      it('clears the anchor along with the param', () => {
        expect(urlUtility.updateHistory).toHaveBeenCalledWith({
          url: expect.not.stringContaining('#'),
        });
      });
    });
  });

  describe('when the hash belongs to the page behind the panel', () => {
    beforeEach(() => {
      setWindowLocation('?show=decision-log#note_5');
      createComponent();
    });

    describe('when the panel closes', () => {
      beforeEach(async () => {
        await wrapper.setProps({ open: false });
      });

      it('leaves the hash alone', () => {
        expect(urlUtility.updateHistory).toHaveBeenCalledWith({
          url: expect.stringContaining('#note_5'),
        });
      });
    });
  });

  describe('when another panel has claimed the show param', () => {
    beforeEach(() => {
      setWindowLocation('?show=decision-log');
      createComponent();
      setWindowLocation('?show=workplan');
      urlUtility.updateHistory.mockClear();
    });

    describe('when the panel closes', () => {
      beforeEach(async () => {
        await wrapper.setProps({ open: false });
      });

      it('leaves the param alone', () => {
        expect(urlUtility.updateHistory).not.toHaveBeenCalled();
      });
    });
  });
});
