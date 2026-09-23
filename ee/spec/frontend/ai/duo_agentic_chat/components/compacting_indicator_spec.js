import { GlLoadingIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CompactingIndicator from 'ee/ai/duo_agentic_chat/components/compacting_indicator.vue';

describe('CompactingIndicator', () => {
  let wrapper;

  const findIndicator = () => wrapper.findByTestId('compacting-indicator');

  beforeEach(() => {
    wrapper = shallowMountExtended(CompactingIndicator);
  });

  it('announces that the conversation is being compacted', () => {
    expect(findIndicator().text()).toBe('Compacting…');
  });

  it('shows the work as still in progress', () => {
    expect(findIndicator().findComponent(GlLoadingIcon).exists()).toBe(true);
  });
});
