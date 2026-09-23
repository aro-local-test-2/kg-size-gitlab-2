import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FlowTriggersList from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/flow_triggers_list.vue';
import FlowTriggerCard from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/flow_trigger_card.vue';
import { mockFlowTriggerFactory } from '../../mocks';

describe('FlowTriggersList', () => {
  let wrapper;

  const triggers = [
    mockFlowTriggerFactory({ id: 'gid://gitlab/Ai::FlowTrigger/1' }),
    mockFlowTriggerFactory({ id: 'gid://gitlab/Ai::FlowTrigger/2' }),
  ];

  const createWrapper = ({
    aiFlowTriggers = triggers,
    togglingIds = [],
    serviceAccountRoles = {},
  } = {}) => {
    wrapper = shallowMountExtended(FlowTriggersList, {
      propsData: { aiFlowTriggers, togglingIds, serviceAccountRoles },
    });
  };

  const findCards = () => wrapper.findAllComponents(FlowTriggerCard);

  it('renders a card per trigger', () => {
    createWrapper();

    expect(findCards()).toHaveLength(2);
    expect(findCards().at(0).props('trigger')).toBe(triggers[0]);
  });

  it("resolves each card's role from the service account map by user id", () => {
    createWrapper({
      serviceAccountRoles: { 'gid://gitlab/User/1': 'Developer' },
    });

    // Both mock triggers share user/1, so both resolve to Developer.
    expect(findCards().at(0).props('serviceAccountRole')).toBe('Developer');
    expect(findCards().at(1).props('serviceAccountRole')).toBe('Developer');
  });

  it('passes a null role when the owner has no mapped role', () => {
    createWrapper({ serviceAccountRoles: {} });

    expect(findCards().at(0).props('serviceAccountRole')).toBe(null);
  });

  it('marks a card as toggling when its id is in togglingIds', () => {
    createWrapper({ togglingIds: ['gid://gitlab/Ai::FlowTrigger/2'] });

    expect(findCards().at(0).props('isToggling')).toBe(false);
    expect(findCards().at(1).props('isToggling')).toBe(true);
  });

  it('re-emits delete-trigger from a card', () => {
    createWrapper();
    findCards().at(0).vm.$emit('delete', 'gid://gitlab/Ai::FlowTrigger/1');

    expect(wrapper.emitted('delete-trigger')).toEqual([['gid://gitlab/Ai::FlowTrigger/1']]);
  });

  it('re-emits toggle-trigger from a card', () => {
    createWrapper();
    const payload = { id: 'gid://gitlab/Ai::FlowTrigger/1', active: false };
    findCards().at(0).vm.$emit('toggle', payload);

    expect(wrapper.emitted('toggle-trigger')).toEqual([[payload]]);
  });
});
