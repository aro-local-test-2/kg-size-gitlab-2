import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  clearFilters,
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { WORK_ITEMS } from './filter_test_constants';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn().mockReturnValue(true),
}));

const CRM_ID = '1';
const SECOND_CRM_ID = '2';
const ORGANIZATION_ITEMS = [WORK_ITEMS.SECOND, WORK_ITEMS.BLOCKING];
const ALL_ITEMS = [
  WORK_ITEMS.AGENT_PLAN,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.CHILD_TASK,
  WORK_ITEMS.SECOND,
  WORK_ITEMS.DEPENDENT,
];

describe('Work items list - CRM filters', () => {
  useFilterSpec();

  it('filters to work items linked to the organization', async () => {
    useListFixture('WITH_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${CRM_ID}`);

    await expectListToShow(ORGANIZATION_ITEMS);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org/gitlab',
      crmOrganizationId: '1',
    });
  });

  it('filters to work items linked to the second organization', async () => {
    useListFixture('WITH_SECOND_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${SECOND_CRM_ID}`);

    await expectListToShow([WORK_ITEMS.LINKABLE]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org/gitlab',
      crmOrganizationId: '2',
    });
  });

  it('filters to work items linked to the contact', async () => {
    useListFixture('WITH_CRM_CONTACT');
    mountListWithQuery(`?crm_contact_id=${CRM_ID}`);

    await expectListToShow([WORK_ITEMS.SECOND]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org/gitlab',
      crmContactId: '1',
    });
  });

  it('filters to work items linked to the second contact', async () => {
    useListFixture('WITH_SECOND_CRM_CONTACT');
    mountListWithQuery(`?crm_contact_id=${SECOND_CRM_ID}`);

    await expectListToShow([WORK_ITEMS.BLOCKING]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org/gitlab',
      crmContactId: '2',
    });
  });

  it('filters to work items linked to the organization on the group list', async () => {
    useListFixture('GROUP_WITH_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${CRM_ID}`, { isGroup: true });

    await expectListToShow(ORGANIZATION_ITEMS);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org',
      crmOrganizationId: '1',
    });
  });

  it('clears the filter and shows every work item again', async () => {
    useListFixture('WITH_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${CRM_ID}`);
    await expectListToShow(ORGANIZATION_ITEMS);

    useListFixture('BASE');
    clearFilters();

    await expectListToShow(ALL_ITEMS);

    expect(lastRequestVariables('getWorkItemsSlimEE')).not.toHaveProperty('crmOrganizationId');
  });

  it('filters to work items linked to the contact on the group list', async () => {
    useListFixture('GROUP_WITH_CRM_CONTACT');
    mountListWithQuery(`?crm_contact_id=${CRM_ID}`, { isGroup: true });

    await expectListToShow([WORK_ITEMS.SECOND]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org',
      crmContactId: '1',
    });
  });
});
