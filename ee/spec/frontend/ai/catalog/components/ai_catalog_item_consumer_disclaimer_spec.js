import { shallowMount } from '@vue/test-utils';
import { GlAlert, GlSprintf } from '@gitlab/ui';
import AiCatalogItemConsumerDisclaimer from 'ee/ai/catalog/components/ai_catalog_item_consumer_disclaimer.vue';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import {
  AI_CATALOG_TYPE_AGENT,
  AI_CATALOG_TYPE_FLOW,
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
} from 'ee/ai/catalog/constants';
import {
  FLOW_TRIGGER_TYPE_MENTION,
  FLOW_TRIGGER_TYPE_SCHEDULE,
} from 'ee/ai/duo_agents_platform/constants';

describe('AiCatalogItemConsumerDisclaimer', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMount(AiCatalogItemConsumerDisclaimer, {
      propsData: {
        itemType: AI_CATALOG_TYPE_AGENT,
        canEnable: true,
        ...props,
      },
      stubs: {
        GlAlert,
        GlSprintf,
        HelpPageLink,
      },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findHelpPageLink = () => wrapper.findComponent(HelpPageLink);
  const findAllHelpPageLinks = () => wrapper.findAllComponents(HelpPageLink);
  const findCompositeIdentityLink = () =>
    findAllHelpPageLinks().wrappers.find(
      (link) => link.props('href') === 'user/duo_agent_platform/composite_identity',
    );
  const findRoleLink = () =>
    findAllHelpPageLinks().wrappers.find((link) => link.props('href') === 'user/permissions');

  describe('when the user can enable', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders inline guidance rather than an alert', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('agent disclaimer', () => {
    beforeEach(() => {
      createComponent({ itemType: AI_CATALOG_TYPE_AGENT });
    });

    it('displays enablement and access text', () => {
      expect(wrapper.text()).toContain(
        'When you enable this agent, all project members will be able to use it.',
      );
      expect(wrapper.text()).toContain(
        'When this agent runs, it will have access to the projects the user who runs it has access to.',
      );
    });

    it('renders the disclaimer as a two-item list', () => {
      expect(wrapper.findAll('ul li')).toHaveLength(2);
    });

    it('does not display composite identity link', () => {
      expect(findHelpPageLink().exists()).toBe(false);
    });
  });

  describe('flow disclaimer with no triggers selected', () => {
    beforeEach(() => {
      createComponent({ itemType: AI_CATALOG_TYPE_FLOW, triggerTypes: [] });
    });

    it('renders no disclaimer text or links', () => {
      expect(wrapper.text()).toBe('');
      expect(findHelpPageLink().exists()).toBe(false);
    });
  });

  describe('flow disclaimer with an event trigger selected', () => {
    beforeEach(() => {
      createComponent({
        itemType: AI_CATALOG_TYPE_FLOW,
        triggerTypes: [FLOW_TRIGGER_TYPE_MENTION.value],
      });
    });

    it('displays composite identity text', () => {
      expect(wrapper.text()).toContain(
        'This flow uses a service account with the Developer role by default, forming a composite identity with the user who triggers it, so only the more restrictive role applies. The service account can also access all other projects it is a member of. Change its role from the members page.',
      );
    });

    it('links the composite identity phrase to the docs', () => {
      expect(findCompositeIdentityLink().text()).toBe('composite identity');
    });

    it('links the Developer role to the roles docs', () => {
      expect(findRoleLink().props('href')).toBe('user/permissions');
      expect(findRoleLink().props('anchor')).toBe('roles');
      expect(findRoleLink().text()).toBe('Developer role');
    });
  });

  describe('flow disclaimer with only a scheduled trigger selected', () => {
    beforeEach(() => {
      createComponent({
        itemType: AI_CATALOG_TYPE_FLOW,
        triggerTypes: [FLOW_TRIGGER_TYPE_SCHEDULE.value],
      });
    });

    it('displays the scheduled service-account-only text', () => {
      expect(wrapper.text()).toContain(
        "This flow uses a service account with the Developer role by default. Scheduled runs have no triggering user, so only the service account's role applies. The service account can also access all other projects it is a member of. Change its role from the members page.",
      );
    });

    it('does not mention composite identity', () => {
      expect(wrapper.text()).not.toContain('composite identity');
    });
  });

  describe('flow disclaimer with both event and scheduled triggers selected', () => {
    beforeEach(() => {
      createComponent({
        itemType: AI_CATALOG_TYPE_FLOW,
        triggerTypes: [FLOW_TRIGGER_TYPE_MENTION.value, FLOW_TRIGGER_TYPE_SCHEDULE.value],
      });
    });

    it('displays both the composite identity and scheduled access text', () => {
      expect(wrapper.text()).toContain(
        "This flow uses a service account with the Developer role by default. Event-triggered runs form a composite identity with the user who triggers them, so only the more restrictive role applies. Scheduled runs have no triggering user, so only the service account's role applies. The service account can also access all other projects it is a member of. Change its role from the members page.",
      );
    });
  });

  describe('third-party flow disclaimer with an event trigger selected', () => {
    beforeEach(() => {
      createComponent({
        itemType: AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
        triggerTypes: [FLOW_TRIGGER_TYPE_MENTION.value],
      });
    });

    it('displays composite identity text', () => {
      expect(wrapper.text()).toContain(
        'This agent uses a service account with the Developer role by default, forming a composite identity with the user who triggers it, so only the more restrictive role applies. The service account can also access all other projects it is a member of. Change its role from the members page.',
      );
    });

    it('links the composite identity phrase to the docs', () => {
      expect(findCompositeIdentityLink().props('href')).toBe(
        'user/duo_agent_platform/composite_identity',
      );
    });
  });

  describe('when the user cannot enable', () => {
    it('renders the restricted message as a non-dismissible info alert', () => {
      createComponent({ itemType: AI_CATALOG_TYPE_FLOW, canEnable: false });

      expect(findAlert().props('variant')).toBe('info');
      expect(findAlert().props('dismissible')).toBe(false);
    });

    it('shows the restricted message for agents', () => {
      createComponent({ itemType: AI_CATALOG_TYPE_AGENT, canEnable: false });

      expect(wrapper.text()).toContain(
        'You must have the Maintainer or Owner role to enable an agent in a project.',
      );
      expect(wrapper.text()).not.toContain('When you enable this agent');
    });

    it('shows the restricted message for flows', () => {
      createComponent({ itemType: AI_CATALOG_TYPE_FLOW, canEnable: false });

      expect(wrapper.text()).toContain(
        'You must have the Maintainer or Owner role to enable a flow in a project.',
      );
      expect(findHelpPageLink().exists()).toBe(false);
    });

    it('shows the restricted message for third-party flows', () => {
      createComponent({ itemType: AI_CATALOG_TYPE_THIRD_PARTY_FLOW, canEnable: false });

      expect(wrapper.text()).toContain(
        'You must have the Maintainer or Owner role to enable an agent in a project.',
      );
      expect(findHelpPageLink().exists()).toBe(false);
    });
  });
});
