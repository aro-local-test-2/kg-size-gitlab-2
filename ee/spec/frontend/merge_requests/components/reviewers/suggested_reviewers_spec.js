import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlButton } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import ReviewerAvatarLink from '~/sidebar/components/reviewers/reviewer_avatar_link.vue';
import SuggestedReviewers from 'ee/merge_requests/components/reviewers/suggested_reviewers.vue';
import suggestedReviewersQuery from 'ee/merge_requests/queries/suggested_reviewer.query.graphql';
import setReviewersMutation from '~/merge_requests/components/reviewers/queries/set_reviewers.mutation.graphql';

Vue.use(VueApollo);

const rule = (id, name, type = 'REGULAR') => ({
  id: `gid://gitlab/ApprovalRule/${id}`,
  name,
  type,
});

const suggestion = (id, username, approvalRule) => ({
  __typename: 'AiSuggestedReviewer',
  id: `gid://gitlab/MergeRequests::AiSuggestedReviewer/${id}`,
  user: {
    __typename: 'UserCore',
    id: `gid://gitlab/User/${id}`,
    username,
    name: username,
    avatarUrl: '/avatar.png',
    webUrl: `/${username}`,
    webPath: `/${username}`,
  },
  approvalRule: approvalRule && { __typename: 'ApprovalRule', ...approvalRule },
  reason: 'Owns the changed files.',
});

const mockData = (nodes) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      mergeRequest: {
        __typename: 'MergeRequest',
        id: 'gid://gitlab/MergeRequest/1',
        aiSuggestedReviewers: {
          __typename: 'AiSuggestedReviewerConnection',
          nodes,
        },
      },
    },
  },
});

describe('Suggested reviewers component', () => {
  let wrapper;
  let mutationHandler;

  const findGroups = () => wrapper.findAllByTestId('reviewer');
  const findAddButton = () => wrapper.findComponent(GlButton);
  const usernamesIn = (group) =>
    group.findAllComponents(ReviewerAvatarLink).wrappers.map((link) => link.props('user').username);

  const createComponent = (nodes, canUpdate = true) => {
    mutationHandler = jest.fn().mockResolvedValue({
      data: {
        mergeRequestSetReviewers: { __typename: 'MergeRequestSetReviewersPayload', errors: [] },
      },
    });

    wrapper = shallowMountExtended(SuggestedReviewers, {
      apolloProvider: createMockApollo([
        [suggestedReviewersQuery, jest.fn().mockResolvedValue(mockData(nodes))],
        [setReviewersMutation, mutationHandler],
      ]),
      provide: { projectPath: 'group/project', issuableIid: '1' },
      propsData: {
        canUpdate,
      },
    });

    return waitForPromises();
  };

  it('renders nothing when there are no suggestions', async () => {
    await createComponent([]);

    expect(wrapper.text()).toBe('');
  });

  it('groups suggestions by approval rule, rules first', async () => {
    await createComponent([
      suggestion(1, 'alice', rule(1, 'Backend')),
      suggestion(2, 'bob', null),
      suggestion(3, 'carol', rule(1, 'Backend')),
      suggestion(4, 'dave', rule(2, 'ignored', 'ANY_APPROVER')),
    ]);

    const headings = findGroups().wrappers.map((group) => group.find('span').text());

    expect(headings).toEqual(['Backend', 'Any eligible user', 'No approval rule']);
    expect(usernamesIn(findGroups().at(0))).toEqual(['alice', 'carol']);
  });

  it('hides add button if user does not have permission', async () => {
    await createComponent([suggestion(1, 'alice', null)], false);

    expect(findAddButton().exists()).toBe(false);
  });

  it('adds the suggested reviewer without replacing the existing ones', async () => {
    await createComponent([suggestion(1, 'alice', null)]);

    findAddButton().vm.$emit('click');
    await waitForPromises();

    expect(mutationHandler).toHaveBeenCalledWith({
      reviewerUsernames: ['alice'],
      projectPath: 'group/project',
      iid: '1',
      operationMode: 'APPEND',
    });
  });
});
