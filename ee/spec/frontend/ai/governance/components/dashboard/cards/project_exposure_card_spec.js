import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import ProjectExposureCard from 'ee/ai/governance/components/dashboard/cards/project_exposure_card.vue';
import getProjectExposureQuery from 'ee/ai/governance/graphql/queries/get_project_exposure.query.graphql';

Vue.use(VueApollo);

const projectNode = (id, sessionCount) => ({
  __typename: 'AiGovernanceProjectActivity',
  sessionCount,
  project: {
    __typename: 'Project',
    id: `gid://gitlab/Project/${id}`,
    name: `project-${id}`,
    fullPath: `acme/project-${id}`,
    nameWithNamespace: `Acme / project-${id}`,
    webUrl: `/acme/project-${id}`,
  },
});

const groupResponse = (nodes) => ({
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      aiGovernanceMetrics: {
        __typename: 'AiGovernanceMetrics',
        topProjects: nodes,
      },
    },
  },
});

const projectResponse = (nodes) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      aiGovernanceMetrics: {
        __typename: 'AiGovernanceMetrics',
        topProjects: nodes,
      },
    },
  },
});

describe('ProjectExposureCard', () => {
  let wrapper;

  const createComponent = ({ provide = {}, props = {}, handler } = {}) => {
    const apolloProvider = createMockApollo([
      [getProjectExposureQuery, handler ?? jest.fn().mockResolvedValue(groupResponse([]))],
    ]);

    wrapper = mountExtended(ProjectExposureCard, {
      apolloProvider,
      propsData: props,
      provide: { groupFullPath: 'gitlab-duo', projectFullPath: null, ...provide },
    });
  };

  const findRows = () => wrapper.findAllByTestId('project-exposure-row');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  it('renders a row per ranked project', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(groupResponse([projectNode(201, 118), projectNode(202, 87)])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(2);
  });

  it('skips ranked entries whose project cannot be resolved', async () => {
    const unresolved = {
      __typename: 'AiGovernanceProjectActivity',
      sessionCount: 9,
      project: null,
    };
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([projectNode(201, 118), unresolved])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(1);
    expect(findRows().at(0).text()).toContain('project-201');
  });

  it('maps the session count to the "N sessions" label', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([projectNode(201, 118)])),
    });
    await waitForPromises();

    const top = findRows().at(0);
    expect(top.text()).toContain('project-201');
    expect(top.text()).toContain('118 sessions');
  });

  it('links each row to the audit report filtered by that project full path', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([projectNode(201, 118)])),
    });
    await waitForPromises();

    const href = findRows().at(0).attributes('href');
    expect(href).toContain('tab=agent-artifacts');
    expect(href).toContain(`projectPath=${encodeURIComponent('acme/project-201')}`);
  });

  it('shows a loading state while the query is in flight', () => {
    createComponent({ handler: jest.fn().mockReturnValue(new Promise(() => {})) });

    expect(findViewAllLink().exists()).toBe(true);
    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(false);
  });

  it('shows the empty state when there are no projects', async () => {
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

  it('links "View all projects" to the audit events tab', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().attributes('href')).toBe('?tab=agent-artifacts');
  });

  it('defaults to the ALL agent class', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'ALL' }));
  });

  it('segments the ranking by the agent class it is given', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ props: { agentClass: 'EXTERNAL' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'EXTERNAL' }));
  });

  it('re-runs the query when the agent class changes', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    await wrapper.setProps({ agentClass: 'INTERNAL_DAP' });
    await waitForPromises();

    expect(handler).toHaveBeenLastCalledWith(
      expect.objectContaining({ agentClass: 'INTERNAL_DAP' }),
    );
  });

  it('defaults to the LAST_7_DAYS timeframe', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ timeframe: 'LAST_7_DAYS' }));
  });

  it('scopes the ranking to the timeframe it is given', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ props: { timeframe: 'LAST_30_DAYS' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ timeframe: 'LAST_30_DAYS' }));
  });

  it('re-runs the query when the timeframe changes', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    await wrapper.setProps({ timeframe: 'LAST_30_DAYS' });
    await waitForPromises();

    expect(handler).toHaveBeenLastCalledWith(
      expect.objectContaining({ timeframe: 'LAST_30_DAYS' }),
    );
  });

  it('uses the project-level query in project mode', async () => {
    const handler = jest.fn().mockResolvedValue(projectResponse([projectNode(201, 5)]));
    createComponent({ provide: { projectFullPath: 'gitlab-duo/test' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({ projectFullPath: 'gitlab-duo/test', isProject: true }),
    );
    expect(findRows()).toHaveLength(1);
  });
});
