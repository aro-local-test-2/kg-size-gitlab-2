import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentSessionInboxItem from 'ee/ai/duo_agents_platform/panel/agent_session_inbox_item.vue';
import InboxRow from 'ee/ai/duo_agents_platform/panel/inbox_row.vue';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import { buildInboxRowItem } from '../../mocks';

describe('AgentSessionInboxItem', () => {
  let wrapper;

  const createWrapper = (item = buildInboxRowItem()) => {
    wrapper = shallowMountExtended(AgentSessionInboxItem, {
      propsData: { item },
      stubs: { InboxRow },
      mocks: { $router: { push: jest.fn() } },
    });
  };

  const findRow = () => wrapper.findComponent(InboxRow);
  const findStatusIcon = () => wrapper.findComponent(AgentStatusIcon);
  const findStatusLabel = () => wrapper.findByTestId('item-status-label');

  describe('row', () => {
    it('hands the item to the row', () => {
      const item = buildInboxRowItem();
      createWrapper(item);

      expect(findRow().props('item')).toBe(item);
    });
  });

  describe('status label overrides', () => {
    it.each([
      ['INPUT_REQUIRED', 'Waiting for input'],
      ['PLAN_APPROVAL_REQUIRED', 'Approval gate'],
      ['TOOL_CALL_APPROVAL_REQUIRED', 'Confirm action'],
      ['STOPPED', 'Canceled'],
    ])('renders the renamed label for %s', (status, expectedLabel) => {
      createWrapper(buildInboxRowItem({ status, humanStatus: status.toLowerCase() }));

      expect(findStatusLabel().text()).toBe(expectedLabel);
    });

    it('falls through to formatAgentStatus(humanStatus) for an unmapped status', () => {
      createWrapper(buildInboxRowItem({ status: 'RUNNING', humanStatus: 'running' }));

      expect(findStatusLabel().text()).toBe('Running');
    });

    it('renders "Unknown" for an unmapped status with a null humanStatus', () => {
      createWrapper(buildInboxRowItem({ status: 'RUNNING', humanStatus: null }));

      expect(findStatusLabel().text()).toBe('Unknown');
    });

    it('passes the resolved label to AgentStatusIcon so the aria-label matches visible text', () => {
      createWrapper(buildInboxRowItem({ status: 'INPUT_REQUIRED', humanStatus: 'input required' }));

      expect(findStatusIcon().props('humanStatus')).toBe('Waiting for input');
    });
  });

  describe('status colour (semantic token)', () => {
    it.each([
      ['CREATED', 'gl-text-status-neutral'],
      ['RUNNING', 'gl-text-status-info'],
      ['FINISHED', 'gl-text-status-success'],
      ['PAUSED', 'gl-text-status-neutral'],
      ['STOPPED', 'gl-text-status-danger'],
      ['INPUT_REQUIRED', 'gl-text-status-warning'],
      ['PLAN_APPROVAL_REQUIRED', 'gl-text-status-warning'],
      ['TOOL_CALL_APPROVAL_REQUIRED', 'gl-text-status-warning'],
      ['FAILED', 'gl-text-status-danger'],
      ['UNKNOWN_FUTURE_STATUS', 'gl-text-status-neutral'],
    ])('applies %s → %s', (status, expectedClass) => {
      createWrapper(buildInboxRowItem({ status }));

      expect(findStatusLabel().classes()).toContain(expectedClass);
    });
  });
});
