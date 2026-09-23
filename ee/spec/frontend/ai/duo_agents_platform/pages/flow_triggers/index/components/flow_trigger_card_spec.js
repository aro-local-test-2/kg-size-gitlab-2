import { GlAvatar, GlAvatarLink, GlCard, GlDisclosureDropdown, GlToggle } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import FlowTriggerCard from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/flow_trigger_card.vue';
import FlowTriggerEventTokens from 'ee/ai/duo_agents_platform/components/common/flow_trigger_event_tokens.vue';
import { FLOW_TRIGGERS_EDIT_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import { mockFlowTriggerFactory } from '../../mocks';

describe('FlowTriggerCard', () => {
  let wrapper;

  const createWrapper = ({
    trigger = mockFlowTriggerFactory(),
    isToggling = false,
    serviceAccountRole = null,
  } = {}) => {
    wrapper = mountExtended(FlowTriggerCard, {
      propsData: { trigger, isToggling, serviceAccountRole },
      stubs: {
        GlDisclosureDropdown: true,
      },
    });
  };

  const findCard = () => wrapper.findComponent(GlCard);
  const findToggle = () => wrapper.findComponent(GlToggle);
  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findEventTokens = () => wrapper.findComponent(FlowTriggerEventTokens);
  const findConfigPathLink = () => wrapper.findByTestId('flow-trigger-config-path');
  const findCatalogItem = () => wrapper.findByTestId('flow-trigger-catalog-item');
  const findTargetFallback = () => wrapper.findByTestId('flow-trigger-target-fallback');
  const findOwner = () => wrapper.findByTestId('flow-trigger-owner');
  const findRole = () => wrapper.findByTestId('flow-trigger-role');

  describe('rendering', () => {
    beforeEach(() => createWrapper());

    it('renders the description', () => {
      expect(wrapper.findByTestId('flow-trigger-description').text()).toBe('Test trigger');
    });

    it('renders the event tokens', () => {
      expect(findEventTokens().props('flowTrigger')).toMatchObject({ eventTypes: [0, 1] });
    });

    it('passes the trigger active state to the toggle', () => {
      expect(findToggle().props('value')).toBe(true);
    });

    it('is not subdued while active', () => {
      expect(findCard().classes()).not.toContain('gl-bg-subtle');
    });
  });

  describe('when the trigger is inactive', () => {
    beforeEach(() => createWrapper({ trigger: mockFlowTriggerFactory({ active: false }) }));

    it('subdues the card', () => {
      expect(findCard().classes()).toContain('gl-bg-subtle');
    });
  });

  describe('target', () => {
    it('renders a config-path link when the trigger has a config path', () => {
      createWrapper();

      expect(findConfigPathLink().exists()).toBe(true);
      expect(findConfigPathLink().attributes('href')).toBe('https://example.com/config/test.yml');
      expect(findConfigPathLink().text()).toBe('test.yml');
      expect(findCatalogItem().exists()).toBe(false);
    });

    it('renders the catalog item name when there is no config path', () => {
      createWrapper({
        trigger: mockFlowTriggerFactory({ configPath: null, configUrl: null }),
      });

      expect(findCatalogItem().text()).toBe('Test Flow');
      expect(findConfigPathLink().exists()).toBe(false);
    });

    it('falls back to Unknown when there is neither a config path nor a catalog item', () => {
      createWrapper({
        trigger: mockFlowTriggerFactory({
          configPath: null,
          configUrl: null,
          aiCatalogItemConsumer: null,
        }),
      });

      expect(findTargetFallback().text()).toBe('Unknown');
    });
  });

  describe('owner', () => {
    it('renders the owner avatar without the username text', () => {
      createWrapper();

      expect(findOwner().findComponent(GlAvatarLink).attributes('href')).toBe('/testuser');
      expect(findOwner().findComponent(GlAvatar).props('alt')).toBe('testuser');
    });

    it('falls back to Unknown when there is no owner', () => {
      createWrapper({ trigger: mockFlowTriggerFactory({ user: undefined }) });

      expect(findOwner().text()).toBe('Unknown');
    });
  });

  describe('service account role', () => {
    it('renders the role beside the avatar when provided', () => {
      createWrapper({ serviceAccountRole: 'Developer' });

      expect(findRole().text()).toBe('Developer');
    });

    it('does not render a role when none is provided', () => {
      createWrapper();

      expect(findRole().exists()).toBe(false);
    });

    it('does not render a role when there is no owner', () => {
      createWrapper({
        trigger: mockFlowTriggerFactory({ user: undefined }),
        serviceAccountRole: 'Developer',
      });

      expect(findRole().exists()).toBe(false);
    });
  });

  describe('actions', () => {
    beforeEach(() => createWrapper());

    it('links the edit action to the edit route', () => {
      const items = findDropdown().props('items');

      expect(items[0]).toMatchObject({
        text: 'Edit trigger',
        to: { name: FLOW_TRIGGERS_EDIT_ROUTE, params: { id: 1 } },
      });
    });

    it('emits delete with the trigger id from the delete action', () => {
      const items = findDropdown().props('items');
      items[1].action();

      expect(wrapper.emitted('delete')).toEqual([['gid://gitlab/Ai::FlowTrigger/1']]);
    });

    it('marks the delete action as the danger variant', () => {
      expect(findDropdown().props('items')[1]).toMatchObject({
        text: 'Delete trigger',
        variant: 'danger',
      });
    });
  });

  describe('toggle', () => {
    it('emits toggle with the id and new value', () => {
      createWrapper();
      findToggle().vm.$emit('change', false);

      expect(wrapper.emitted('toggle')).toEqual([
        [{ id: 'gid://gitlab/Ai::FlowTrigger/1', active: false }],
      ]);
    });

    it('shows the loading state while toggling', () => {
      createWrapper({ isToggling: true });

      expect(findToggle().props('isLoading')).toBe(true);
    });

    it('uses a state-independent accessible label', () => {
      createWrapper({ trigger: mockFlowTriggerFactory({ active: true }) });
      const activeLabel = findToggle().props('label');

      createWrapper({ trigger: mockFlowTriggerFactory({ active: false }) });

      expect(findToggle().props('label')).toBe('Turn trigger on or off: Test trigger');
      expect(activeLabel).toBe(findToggle().props('label'));
    });

    it('does not HTML-escape punctuation in the description', () => {
      createWrapper({
        trigger: mockFlowTriggerFactory({ description: "Don't review & merge" }),
      });

      expect(findToggle().props('label')).toBe("Turn trigger on or off: Don't review & merge");
    });
  });
});
