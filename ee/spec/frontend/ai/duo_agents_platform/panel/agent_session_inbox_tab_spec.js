import { GlSkeletonLoader } from '@gitlab/ui';
import AgentSessionInboxTab from 'ee/ai/duo_agents_platform/panel/agent_session_inbox_tab.vue';
import AgentFlowList from 'ee/ai/duo_agents_platform/components/common/agent_flow_list.vue';
import AgentSessionInboxItem from 'ee/ai/duo_agents_platform/panel/agent_session_inbox_item.vue';
import AgentSessionCliInboxItem from 'ee/ai/duo_agents_platform/panel/agent_session_cli_inbox_item.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { buildInboxRowItem, mockAgentFlows, mockInboxPageInfo } from '../../mocks';

describe('AgentSessionInboxTab', () => {
  let wrapper;

  const SLOTTED_EMPTY_STATE = {
    'empty-state': '<div data-testid="slotted-empty-state">Nothing here</div>',
  };

  const createWrapper = ({ slots = SLOTTED_EMPTY_STATE, ...props } = {}) => {
    wrapper = shallowMountExtended(AgentSessionInboxTab, {
      propsData: {
        testidPrefix: 'needs-decision',
        workflows: mockAgentFlows,
        pageInfo: mockInboxPageInfo,
        ...props,
      },
      slots,
      stubs: { AgentFlowList },
    });
  };

  const findList = () => wrapper.findComponent(AgentFlowList);
  const findSlottedEmptyState = () => wrapper.findByTestId('slotted-empty-state');

  describe('when loading', () => {
    beforeEach(() => createWrapper({ loading: true }));

    it('renders skeletons under a testid derived from the prefix', () => {
      expect(wrapper.findByTestId('needs-decision-loading').exists()).toBe(true);
      expect(wrapper.findAllComponents(GlSkeletonLoader)).toHaveLength(3);
    });

    it('renders neither the list nor the empty state', () => {
      expect(findList().exists()).toBe(false);
      expect(findSlottedEmptyState().exists()).toBe(false);
    });
  });

  describe('when empty and the tab supplies its own empty state', () => {
    beforeEach(() => createWrapper({ showEmptyState: true, workflows: [] }));

    it('renders the slot instead of the list', () => {
      expect(findSlottedEmptyState().exists()).toBe(true);
      expect(findList().exists()).toBe(false);
    });
  });

  describe('when empty and the tab supplies no empty state', () => {
    beforeEach(() =>
      createWrapper({ testidPrefix: 'all', workflows: [], showEmptyState: true, slots: {} }),
    );

    it("falls back to the list's own empty state", () => {
      expect(findList().props('showEmptyState')).toBe(true);
      expect(findSlottedEmptyState().exists()).toBe(false);
    });
  });

  describe('when there are sessions to show', () => {
    beforeEach(() => createWrapper());

    it('forwards the list props, including a prefixed testid', () => {
      expect(wrapper.findComponentByTestId('needs-decision-flow-list').exists()).toBe(true);
      expect(findList().props()).toMatchObject({
        workflows: mockAgentFlows,
        workflowsPageInfo: mockInboxPageInfo,
        showEmptyState: false,
      });
      expect(findList().props('showProjectInfo')).toBe(false);
    });

    it('renders one redesigned row per workflow, with the workflow bound', () => {
      const rows = wrapper.findAllComponents(AgentSessionInboxItem);

      expect(rows).toHaveLength(mockAgentFlows.length);
      expect(rows.at(0).props('item')).toEqual(mockAgentFlows[0]);
    });

    describe('row dispatch', () => {
      const findRows = (Component) => wrapper.findAllComponents(Component);

      it.each`
        signal                                 | overrides
        ${'sourceType is CLI'}                 | ${{ sourceType: 'CLI', flowMetadataVersion: null }}
        ${'flow version ends in -interactive'} | ${{ flowMetadataVersion: '2.1.0-interactive' }}
      `('renders a CLI row for a session waiting for input when $signal', ({ overrides }) => {
        const item = buildInboxRowItem({ status: 'INPUT_REQUIRED', ...overrides });
        createWrapper({ workflows: [item] });

        expect(findRows(AgentSessionCliInboxItem)).toHaveLength(1);
        expect(findRows(AgentSessionCliInboxItem).at(0).props('item')).toEqual(item);
        expect(findRows(AgentSessionInboxItem)).toHaveLength(0);
      });

      it.each`
        row                                          | status                           | flowMetadataVersion
        ${'a web session waiting for input'}         | ${'INPUT_REQUIRED'}              | ${'2.0.0'}
        ${'a /goal CLI session waiting for input'}   | ${'INPUT_REQUIRED'}              | ${'2.0.0-goal'}
        ${'a failed CLI session'}                    | ${'FAILED'}                      | ${'2.1.0-interactive'}
        ${'a CLI session waiting for tool approval'} | ${'TOOL_CALL_APPROVAL_REQUIRED'} | ${'2.1.0-interactive'}
      `('renders the regular row for $row', ({ status, flowMetadataVersion }) => {
        const item = buildInboxRowItem({ status, flowMetadataVersion });
        createWrapper({ workflows: [item] });

        expect(findRows(AgentSessionInboxItem)).toHaveLength(1);
        expect(findRows(AgentSessionInboxItem).at(0).props('item')).toEqual(item);
        expect(findRows(AgentSessionCliInboxItem)).toHaveLength(0);
      });
    });

    it.each(['next-page', 'prev-page'])('re-emits %s from the list', async (event) => {
      await findList().vm.$emit(event);

      expect(wrapper.emitted(event)).toHaveLength(1);
    });
  });
});
