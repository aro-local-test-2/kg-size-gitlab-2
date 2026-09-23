import { setNewWorkItemCache } from '~/work_items/graphql/cache_utils';
import { CREATION_CONTEXT_LIST_ROUTE, WIDGET_TYPE_STATUS } from '~/work_items/constants';
import { findStatusWidget } from '~/work_items/utils';
import workItemByIidQuery from '~/work_items/graphql/work_item_by_iid.query.graphql';
import waitForPromises from 'helpers/wait_for_promises';
import { createIssuableCache, expectCacheHit } from 'helpers/apollo_cache_helper';
import { setCurrentUser } from 'helpers/current_user_helper';
import { namespaceWorkItemTypesQueryResponse } from 'jest/work_items/mock_data';

describe('work items graphql cache utils', () => {
  const originalFeatures = window.gon.features;
  const fullPath = 'gitlab-org/gitlab';

  const taskWidgetDefinitions =
    namespaceWorkItemTypesQueryResponse.data?.namespace?.workItemTypes?.nodes
      ?.find((type) => type.name === 'Task')
      ?.widgetDefinitions.filter((definition) => definition.type !== WIDGET_TYPE_STATUS) || [];

  const statusDefinition = namespaceWorkItemTypesQueryResponse.data?.namespace?.workItemTypes?.nodes
    ?.find((type) => type.name === 'Task')
    ?.widgetDefinitions.find((definition) => definition.type === WIDGET_TYPE_STATUS);

  let cache;

  beforeEach(() => {
    window.gon.features = {};
    setCurrentUser();
    cache = createIssuableCache();
  });

  afterAll(() => {
    window.gon.features = originalFeatures;
  });

  describe.each`
    path          | useWorkItemFeatures
    ${'widgets'}  | ${false}
    ${'features'} | ${true}
  `('setNewWorkItemCache on the $path path', ({ useWorkItemFeatures }) => {
    const variables = {
      fullPath: 'gitlab-org/gitlab-task-id',
      iid: 'new-work-item-iid',
      useWorkItemFeatures,
    };

    const readWorkItem = () =>
      cache.readQuery({ query: workItemByIidQuery, variables })?.namespace?.workItem;

    beforeEach(async () => {
      await setNewWorkItemCache({
        fullPath,
        context: CREATION_CONTEXT_LIST_ROUTE,
        widgetDefinitions: [...taskWidgetDefinitions, statusDefinition],
        workItemType: 'Task',
        workItemTypeId: 'gid://gitlab/WorkItems::Type/5',
        workItemTypeIconName: 'work-item-task',
        useWorkItemFeatures,
        cache,
      });

      await waitForPromises();
    });

    it('seeds the status widget with the default open status', () => {
      expect(findStatusWidget(readWorkItem()).status).toEqual(statusDefinition.defaultOpenStatus);
    });

    // The EE `WorkItemFeatures` fragment selects fields — `agentPlan.type` was the one that
    // shipped broken — whose widget definition is absent for types that do not support them.
    // Anything the seed misses makes this read incomplete and names the field.
    // Regression guard for https://gitlab.com/gitlab-org/gitlab/-/work_items/598491
    it('seeds a work item the detail query can read in full', () => {
      expectCacheHit(cache, { query: workItemByIidQuery, variables });
    });
  });
});
