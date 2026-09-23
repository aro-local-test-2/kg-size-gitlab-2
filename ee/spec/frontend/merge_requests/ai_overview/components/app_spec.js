import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import { createMockSubscription } from 'mock-apollo-client';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import App from 'ee/merge_requests/ai_overview/components/app.vue';
import MergeReadiness from 'ee/merge_requests/ai_overview/components/merge_readiness.vue';
import overviewQuery from 'ee/merge_requests/ai_overview/queries/mr_ai_overview.query.graphql';
import mergeStatusSubscription from 'ee/merge_requests/ai_overview/queries/mr_ai_overview.subscription.graphql';
import { makeMergeRequest, overviewResponse, passingChecks } from '../mock_data';

Vue.use(VueApollo);

describe('AI Overview app', () => {
  let wrapper;
  let subscriptionHandler;
  let mergeStatusUpdates;
  let queryHandler;

  const createComponent = ({ handler } = {}) => {
    mergeStatusUpdates = createMockSubscription();
    subscriptionHandler = jest.fn(() => mergeStatusUpdates);
    queryHandler = handler ?? jest.fn().mockResolvedValue(overviewResponse());
    const apolloProvider = createMockApollo([[overviewQuery, queryHandler]]);
    apolloProvider.defaultClient.setRequestHandler(mergeStatusSubscription, subscriptionHandler);

    wrapper = shallowMountExtended(App, {
      apolloProvider,
      provide: { projectPath: 'group/proj', iid: '1' },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findBody = () => wrapper.find('.ai-overview-body');
  const findReadiness = () => wrapper.findComponent(MergeReadiness);

  it('renders a loading icon while the query is loading', () => {
    createComponent();

    expect(findLoadingIcon().exists()).toBe(true);
    expect(findBody().exists()).toBe(false);
  });

  it('renders an error alert when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('nope')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
    expect(findBody().exists()).toBe(false);
  });

  it('clears the error and refetches when retry is clicked', async () => {
    const handler = jest
      .fn()
      .mockRejectedValueOnce(new Error('nope'))
      .mockResolvedValue(overviewResponse());
    createComponent({ handler });
    await waitForPromises();

    findAlert().vm.$emit('primary-action');
    await waitForPromises();

    expect(handler).toHaveBeenCalledTimes(2);
    expect(findAlert().exists()).toBe(false);
    expect(findBody().exists()).toBe(true);
  });

  it('renders the overview once the merge request loads', async () => {
    createComponent();
    await waitForPromises();

    expect(findBody().exists()).toBe(true);
    expect(findLoadingIcon().exists()).toBe(false);
    expect(findAlert().exists()).toBe(false);
  });

  it('hands the merge request to the readiness panel', async () => {
    createComponent();
    await waitForPromises();

    expect(findReadiness().props('mergeRequest')).toMatchObject({ iid: '1', state: 'opened' });
  });

  // Nothing to show, and the fields the overview reads would be missing.
  it('renders nothing when the merge request cannot be read', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue({
        data: {
          project: { __typename: 'Project', id: 'gid://gitlab/Project/7', mergeRequest: null },
        },
      }),
    });
    await waitForPromises();

    expect(findBody().exists()).toBe(false);
    expect(findReadiness().exists()).toBe(false);
    expect(findLoadingIcon().exists()).toBe(false);
  });

  it('follows the merge status subscription for the loaded merge request', async () => {
    createComponent();
    await waitForPromises();

    expect(subscriptionHandler).toHaveBeenCalledWith({
      issuableId: 'gid://gitlab/MergeRequest/3',
    });
  });

  it('does not subscribe before the merge request is known', () => {
    createComponent();

    expect(subscriptionHandler).not.toHaveBeenCalled();
  });

  it('applies a merge status update without a refetch', async () => {
    createComponent();
    await waitForPromises();

    mergeStatusUpdates.next({
      data: {
        mergeRequestMergeStatusUpdated: makeMergeRequest({
          approvalsLeft: 0,
          resolvedDiscussionsCount: 4,
          mergeabilityChecks: passingChecks,
        }),
      },
    });
    await waitForPromises();

    expect(findReadiness().props('mergeRequest')).toMatchObject({
      approvalsLeft: 0,
      resolvedDiscussionsCount: 4,
    });
    expect(queryHandler).toHaveBeenCalledTimes(1);
  });
});
