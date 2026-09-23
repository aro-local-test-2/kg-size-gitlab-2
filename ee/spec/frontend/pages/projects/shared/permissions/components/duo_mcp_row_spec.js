import Vue from 'vue';
import VueApollo from 'vue-apollo';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoReadinessRow from '~/pages/projects/shared/permissions/components/duo_readiness_row.vue';
import DuoMcpRow from 'ee/pages/projects/shared/permissions/components/duo_mcp_row.vue';
import duoMcpServersCountQuery from 'ee/pages/projects/shared/permissions/graphql/duo_mcp_servers_count.query.graphql';

Vue.use(VueApollo);

describe('DuoMcpRow', () => {
  let wrapper;

  const countResponse = (count) => ({
    data: { project: { id: 'gid://gitlab/Project/1', duoMcpServersCount: count } },
  });

  const createComponent = ({ count = 0, handler } = {}) => {
    const queryHandler = handler || jest.fn().mockResolvedValue(countResponse(count));

    wrapper = shallowMountExtended(DuoMcpRow, {
      apolloProvider: createMockApollo([[duoMcpServersCountQuery, queryHandler]]),
      propsData: {
        mcp: { serversPath: '/group/project/-/automate/mcp-servers' },
        projectFullPath: 'group/project',
      },
    });

    return queryHandler;
  };

  const findRow = () => wrapper.findComponent(DuoReadinessRow);
  const findViewServersButton = () => wrapper.findComponentByTestId('mcp-view-servers-button');
  const findHowToConnectButton = () => wrapper.findComponentByTestId('mcp-how-to-connect-button');
  const findRetryButton = () => wrapper.findComponentByTestId('mcp-retry-button');

  describe('while the count is loading', () => {
    it('shows a loading row with its control disabled', () => {
      const queryHandler = createComponent();

      expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'group/project' });
      expect(findRow().props('status')).toBe('loading');
      expect(findHowToConnectButton().props('disabled')).toBe(true);
    });
  });

  describe('when no servers are connected', () => {
    beforeEach(async () => {
      createComponent({ count: 0 });
      await waitForPromises();
    });

    it('renders a neutral to-do row marked as an experiment', () => {
      expect(findRow().props('title')).toBe('MCP servers');
      expect(findRow().props('status')).toBe('todo');
      expect(findRow().props('description')).toBe(
        'Experiment. Agents can connect to tools your team already uses, such as Jira or Linear.',
      );
    });

    it('links to the MCP servers documentation', () => {
      expect(findHowToConnectButton().text()).toBe('How to connect');
      expect(findHowToConnectButton().props('disabled')).toBe(false);
      expect(findHowToConnectButton().attributes('href')).toBe(
        '/help/user/gitlab_duo/model_context_protocol/ai_catalog_mcp_servers.md',
      );
      expect(findHowToConnectButton().attributes('target')).toBe('_blank');
      expect(findViewServersButton().exists()).toBe(false);
    });
  });

  describe('when servers are connected', () => {
    it('displays a single server and shows the view servers button', async () => {
      createComponent({ count: 1 });
      await waitForPromises();

      expect(findRow().props('status')).toBe('done');
      expect(findRow().props('description')).toBe(
        '1 MCP server is connected. Agents can use it in this project.',
      );
      expect(findViewServersButton().exists()).toBe(true);
      expect(findHowToConnectButton().exists()).toBe(false);
    });

    it('displays multiple servers and links to the servers page', async () => {
      createComponent({ count: 2 });
      await waitForPromises();

      expect(findRow().props('description')).toBe(
        '2 MCP servers are connected. Agents can use them in this project.',
      );
      expect(findViewServersButton().attributes('href')).toBe(
        '/group/project/-/automate/mcp-servers',
      );
    });
  });

  describe('when the check fails', () => {
    it('marks only this row and offers a retry', async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('boom')) });
      await waitForPromises();

      expect(findRow().props('status')).toBe('error');
      expect(findRetryButton().exists()).toBe(true);
      expect(findViewServersButton().exists()).toBe(false);
      expect(findHowToConnectButton().exists()).toBe(false);
    });

    it('retries the check in place', async () => {
      const queryHandler = jest
        .fn()
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValueOnce(countResponse(1));
      createComponent({ handler: queryHandler });
      await waitForPromises();

      findRetryButton().vm.$emit('click');
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(2);
      expect(findRow().props('status')).toBe('done');
    });
  });

  describe('when the answer is redacted by authorization', () => {
    it('reads as an error rather than as no servers', async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue({
          data: { project: { id: 'gid://gitlab/Project/1', duoMcpServersCount: null } },
        }),
      });
      await waitForPromises();

      expect(findRow().props('status')).toBe('error');
      expect(findRetryButton().exists()).toBe(true);
    });
  });
});
