import { GlAvatar, GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ClientTypeIcon from 'ee/agent_artifacts/components/client_type_icon.vue';

describe('ClientTypeIcon', () => {
  let wrapper;

  const createComponent = (clientType) => {
    wrapper = shallowMountExtended(ClientTypeIcon, {
      propsData: { clientType },
    });
  };

  describe('when the client type has a sprite icon', () => {
    beforeEach(() => {
      createComponent({ name: 'GitLab Duo', icon: 'tanuki-ai' });
    });

    it('renders the sprite icon', () => {
      const icon = wrapper.findComponent(GlIcon);

      expect(icon.exists()).toBe(true);
      expect(icon.props('name')).toBe('tanuki-ai');
    });

    it('does not render an avatar', () => {
      expect(wrapper.findComponent(GlAvatar).exists()).toBe(false);
    });
  });

  describe('when the client type has no sprite icon', () => {
    beforeEach(() => {
      createComponent({ name: 'Claude Code' });
    });

    it('renders an initial avatar for the agent name', () => {
      const avatar = wrapper.findComponent(GlAvatar);

      expect(avatar.exists()).toBe(true);
      expect(avatar.props('entityName')).toBe('Claude Code');
    });

    it('does not render an icon', () => {
      expect(wrapper.findComponent(GlIcon).exists()).toBe(false);
    });
  });
});
