import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlDisclosureDropdown, GlLink, GlSprintf, GlToggle } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createAlert } from '~/alert';
import ConfirmActionModal from '~/vue_shared/components/confirm_action_modal.vue';
import AiCatalogItemField from 'ee/ai/catalog/components/ai_catalog_item_field.vue';
import TriggerField from 'ee/ai/catalog/components/trigger_field.vue';
import FlowTriggerEventTokens from 'ee/ai/duo_agents_platform/components/common/flow_trigger_event_tokens.vue';
import aiCatalogFlowQuery from 'ee/ai/catalog/graphql/queries/ai_catalog_flow.query.graphql';
import updateAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import deleteAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/delete_ai_flow_trigger.mutation.graphql';
import {
  FLOW_TRIGGERS_EDIT_ROUTE,
  FLOW_TRIGGERS_NEW_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import {
  mockAiCatalogFlowResponse,
  mockFlow,
  mockFlowConfigurationForProject,
  mockFlowTrigger,
  mockFlowTriggerSecond,
} from '../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

const mockUpdateSuccess = {
  data: {
    aiFlowTriggerUpdate: {
      aiFlowTrigger: { id: mockFlowTrigger.id, active: false, __typename: 'AiFlowTrigger' },
      errors: [],
    },
  },
};

const mockUpdateWithErrors = {
  data: {
    aiFlowTriggerUpdate: {
      aiFlowTrigger: null,
      errors: ['Trigger could not be updated'],
    },
  },
};

const mockDeleteSuccess = {
  data: {
    aiFlowTriggerDelete: {
      errors: [],
    },
  },
};

const mockDeleteWithErrors = {
  data: {
    aiFlowTriggerDelete: {
      errors: ['Trigger could not be deleted'],
    },
  },
};

describe('TriggerFieldSpec', () => {
  let wrapper;
  let updateHandler;
  let deleteHandler;
  const toastShow = jest.fn();

  const createComponent = ({ props = {}, provide = {}, handlers = {} } = {}) => {
    updateHandler = handlers.update || jest.fn().mockResolvedValue(mockUpdateSuccess);
    deleteHandler = handlers.delete || jest.fn().mockResolvedValue(mockDeleteSuccess);

    const mockApollo = createMockApollo([
      [updateAiFlowTrigger, updateHandler],
      [deleteAiFlowTrigger, deleteHandler],
      [aiCatalogFlowQuery, jest.fn().mockResolvedValue(mockAiCatalogFlowResponse)],
    ]);
    // The delete mutation awaits a refetch of the flow query. refetchQueries only
    // refetches active queries, so subscribe to make it observable (mirrors VueApollo).
    mockApollo.defaultClient
      .watchQuery({
        query: aiCatalogFlowQuery,
        variables: {
          id: mockFlow.id,
          projectId: 'gid://gitlab/Project/1',
          groupId: 'gid://gitlab/Group/1',
        },
      })
      .subscribe();

    wrapper = shallowMountExtended(TriggerField, {
      apolloProvider: mockApollo,
      propsData: {
        item: mockFlow,
        ...props,
      },
      provide,
      mocks: {
        $toast: { show: toastShow },
      },
      stubs: {
        GlSprintf,
      },
    });
  };

  const withTriggers = () => ({
    props: {
      item: { ...mockFlow, configurationForProject: mockFlowConfigurationForProject },
    },
    provide: { glAbilities: { manageAiFlowTriggers: true } },
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  const findEventTokens = () => wrapper.findComponent(FlowTriggerEventTokens);
  const findAllEventTokens = () => wrapper.findAllComponents(FlowTriggerEventTokens);
  const findAllToggles = () => wrapper.findAllComponents(GlToggle);
  const findAllDropdowns = () => wrapper.findAllComponents(GlDisclosureDropdown);
  const findModal = () => wrapper.findComponent(ConfirmActionModal);

  describe('field title', () => {
    it('renders the "Trigger conditions" title', () => {
      createComponent(withTriggers());

      expect(wrapper.findComponent(AiCatalogItemField).props('title')).toBe('Trigger conditions');
    });
  });

  describe('when flowTriggers is empty', () => {
    const emptyConfig = {
      item: {
        ...mockFlow,
        configurationForProject: { ...mockFlowConfigurationForProject, flowTriggers: [] },
      },
    };

    describe('when user can manage triggers', () => {
      beforeEach(() => {
        createComponent({
          props: emptyConfig,
          provide: { glAbilities: { manageAiFlowTriggers: true } },
        });
      });

      it('renders "Add a trigger" message with link', () => {
        const link = wrapper.findComponent(GlLink);

        expect(wrapper.text()).toContain(
          'No triggers configured. Add a trigger to make this flow available.',
        );
        expect(link.props('to')).toEqual({ name: FLOW_TRIGGERS_NEW_ROUTE });
      });

      it('does not render the trigger event tokens', () => {
        expect(findEventTokens().exists()).toBe(false);
      });
    });

    describe('when user cannot manage triggers', () => {
      beforeEach(() => {
        createComponent({
          props: emptyConfig,
          provide: { glAbilities: { manageAiFlowTriggers: false } },
        });
      });

      it('renders "No triggers configured" without an actions dropdown', () => {
        expect(wrapper.text()).toContain('No triggers configured.');
        expect(findAllDropdowns()).toHaveLength(0);
      });
    });
  });

  describe('when flowTriggers exist and user can manage triggers', () => {
    beforeEach(() => {
      createComponent(withTriggers());
    });

    it('renders a token group per stored trigger', () => {
      const eventTokens = findAllEventTokens();

      expect(eventTokens).toHaveLength(2);
      expect(eventTokens.at(0).props('flowTrigger')).toEqual(mockFlowTrigger);
      expect(eventTokens.at(1).props('flowTrigger')).toEqual(mockFlowTriggerSecond);
    });

    it('renders a toggle per trigger reflecting its active state', () => {
      const toggles = findAllToggles();

      expect(toggles).toHaveLength(2);
      expect(toggles.at(0).props('value')).toBe(true);
      expect(toggles.at(1).props('value')).toBe(false);
    });

    it('renders an actions dropdown per trigger with Edit and Delete items', () => {
      const dropdowns = findAllDropdowns();

      expect(dropdowns).toHaveLength(2);

      const firstItems = dropdowns.at(0).props('items');
      expect(firstItems).toHaveLength(2);
      expect(firstItems[0].text).toBe('Edit');
      expect(firstItems[0].to).toEqual({
        name: FLOW_TRIGGERS_EDIT_ROUTE,
        params: { id: 73 },
      });
      expect(firstItems[1].text).toBe('Delete');

      expect(dropdowns.at(1).props('items')[0].to).toEqual({
        name: FLOW_TRIGGERS_EDIT_ROUTE,
        params: { id: 74 },
      });
    });
  });

  describe('when user cannot manage triggers', () => {
    beforeEach(() => {
      createComponent({
        props: {
          item: { ...mockFlow, configurationForProject: mockFlowConfigurationForProject },
        },
        provide: { glAbilities: { manageAiFlowTriggers: false } },
      });
    });

    it('renders the trigger event tokens', () => {
      expect(findEventTokens().exists()).toBe(true);
    });

    it('does not render toggles or actions dropdowns', () => {
      expect(findAllToggles()).toHaveLength(0);
      expect(findAllDropdowns()).toHaveLength(0);
    });
  });

  describe('when item is foundational', () => {
    beforeEach(() => {
      createComponent({
        props: {
          item: {
            ...mockFlow,
            foundational: true,
            configurationForProject: mockFlowConfigurationForProject,
          },
        },
        provide: { glAbilities: { manageAiFlowTriggers: true } },
      });
    });

    it('does not render toggles or actions dropdowns', () => {
      expect(findAllToggles()).toHaveLength(0);
      expect(findAllDropdowns()).toHaveLength(0);
    });
  });

  describe('toggling a trigger', () => {
    describe('when the mutation succeeds', () => {
      beforeEach(async () => {
        createComponent(withTriggers());
        findAllToggles().at(0).vm.$emit('change', false);
        await waitForPromises();
      });

      it('calls the update mutation with the trigger id and new state', () => {
        expect(updateHandler).toHaveBeenCalledWith({
          input: { id: mockFlowTrigger.id, active: false },
        });
      });

      it('shows the off confirmation toast', () => {
        expect(toastShow).toHaveBeenCalledWith('Trigger turned off');
      });
    });

    describe('when turning a trigger on', () => {
      beforeEach(async () => {
        createComponent(withTriggers());
        findAllToggles().at(1).vm.$emit('change', true);
        await waitForPromises();
      });

      it('shows the on confirmation toast', () => {
        expect(toastShow).toHaveBeenCalledWith('Trigger turned on');
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        createComponent({
          ...withTriggers(),
          handlers: { update: jest.fn().mockResolvedValue(mockUpdateWithErrors) },
        });
        findAllToggles().at(0).vm.$emit('change', false);
        await waitForPromises();
      });

      it('surfaces the error and does not show a toast', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Trigger could not be updated' });
        expect(toastShow).not.toHaveBeenCalled();
      });
    });

    describe('when the mutation rejects', () => {
      beforeEach(async () => {
        createComponent({
          ...withTriggers(),
          handlers: { update: jest.fn().mockRejectedValue(new Error('boom')) },
        });
        findAllToggles().at(0).vm.$emit('change', false);
        await waitForPromises();
      });

      it('surfaces a generic error', () => {
        expect(createAlert).toHaveBeenCalledWith(expect.objectContaining({ captureError: true }));
      });
    });
  });

  describe('deleting a trigger', () => {
    const openDeleteModal = async () => {
      const items = findAllDropdowns().at(0).props('items');
      items[1].action();
      await nextTick();
    };

    it('does not render the confirm modal until Delete is selected', () => {
      createComponent(withTriggers());

      expect(findModal().exists()).toBe(false);
    });

    describe('when Delete is selected', () => {
      beforeEach(async () => {
        createComponent(withTriggers());
        await openDeleteModal();
      });

      it('opens the confirm modal', () => {
        expect(findModal().exists()).toBe(true);
      });

      describe('and confirmed', () => {
        beforeEach(async () => {
          await findModal().props('actionFn')();
          await waitForPromises();
        });

        it('calls the delete mutation with the trigger id', () => {
          expect(deleteHandler).toHaveBeenCalledWith({ id: mockFlowTrigger.id });
        });

        it('shows a confirmation toast', () => {
          expect(toastShow).toHaveBeenCalledWith('Trigger deleted successfully.');
        });

        it('closes the confirm modal', () => {
          expect(findModal().exists()).toBe(false);
        });
      });
    });

    describe('when the delete mutation returns errors', () => {
      beforeEach(async () => {
        createComponent({
          ...withTriggers(),
          handlers: { delete: jest.fn().mockResolvedValue(mockDeleteWithErrors) },
        });
        await openDeleteModal();
        await findModal().props('actionFn')();
        await waitForPromises();
      });

      it('surfaces the error and does not show a toast', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Trigger could not be deleted' });
        expect(toastShow).not.toHaveBeenCalled();
      });
    });

    describe('when the delete mutation rejects', () => {
      beforeEach(async () => {
        createComponent({
          ...withTriggers(),
          handlers: { delete: jest.fn().mockRejectedValue(new Error('boom')) },
        });
        await openDeleteModal();

        try {
          await findModal().props('actionFn')();
        } catch {
          // ConfirmActionModal rethrows; swallow so the assertion can run.
        }
        await waitForPromises();
      });

      it('surfaces a generic error', () => {
        expect(createAlert).toHaveBeenCalledWith(expect.objectContaining({ captureError: true }));
      });
    });
  });
});
