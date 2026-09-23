import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlBadge, GlPopover } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import McpServerActivityCard from 'ee/ai/governance/components/dashboard/cards/mcp_server_activity_card.vue';
import getMcpServersQuery from 'ee/ai/governance/graphql/queries/get_mcp_servers.query.graphql';

Vue.use(VueApollo);

const serverNode = (
  id,
  name,
  { blockStatus = 'ACTIVE', description = `${name} description` } = {},
) => ({
  __typename: 'AiCatalogMcpServer',
  id: `gid://gitlab/Ai::Catalog::McpServer/${id}`,
  name,
  description,
  url: `https://mcp.example.com/${id}`,
  blockStatus,
});

const mcpServersResponse = (nodes) => ({
  data: {
    aiCatalogMcpServers: {
      __typename: 'AiCatalogMcpServerConnection',
      nodes,
      pageInfo: {
        __typename: 'PageInfo',
        hasNextPage: false,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: null,
      },
    },
  },
});

describe('McpServerActivityCard', () => {
  let wrapper;

  const createComponent = ({ provide = {}, handler } = {}) => {
    const apolloProvider = createMockApollo([
      [getMcpServersQuery, handler ?? jest.fn().mockResolvedValue(mcpServersResponse([]))],
    ]);

    wrapper = mountExtended(McpServerActivityCard, {
      apolloProvider,
      provide: {
        groupFullPath: 'gitlab-org',
        projectFullPath: '',
        ...provide,
      },
    });
  };

  const findRows = () => wrapper.findAllByTestId('mcp-server-row');
  const findStatusBadges = () => wrapper.findAllComponentsByTestId('mcp-server-status-badge');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');
  const findDescriptions = () => wrapper.findAllByTestId('mcp-server-description');
  const findPopovers = () => wrapper.findAllComponents(GlPopover);

  it('renders a row per MCP server with an Active status', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(
          mcpServersResponse([serverNode(1, 'Filesystem'), serverNode(2, 'GitHub')]),
        ),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(2);
    expect(findRows().at(0).text()).toContain('Filesystem');
    expect(findStatusBadges().at(0).text()).toBe('Active');
    expect(findStatusBadges().at(0).props('variant')).toBe('success');
  });

  it('renders a popover with the full description for each described server', async () => {
    const longDescription =
      'A very long MCP server description that does not fit on a single truncated row';
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(
          mcpServersResponse([
            serverNode(1, 'Filesystem', { description: longDescription }),
            serverNode(2, 'GitHub'),
          ]),
        ),
    });
    await waitForPromises();

    expect(findPopovers()).toHaveLength(2);
    expect(findPopovers().at(0).text()).toBe(longDescription);
    expect(findPopovers().at(0).props('target')).toBe(findDescriptions().at(0).attributes('id'));
    expect(findDescriptions().at(0).attributes('tabindex')).toBe('0');
    expect(findPopovers().at(1).props('target')).not.toBe(findPopovers().at(0).props('target'));
  });

  it.each([null, ''])('renders no popover when the description is %p', async (description) => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(mcpServersResponse([serverNode(1, 'Filesystem', { description })])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(1);
    expect(findDescriptions()).toHaveLength(0);
    expect(findPopovers()).toHaveLength(0);
  });

  it('shows a Blocked status for blocked servers', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(
          mcpServersResponse([
            serverNode(1, 'Filesystem'),
            serverNode(2, 'Blocked one', { blockStatus: 'BLOCKED' }),
          ]),
        ),
    });
    await waitForPromises();

    const badge = findRows().at(1).findComponent(GlBadge);
    expect(badge.text()).toBe('Blocked');
    expect(badge.props('variant')).toBe('danger');
  });

  it('scopes the query to the group', async () => {
    const handler = jest.fn().mockResolvedValue(mcpServersResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({
        groupFullPath: 'gitlab-org',
        projectFullPath: null,
        first: 5,
      }),
    );
  });

  it('scopes the query to the project in project mode', async () => {
    const handler = jest.fn().mockResolvedValue(mcpServersResponse([]));
    createComponent({ provide: { projectFullPath: 'gitlab-org/test' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({
        projectFullPath: 'gitlab-org/test',
        groupFullPath: null,
        first: 5,
      }),
    );
  });

  it('links to the MCP registry tab', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().text()).toBe('View MCP registry');
    expect(findViewAllLink().attributes('href')).toBe('?tab=mcp-registry');
  });

  it('shows the empty state when no servers exist', async () => {
    createComponent();
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
  });

  it('shows an error alert when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('failed')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
  });

  it('clears the error state when a later fetch succeeds', async () => {
    const handler = jest
      .fn()
      .mockRejectedValueOnce(new Error('failed'))
      .mockResolvedValue(mcpServersResponse([serverNode(1, 'Alpha')]));
    createComponent({ handler });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);

    wrapper.vm.$apollo.queries.mcpServers.refetch();
    await waitForPromises();

    expect(findAlert().exists()).toBe(false);
    expect(findRows()).toHaveLength(1);
  });

  it('states that it is not scoped to the selected date range', async () => {
    createComponent();
    await waitForPromises();

    expect(wrapper.findByTestId('card-footnote').text()).toBe(
      'Shows the current registry, not filtered by date range.',
    );
  });
});
