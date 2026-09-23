export const check = (identifier, status) => ({
  __typename: 'MergeRequestMergeabilityCheck',
  identifier,
  status,
});

export const failingChecks = [
  check('NOT_APPROVED', 'FAILED'),
  check('DISCUSSIONS_NOT_RESOLVED', 'FAILED'),
  check('CI_MUST_PASS', 'CHECKING'),
  check('CONFLICT', 'SUCCESS'),
  check('DRAFT_STATUS', 'SUCCESS'),
];

export const passingChecks = failingChecks.map(({ identifier }) => check(identifier, 'SUCCESS'));

// Overriding one check means restating the list: `slice` used to leave a second entry for the
// same identifier, and the last one won, so the check under test never took effect.
export const checksWith = (...overrides) => {
  const byIdentifier = new Map(passingChecks.map((c) => [c.identifier, c]));

  overrides.forEach((c) => byIdentifier.set(c.identifier, c));

  return [...byIdentifier.values()];
};

export const pipeline = (text = 'Running') => ({
  __typename: 'Pipeline',
  id: 'gid://gitlab/Ci::Pipeline/9',
  path: '/group/proj/-/pipelines/9',
  detailedStatus: { __typename: 'DetailedStatus', id: 'status-9', text },
});

export const makeMergeRequest = (overrides = {}) => ({
  __typename: 'MergeRequest',
  id: 'gid://gitlab/MergeRequest/3',
  iid: '1',
  webPath: '/group/proj/-/merge_requests/1',
  state: 'opened',
  conflicts: false,
  approvalsRequired: 2,
  approvalsLeft: 1,
  resolvableDiscussionsCount: 4,
  resolvedDiscussionsCount: 1,
  mergeabilityChecks: failingChecks,
  headPipeline: pipeline(),
  ...overrides,
});

export const overviewResponse = (mergeRequest = makeMergeRequest()) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/7',
      mergeRequest,
    },
  },
});
