import { TEST_HOST } from 'helpers/test_constants';

const HOUR_IN_MS = 60 * 60 * 1000;
const DAY_IN_MS = 24 * HOUR_IN_MS;

export const mockFullPath = 'group/project';
export const mockWorkItemId = 'gid://gitlab/WorkItem/7';
export const mockWorkItemIid = '7';

const buildUser = (id, name, avatarUrl = null) => ({
  __typename: 'UserCore',
  id: `gid://gitlab/User/${id}`,
  name,
  username: name.toLowerCase().replace(/\s/g, '.'),
  avatarUrl,
  webUrl: `/${name}`,
  webPath: `/${name}`,
});

const mockDuo = buildUser(1, 'GitLab Duo');
const mockDecider = buildUser(2, 'Avery Patel', '/avery.png');
export const mockThreadAuthor = buildUser(3, 'Parker Osinski', '/parker.png');

const buildOptions = (nodes) => ({
  __typename: 'WorkItemDecisionOptionConnection',
  nodes: nodes.map(({ id, content, selected = false }) => ({
    __typename: 'WorkItemDecisionOption',
    id: `gid://gitlab/WorkItems::DecisionOption/${id}`,
    content,
    selected,
  })),
});

/**
 * Builds one decision in the shape the decision log query fetches.
 *
 * The defaults describe a decision GitLab Duo raised and Avery settled. Neither `sourceLink` nor
 * `discussionId` is set, so the card reads the default as Duo's work.
 *
 * @param {Object} attributes The fields that set this decision apart, plus a numeric `id`.
 * @returns {Object} A decision record.
 */
const buildDecision = ({ id, ...attributes }) => ({
  __typename: 'WorkItemDecision',
  id: `gid://gitlab/WorkItems::Decision/${id}`,
  title: null,
  description: null,
  resolutionRationale: null,
  resolvedAt: new Date(Date.now() - HOUR_IN_MS).toISOString(),
  // A resolving note always lives on this GitLab, so the card treats it as an internal link.
  noteUrl: `${TEST_HOST}/acme/web/-/work_items/7#note_${1000000 + id}`,
  discussionId: null,
  sourceLink: null,
  state: 'RESOLVED',
  author: mockDuo,
  resolvedBy: mockDecider,
  options: buildOptions([]),
  ...attributes,
});

export const mockDecision = buildDecision({
  id: 1,
  title:
    'The updated description mentions SCIM auto-provisioning — should we scope that into this MVP, or handle it as a follow-up?',
  description:
    'GitLab Duo noticed the description was updated to reference SCIM auto-provisioning. Before creating the workplan, it needed a stance on whether SCIM belongs in this MVP or a follow-up work item.',
  resolutionRationale:
    'Provisioning and authentication ship together, so splitting them would leave the MVP with accounts that nothing creates.',
  resolvedAt: new Date(Date.now() - 2 * HOUR_IN_MS).toISOString(),
  options: buildOptions([
    { id: 1, content: 'Handle SCIM as a follow-up' },
    { id: 2, content: 'Include SCIM alongside SAML in this MVP', selected: true },
  ]),
});

const mockDecisionWithoutRationale = buildDecision({
  id: 2,
  title: 'Is there emergency access if the IdP is unreachable and SSO is enforced?',
  description:
    'GitLab Duo offered this as a suggested answer on the spec. Open question on how admins stay reachable if the IdP is down and SSO is the only sanctioned login path.',
  resolvedAt: new Date(Date.now() - DAY_IN_MS).toISOString(),
  options: buildOptions([
    {
      id: 3,
      content: 'No backup — full lockout, contact support to restore access',
      selected: true,
    },
    { id: 4, content: 'Admins keep a backup email and password login' },
  ]),
});

const mockDecisionFromThread = buildDecision({
  id: 3,
  description:
    'Several IdPs in the field ship non-conformant assertions. The team needed a stance before the validation layer was written.',
  resolutionRationale:
    'Accepting deviations once would make every later assertion a special case, and the team has no capacity to maintain per-vendor branches.',
  resolvedAt: new Date(Date.now() - 3 * DAY_IN_MS).toISOString(),
  discussionId: `gid://gitlab/Discussion/${'a'.repeat(40)}`,
  author: mockThreadAuthor,
  resolvedBy: mockThreadAuthor,
  options: buildOptions([
    {
      id: 5,
      content: 'Strict spec compliance only — reject any non-conformant assertions',
      selected: true,
    },
  ]),
});

export const mockDecisions = [mockDecision, mockDecisionWithoutRationale, mockDecisionFromThread];

export const buildMockDecision = (overrides = {}) => ({ ...mockDecision, ...overrides });

export const buildMockOptions = (nodes) => ({ nodes });

export const decisionLogResponse = (nodes = mockDecisions) => ({
  data: {
    namespace: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      workItem: {
        __typename: 'WorkItem',
        id: mockWorkItemId,
        features: {
          __typename: 'WorkItemFeatures',
          decisionLog: {
            __typename: 'WorkItemWidgetDecisionLog',
            decisions: { __typename: 'WorkItemDecisionConnection', nodes },
          },
        },
      },
    },
  },
});
