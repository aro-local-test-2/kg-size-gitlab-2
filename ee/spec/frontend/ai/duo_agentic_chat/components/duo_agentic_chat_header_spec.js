import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoAgenticChatHeader from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_header.vue';
import OrbitToggle from 'ee/ai/duo_agentic_chat/components/orbit_toggle.vue';
import PanelActionsPortal from '~/vue_shared/components/panel_actions_portal.vue';

describe('DuoAgenticChatHeader', () => {
  let wrapper;

  const createComponent = ({ propsData = {}, slots = {} } = {}) => {
    wrapper = shallowMountExtended(DuoAgenticChatHeader, {
      propsData: { singleHeader: true, ...propsData },
      slots,
    });
  };

  const findPanelActionsPortal = () => wrapper.findComponent(PanelActionsPortal);
  const findOrbitToggle = () => wrapper.findComponent(OrbitToggle);
  const lastTitle = () => wrapper.emitted('change-title')?.at(-1);
  const lastSubtitle = () => wrapper.emitted('change-subtitle')?.at(-1);

  describe('with the single header', () => {
    it('names an unstarted thread', () => {
      createComponent();

      expect(lastTitle()).toEqual(['New chat']);
    });

    it('prefers the thread title once there is one', () => {
      createComponent({ propsData: { threadTitle: 'Summarize this project' } });

      expect(lastTitle()).toEqual(['Summarize this project']);
    });

    it('emits the product name as the subtitle by default', () => {
      createComponent();

      expect(lastSubtitle()).toEqual(['GitLab Duo']);
    });

    it('emits the agent name as the subtitle when an agent is selected', () => {
      createComponent({ propsData: { currentAgent: { name: 'Security Analyst' } } });

      expect(lastSubtitle()).toEqual(['Security Analyst']);
    });

    it('re-emits when the thread title changes', async () => {
      createComponent();

      await wrapper.setProps({ threadTitle: 'Summarize this project' });

      expect(lastTitle()).toEqual(['Summarize this project']);
    });

    it('falls back to the unstarted name when the thread title is cleared', async () => {
      createComponent({ propsData: { threadTitle: 'Summarize this project' } });

      await wrapper.setProps({ threadTitle: null });

      expect(lastTitle()).toEqual(['New chat']);
    });

    describe('panel actions', () => {
      beforeEach(() => {
        createComponent({
          propsData: { orbitEnabled: true, currentAgent: { name: 'Security Analyst' } },
          slots: { default: '<div data-testid="session-actions"></div>' },
        });
      });

      it('renders the orbit toggle icon-only inside the panel actions portal', () => {
        expect(findPanelActionsPortal().exists()).toBe(true);
        expect(findOrbitToggle().props()).toMatchObject({
          value: true,
          iconOnly: true,
          currentAgent: { name: 'Security Analyst' },
        });
      });

      it('re-emits the orbit preference so the parent can keep it in sync', () => {
        findOrbitToggle().vm.$emit('change', false);

        expect(wrapper.emitted('change')).toEqual([[false]]);
      });

      it('renders the given actions alongside the orbit toggle', () => {
        expect(wrapper.findByTestId('session-actions').exists()).toBe(true);
      });
    });
  });

  describe('without the single header', () => {
    it('renders nothing', () => {
      createComponent({ propsData: { singleHeader: false } });

      expect(findPanelActionsPortal().exists()).toBe(false);
      // Vue 3 leaves a `<!---->` placeholder where the root `v-if` is false and
      // Vue 2 renders nothing at all, so assert on elements rather than markup.
      expect(wrapper.find('*').exists()).toBe(false);
    });

    it('leaves the title to the route', () => {
      createComponent({ propsData: { singleHeader: false } });

      expect(lastTitle()).toEqual([null]);
    });

    it('still surfaces a loaded thread title', () => {
      createComponent({ propsData: { singleHeader: false, threadTitle: 'Older thread' } });

      expect(lastTitle()).toEqual(['Older thread']);
    });

    it('emits only an empty subtitle', () => {
      createComponent({ propsData: { singleHeader: false } });

      expect(wrapper.emitted('change-subtitle')).toEqual([['']]);
    });
  });

  describe('on destroy', () => {
    it('clears both header values', () => {
      createComponent({ propsData: { threadTitle: 'Summarize this project' } });

      wrapper.destroy();

      expect(lastTitle()).toEqual([null]);
      expect(lastSubtitle()).toEqual(['']);
    });
  });
});
