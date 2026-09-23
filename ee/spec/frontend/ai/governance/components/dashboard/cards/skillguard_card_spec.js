import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlBadge } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import SkillguardCard from 'ee/ai/governance/components/dashboard/cards/skillguard_card.vue';
import getSkillguardSummaryQuery from 'ee/ai/governance/graphql/queries/get_skillguard_summary.query.graphql';

Vue.use(VueApollo);

const NO_COUNTS = {
  __typename: 'VulnerabilitySeveritiesCount',
  critical: 0,
  high: 0,
  medium: 0,
  low: 0,
  unknown: 0,
  info: 0,
};

const skillNode = (id, severity, name = `skill-${id}`) => ({
  __typename: 'Vulnerability',
  id: `gid://gitlab/Vulnerability/${id}`,
  title: name,
  severity,
  vulnerabilityPath: `/acme/data-pipeline/-/security/vulnerabilities/${id}`,
  project: {
    __typename: 'Project',
    id: `gid://gitlab/Project/${id}`,
    name: 'data-pipeline',
  },
});

const namespacePayload = (nodes, counts) => ({
  vulnerabilitySeveritiesCount: { ...NO_COUNTS, ...counts },
  vulnerabilities: { __typename: 'VulnerabilityConnection', nodes },
});

const groupResponse = (nodes = [], counts = {}) => ({
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      ...namespacePayload(nodes, counts),
    },
  },
});

const projectResponse = (nodes = [], counts = {}) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      ...namespacePayload(nodes, counts),
    },
  },
});

describe('SkillguardCard', () => {
  let wrapper;

  const createComponent = ({ provide = {}, handler } = {}) => {
    const apolloProvider = createMockApollo([
      [getSkillguardSummaryQuery, handler ?? jest.fn().mockResolvedValue(groupResponse())],
    ]);

    wrapper = mountExtended(SkillguardCard, {
      apolloProvider,
      provide: {
        groupFullPath: 'gitlab-duo',
        projectId: null,
        projectFullPath: '',
        ...provide,
      },
    });
  };

  const findRows = () => wrapper.findAllByTestId('skillguard-row');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');
  const findSeverityCounts = () => wrapper.findByTestId('severity-counts');
  const findTotalFlagged = () => wrapper.findByTestId('total-flagged');

  it('filters both the counts and the list by the SkillGuard scanner', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse());
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ scanner: ['skillguard'] }));
  });

  it('renders a row per flagged skill', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(groupResponse([skillNode(1, 'CRITICAL'), skillNode(2, 'HIGH')])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(2);
  });

  it('shows the skill name and its project on each row', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([skillNode(1, 'CRITICAL', '0x-swap')])),
    });
    await waitForPromises();

    const row = findRows().at(0);
    expect(row.text()).toContain('0x-swap');
    expect(row.text()).toContain('data-pipeline');
  });

  it('links each row to that vulnerability', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([skillNode(7, 'CRITICAL')])),
    });
    await waitForPromises();

    expect(findRows().at(0).attributes('href')).toBe(
      '/acme/data-pipeline/-/security/vulnerabilities/7',
    );
  });

  it('summarises the severity counts and the flagged total', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(groupResponse([skillNode(1, 'CRITICAL')], { critical: 4, high: 17 })),
    });
    await waitForPromises();

    expect(findSeverityCounts().text()).toBe('4 malicious · 17 suspicious');
    expect(findTotalFlagged().text()).toBe('21 flagged skills');
  });

  it('omits severities with no findings from the summary', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(groupResponse([skillNode(1, 'CRITICAL')], { critical: 2 })),
    });
    await waitForPromises();

    expect(findSeverityCounts().text()).toBe('2 malicious');
    expect(wrapper.findByTestId('risk-bar-critical').exists()).toBe(true);
    expect(wrapper.findByTestId('risk-bar-high').exists()).toBe(false);
  });

  it('sizes each risk bar segment by its share of the flagged total', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(groupResponse([skillNode(1, 'CRITICAL')], { critical: 1, high: 3 })),
    });
    await waitForPromises();

    expect(wrapper.findByTestId('risk-bar-critical').attributes('style')).toContain('width: 25%');
    expect(wrapper.findByTestId('risk-bar-high').attributes('style')).toContain('width: 75%');
  });

  it('labels the card with the SkillGuard scanner badge', async () => {
    createComponent();
    await waitForPromises();

    expect(wrapper.findComponent(GlBadge).text()).toBe('SkillGuard');
  });

  // The group report has no scanner token, so it is filtered by identifier name.
  it('deep-links "View all skills" to the group report filtered by the SkillGuard identifier', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().attributes('href')).toBe(
      '/groups/gitlab-duo/-/security/vulnerabilities?identifier=SkillGuard+Skill+Analysis',
    );
  });

  // Project scope has the scanner token, so it filters on the canonical scanner ID.
  it('deep-links to the project vulnerability report filtered by scanner', async () => {
    createComponent({
      provide: { projectId: '1', projectFullPath: 'gitlab-duo/test' },
      handler: jest.fn().mockResolvedValue(projectResponse()),
    });
    await waitForPromises();

    expect(findViewAllLink().attributes('href')).toBe(
      '/gitlab-duo/test/-/security/vulnerability_report?scanner=skillguard',
    );
  });

  it('uses the project-level query in project mode', async () => {
    const handler = jest.fn().mockResolvedValue(projectResponse([skillNode(1, 'CRITICAL')]));
    createComponent({
      provide: { projectId: '1', projectFullPath: 'gitlab-duo/test' },
      handler,
    });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({ projectFullPath: 'gitlab-duo/test', isProject: true }),
    );
    expect(findRows()).toHaveLength(1);
  });

  it('shows a loading state while the query is in flight', () => {
    createComponent({ handler: jest.fn().mockReturnValue(new Promise(() => {})) });

    expect(findViewAllLink().exists()).toBe(true);
    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(false);
  });

  it('shows the empty state when no skill has been flagged', async () => {
    createComponent();
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
  });

  // severity is nullable on VulnerabilityType, and an undefined severity would
  // render a severity-undefined icon name and CSS class.
  it('falls back to the unknown severity icon when a finding has no severity', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([skillNode(1, null)])),
    });
    await waitForPromises();

    expect(wrapper.findComponentByTestId('skill-severity-icon').props('name')).toBe(
      'severity-unknown',
    );
  });

  // The icon is presentational, so severity would otherwise be invisible to a
  // screen reader. The label reuses the verdict wording the summary line shows.
  it('exposes the severity to assistive technology via an aria-label', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([skillNode(1, 'CRITICAL')])),
    });
    await waitForPromises();

    expect(wrapper.findComponentByTestId('skill-severity-icon').attributes('aria-label')).toBe(
      'malicious',
    );
  });

  it('shows an error alert when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('failed')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
  });

  // Severities outside the agreed critical/high mapping keep their own name
  // rather than being labelled with a verdict we cannot infer.
  it('falls back to the severity name for severities with no agreed verdict', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(groupResponse([skillNode(1, 'MEDIUM')], { medium: 3, low: 1 })),
    });
    await waitForPromises();

    expect(findSeverityCounts().text()).toBe('3 medium · 1 low');
  });
});
