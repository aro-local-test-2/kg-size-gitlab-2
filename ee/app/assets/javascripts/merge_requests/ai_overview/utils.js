import {
  CHECKING_REASONS,
  FAILURE_REASONS,
} from '~/vue_merge_request_widget/components/checks/constants';
import { n__, s__, sprintf } from '~/locale';
import { joinPaths } from '~/lib/utils/url_utility';
import {
  CHECK_APPROVALS,
  CHECK_CONFLICTS,
  CHECK_DISCUSSIONS,
  CHECK_LABELS,
  CHECK_PIPELINE,
  CHECK_STATUS,
  DEFAULT_CHECK_STATUS,
  VERDICTS,
} from './constants';

// The checks that always get a row, in the order they render.
const ROW_CHECKS = [CHECK_APPROVALS, CHECK_DISCUSSIONS, CHECK_PIPELINE, CHECK_CONFLICTS];

const unresolvedCount = (mr) =>
  (mr.resolvableDiscussionsCount || 0) - (mr.resolvedDiscussionsCount || 0);

const approvalsDetail = (mr) => {
  const required = mr.approvalsRequired || 0;

  if (!required) return s__('AiOverview|Not required');

  return sprintf(s__('AiOverview|%{given} of %{required} required'), {
    given: required - (mr.approvalsLeft || 0),
    required,
  });
};

const discussionsDetail = (mr) => {
  const unresolved = unresolvedCount(mr);

  return unresolved
    ? sprintf(
        n__(
          'AiOverview|%{count} unresolved thread',
          'AiOverview|%{count} unresolved threads',
          unresolved,
        ),
        { count: unresolved },
      )
    : s__('AiOverview|All resolved');
};

const defaultRows = (mr) => [
  { key: CHECK_APPROVALS, detail: approvalsDetail(mr) },
  {
    key: CHECK_DISCUSSIONS,
    detail: discussionsDetail(mr),
    action: unresolvedCount(mr) ? s__('AiOverview|View discussions') : null,
    href: joinPaths(mr.webPath, 'diffs'),
  },
  {
    key: CHECK_PIPELINE,
    detail: mr.headPipeline?.detailedStatus?.text || s__('AiOverview|No pipeline'),
    action: mr.headPipeline ? s__('AiOverview|View pipeline') : null,
    href: mr.headPipeline?.path,
  },
  {
    key: CHECK_CONFLICTS,
    detail: mr.conflicts ? s__('AiOverview|Must be resolved') : s__('AiOverview|None'),
  },
];

// The identifier arrives as a GraphQL enum name, and both label maps are keyed by its value.
const normalizedChecks = (mr) =>
  mr.mergeabilityChecks.map(({ identifier, status }) => ({
    key: identifier.toLowerCase(),
    status: CHECK_STATUS[status] ? status : DEFAULT_CHECK_STATUS,
  }));

// Row state comes from the mergeability checks rather than the raw fields, so a check the project
// has turned off does not read as a blocker.
export const buildRows = (mergeRequest) => {
  const checks = normalizedChecks(mergeRequest);
  const statusOf = (key) => checks.find((c) => c.key === key)?.status || DEFAULT_CHECK_STATUS;

  const rows = [
    ...defaultRows(mergeRequest).map((row) => ({ ...row, status: statusOf(row.key) })),
    // Every other merge check earns a row only while it is holding the merge request up.
    ...checks.filter(
      ({ key, status }) => !ROW_CHECKS.includes(key) && CHECK_STATUS[status].extraRow,
    ),
  ];

  return rows.map((row) => ({
    ...row,
    label: CHECK_LABELS[row.key] || s__('AiOverview|Merge check'),
    // A check that has not finished has nothing to report yet, so the raw fields would contradict
    // the row ("Merge conflicts: None" beside a spinner).
    detail:
      (row.status === 'CHECKING' && CHECKING_REASONS[row.key]) ||
      row.detail ||
      FAILURE_REASONS[row.key],
    ...CHECK_STATUS[row.status],
  }));
};

export const getVerdict = (rows) =>
  VERDICTS.find(({ checkStatus }) => !checkStatus || rows.some((r) => r.status === checkStatus));
