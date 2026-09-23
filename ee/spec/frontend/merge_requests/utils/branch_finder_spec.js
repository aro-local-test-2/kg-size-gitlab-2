import MockAdapter from 'axios-mock-adapter';
import axios from '~/lib/utils/axios_utils';
import { findTargetBranch } from 'ee/merge_requests/utils/branch_finder';
import { HTTP_STATUS_NOT_FOUND, HTTP_STATUS_OK } from '~/lib/utils/http_status';

describe('findTargetBranch', () => {
  let mock;

  beforeEach(() => {
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
  });

  it('returns the target branch for the project', async () => {
    const { token } = axios.CancelToken.source();
    mock
      .onGet('/gitlab-org/gitlab/-/target_branch_rules', { params: { branch_name: 'feature' } })
      .reply(HTTP_STATUS_OK, { target_branch: 'main' });

    expect(await findTargetBranch('gitlab-org/gitlab', 'feature', token)).toBe('main');
    expect(mock.history.get[0].cancelToken).toBe(token);
  });

  it('returns null when the request fails', async () => {
    mock.onGet('/gitlab-org/gitlab/-/target_branch_rules').reply(HTTP_STATUS_NOT_FOUND);

    expect(await findTargetBranch('gitlab-org/gitlab', 'feature')).toBe(null);
  });
});
