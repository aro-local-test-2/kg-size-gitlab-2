import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import AuditTrailCard from 'ee/ai/governance/components/dashboard/cards/audit_trail_card.vue';
import getAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_agent_artifacts.query.graphql';
import getProjectAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_project_agent_artifacts.query.graphql';

Vue.use(VueApollo);

const sessionNode = (id) => ({
  __typename: 'DuoWorkflowSessionArtifact',
  id: `gid://gitlab/Ai::DuoWorkflows::Workflow/${id}`,
  workflowDefinition: 'software_development',
  agentType: null,
  webPath: `/gitlab-duo/test/-/automate/agent-sessions/${id}`,
  downloadPath: `/download/${id}`,
  auditEventsCount: 3,
  workflowCreatedAt: '2026-07-01T10:00:00Z',
  project: {
    __typename: 'Project',
    id: 'gid://gitlab/Project/1',
    name: 'test',
    webPath: '/gitlab-duo/test',
    fullPath: 'gitlab-duo/test',
  },
  triggeredBy: {
    __typename: 'UserCore',
    id: 'gid://gitlab/User/1',
    name: 'Alice Smith',
    username: 'alice',
    avatarUrl: '/uploads/-/system/user/avatar/1/avatar.png',
    webPath: '/alice',
  },
});

const artifactsConnection = (nodes) => ({
  __typename: 'DuoWorkflowSessionArtifactConnection',
  count: nodes.length,
  nodes,
  pageInfo: {
    __typename: 'PageInfo',
    hasNextPage: false,
    hasPreviousPage: false,
    startCursor: null,
    endCursor: null,
  },
});

const groupResponse = (nodes) => ({
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      duoWorkflowSessionArtifacts: artifactsConnection(nodes),
    },
  },
});

const projectResponse = (nodes) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      duoWorkflowSessionArtifacts: artifactsConnection(nodes),
    },
  },
});

describe('AuditTrailCard', () => {
  let wrapper;

  const createComponent = ({
    provide = {},
    props = {},
    connectedAgentsFilter = true,
    groupHandler,
    projectHandler,
  } = {}) => {
    const apolloProvider = createMockApollo([
      [getAgentArtifactsQuery, groupHandler ?? jest.fn().mockResolvedValue(groupResponse([]))],
      [
        getProjectAgentArtifactsQuery,
        projectHandler ?? jest.fn().mockResolvedValue(projectResponse([])),
      ],
    ]);

    wrapper = mountExtended(AuditTrailCard, {
      apolloProvider,
      propsData: props,
      provide: {
        groupFullPath: 'gitlab-duo',
        projectFullPath: null,
        glFeatures: { aiGovernanceConnectedAgentsFilter: connectedAgentsFilter },
        ...provide,
      },
    });
  };

  const findRows = () => wrapper.findAllByTestId('audit-trail-row');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  const findChevron = (row) => row.find('[data-testid="audit-trail-chevron"]');

  it('renders a row per recent session with a humanized title', async () => {
    createComponent({
      groupHandler: jest.fn().mockResolvedValue(groupResponse([sessionNode(246234)])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(1);
    expect(findRows().at(0).text()).toContain('Session #246234');
    expect(findRows().at(0).text()).toContain('3 audit events');
  });

  it('links a session with a webPath and shows a chevron', async () => {
    createComponent({
      groupHandler: jest.fn().mockResolvedValue(groupResponse([sessionNode(246234)])),
    });
    await waitForPromises();

    const row = findRows().at(0);
    expect(row.element.tagName).toBe('A');
    expect(row.attributes('href')).toBe('/gitlab-duo/test/-/automate/agent-sessions/246234');
    expect(findChevron(row).exists()).toBe(true);
  });

  it('renders a session without a webPath as plain text, no link or chevron', async () => {
    const node = { ...sessionNode(246234), webPath: null };
    createComponent({ groupHandler: jest.fn().mockResolvedValue(groupResponse([node])) });
    await waitForPromises();

    const row = findRows().at(0);
    expect(row.element.tagName).toBe('DIV');
    expect(row.attributes('href')).toBeUndefined();
    expect(findChevron(row).exists()).toBe(false);
  });

  it('links "View all audit logs" to the audit events tab', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().attributes('href')).toBe('?tab=agent-artifacts');
  });

  it('shows the empty state when there are no sessions', async () => {
    createComponent();
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
  });

  it('shows an error alert when the query fails', async () => {
    createComponent({ groupHandler: jest.fn().mockRejectedValue(new Error('failed')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
  });

  // 19.4 ships this card with no agent-class filter. `INTERNAL_DAP` resolves
  // to `agent_type IS NULL`, which is narrower than sending nothing, so the
  // flag-off path must send no `agentClass` key at all.
  describe('with the connected agents filter flag off', () => {
    it('sends no agentClass for a group, matching the 19.4 query', async () => {
      const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
      createComponent({ connectedAgentsFilter: false, groupHandler });
      await waitForPromises();

      expect(groupHandler).toHaveBeenCalledWith({ groupFullPath: 'gitlab-duo', first: 5 });
    });

    it('sends no agentClass for a project, matching the 19.4 query', async () => {
      const projectHandler = jest.fn().mockResolvedValue(projectResponse([]));
      createComponent({
        connectedAgentsFilter: false,
        provide: { projectFullPath: 'gitlab-duo/test' },
        projectHandler,
      });
      await waitForPromises();

      expect(projectHandler).toHaveBeenCalledWith({
        projectFullPath: 'gitlab-duo/test',
        first: 5,
      });
    });

    it('ignores the agentClass prop it is given', async () => {
      const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
      createComponent({
        connectedAgentsFilter: false,
        props: { agentClass: 'INTERNAL_DAP' },
        groupHandler,
      });
      await waitForPromises();

      expect(groupHandler).toHaveBeenCalledWith({ groupFullPath: 'gitlab-duo', first: 5 });
    });
  });

  it('defaults to the ALL agent class', async () => {
    const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ groupHandler });
    await waitForPromises();

    expect(groupHandler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'ALL' }));
  });

  it('segments the sessions by the agent class it is given', async () => {
    const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ props: { agentClass: 'EXTERNAL' }, groupHandler });
    await waitForPromises();

    expect(groupHandler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'EXTERNAL' }));
  });

  it('re-runs the query when the agent class changes', async () => {
    const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ groupHandler });
    await waitForPromises();

    await wrapper.setProps({ agentClass: 'INTERNAL_DAP' });
    await waitForPromises();

    expect(groupHandler).toHaveBeenLastCalledWith(
      expect.objectContaining({ agentClass: 'INTERNAL_DAP' }),
    );
  });

  it('uses the project-level query in project mode', async () => {
    const projectHandler = jest.fn().mockResolvedValue(projectResponse([sessionNode(1)]));
    createComponent({ provide: { projectFullPath: 'gitlab-duo/test' }, projectHandler });
    await waitForPromises();

    expect(projectHandler).toHaveBeenCalledWith(
      expect.objectContaining({ projectFullPath: 'gitlab-duo/test', first: 5, agentClass: 'ALL' }),
    );
    expect(findRows()).toHaveLength(1);
  });

  it('states that it is not scoped to the selected date range', async () => {
    createComponent();
    await waitForPromises();

    expect(wrapper.findByTestId('card-footnote').text()).toBe(
      'Shows the most recent sessions, not filtered by date range.',
    );
  });
});
