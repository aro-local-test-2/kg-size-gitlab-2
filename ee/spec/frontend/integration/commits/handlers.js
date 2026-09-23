import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { loadFixturesMap, matchFixture } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import commitListVariants from './fixture_variants/get_commit_list';
import './fixture_variants/get_branch_merge_request';
import './fixture_variants/get_commit_list_branch_names';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/commits/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

export const commitListResponse = fixtures.getCommitList;
export const nextPageCommitListResponse = fixtures.getCommitListNextPage;
export const allCommitsResponse = fixtures.getCommitListAll;
export const searchedCommitListResponse = fixtures.getCommitListSearch;
export const commitDetailsResponse = fixtures.getCommitDetails;
export const branchMergeRequestResponse = fixtures.getBranchMergeRequest;
export const branchNamesResponse = fixtures.getCommitListBranchNames;

// The message search the searched fixture was recorded with.
export const SEARCH_TERM = 'submodule';
export const UNMATCHED_SEARCH_TERM = 'bogus12345';
// Recorded with every commit on the branch in one page (hasNextPage: false).
export const ALL_COMMITS_PAGE_SIZE = 50;

const PAGE_ONE_END_CURSOR = commitListResponse.data.project.repository.commits.pageInfo.endCursor;

const commitListFixtureTable = [
  {
    // Restricted to unfiltered requests so a request with a filter this table
    // doesn't know about fails loudly instead of being served the base page.
    matches: ({ query, after, first, author, committedAfter, committedBefore }) =>
      !query &&
      !after &&
      !author &&
      !committedAfter &&
      !committedBefore &&
      first !== ALL_COMMITS_PAGE_SIZE,
    fixture: () => commitListResponse,
  },
  {
    matches: ({ query, after }) => !query && after === PAGE_ONE_END_CURSOR,
    fixture: () => nextPageCommitListResponse,
  },
  {
    matches: ({ query, after, first }) => !query && !after && first === ALL_COMMITS_PAGE_SIZE,
    fixture: () => allCommitsResponse,
  },
  {
    matches: ({ query, after }) => query === SEARCH_TERM && !after,
    fixture: () => searchedCommitListResponse,
  },
  {
    matches: ({ query, after }) => query === UNMATCHED_SEARCH_TERM && !after,
    fixture: () => commitListVariants.EMPTY,
  },
];

const OPERATION_HANDLERS = {
  getCommitList: ({ variables }) =>
    getActiveVariant('getCommitList') ??
    matchFixture(variables, commitListFixtureTable, {
      guard: () => true,
      label: 'getCommitList',
    }).fixture(),
  getCommitDetails: () => commitDetailsResponse,
  // Fired by OpenMrBadge when the list is scoped to a path.
  getOpenMrCountForBlobPath: () => fixtures.getOpenMrCountForBlobPath,
  getBranchMergeRequest: () =>
    getActiveVariant('getBranchMergeRequest') ?? branchMergeRequestResponse,
  getCommitListBranchNames: () =>
    getActiveVariant('getCommitListBranchNames') ?? branchNamesResponse,
};

export function handleCommitListOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

// The ref selector searches branches and tags as soon as the page mounts.
export const commitListRestEndpoints = [
  {
    method: 'get',
    path: /\/projects\/[^/]+\/repository\/branches/,
    name: 'refSelectorBranches',
    response: [
      { name: 'master', default: true },
      { name: 'feature', default: false },
      { name: 'improve/awesome', default: false },
    ],
    headers: { 'x-total': '3' },
  },
  {
    method: 'get',
    path: /\/projects\/[^/]+\/repository\/tags/,
    name: 'refSelectorTags',
    response: [{ name: 'v1.0.0' }],
    headers: { 'x-total': '1' },
  },
];
