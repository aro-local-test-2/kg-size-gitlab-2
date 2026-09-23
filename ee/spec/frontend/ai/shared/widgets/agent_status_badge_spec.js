import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentStatusBadge from 'ee/ai/shared/widgets/agent_status_badge.vue';
import { AGENT_PLATFORM_STATUS_BADGE } from 'ee/ai/duo_agents_platform/constants';

describe('AgentStatusBadge', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AgentStatusBadge, {
      propsData: {
        status: 'RUNNING',
        humanStatus: 'Running',
        ...props,
      },
    });
  };

  const findBadge = () => wrapper.findComponent(GlBadge);

  it('renders the human-readable status as the badge text', () => {
    createComponent({ status: 'FINISHED', humanStatus: 'Complete' });

    expect(findBadge().text()).toBe('Complete');
  });

  describe('status to icon and variant mapping', () => {
    it.each(Object.entries(AGENT_PLATFORM_STATUS_BADGE))(
      'renders the badge appearance from AGENT_PLATFORM_STATUS_BADGE for %s',
      (status, { icon, variant }) => {
        createComponent({ status });

        expect(findBadge().props('icon')).toBe(icon);
        expect(findBadge().props('variant')).toBe(variant);
      },
    );

    it('falls back to the FAILED appearance for an unknown status', () => {
      createComponent({ status: 'SOMETHING_NEW' });

      expect(findBadge().props('icon')).toBe(AGENT_PLATFORM_STATUS_BADGE.FAILED.icon);
      expect(findBadge().props('variant')).toBe(AGENT_PLATFORM_STATUS_BADGE.FAILED.variant);
    });
  });
});
