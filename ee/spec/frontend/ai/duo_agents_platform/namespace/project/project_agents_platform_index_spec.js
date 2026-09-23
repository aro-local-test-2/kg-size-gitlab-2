import { shallowMount } from '@vue/test-utils';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import ProjectAgentsPlatformIndex from 'ee/ai/duo_agents_platform/namespace/project/project_agents_platform_index.vue';
import getProjectAgentFlows from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flows.query.graphql';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DuoAgentsPlatformIndex from 'ee/ai/duo_agents_platform/pages/index/duo_agents_platform_index.vue';
import { createAlert } from '~/alert';
import { mockAgentFlowsResponse } from 'ee_jest/ai/mocks';
import {
  saveSessionsQueryVariables,
  getSessionsQueryVariables,
} from 'ee/ai/duo_agents_platform/utils/sessions_query_state';

Vue.use(VueApollo);
jest.mock('~/alert');
jest.mock('ee/ai/duo_agents_platform/utils/sessions_query_state');

describe('ProjectAgentsPlatformIndex', () => {
  let wrapper;
  const projectPath = 'some/project/path';

  const getAgentFlowsHandler = jest.fn();
  const handlers = [[getProjectAgentFlows, getAgentFlowsHandler]];

  const createWrapper = () => {
    wrapper = shallowMount(ProjectAgentsPlatformIndex, {
      apolloProvider: createMockApollo(handlers),
      provide: {
        projectPath,
      },
    });

    return waitForPromises();
  };

  const findIndexComponent = () => wrapper.findComponent(DuoAgentsPlatformIndex);

  beforeEach(() => {
    getAgentFlowsHandler.mockResolvedValue(mockAgentFlowsResponse);
    getSessionsQueryVariables.mockReturnValue(null);
  });

  it('passes correct props to DuoAgentsPlatformIndex', async () => {
    await createWrapper();

    expect(findIndexComponent().props()).toMatchObject({
      initialSort: 'UPDATED_DESC',
      hasInitialWorkflows: expect.any(Boolean),
      isLoadingWorkflows: expect.any(Boolean),
      workflows: expect.any(Array),
      workflowsPageInfo: expect.any(Object),
    });
  });

  describe('Apollo queries', () => {
    describe('workflows query', () => {
      describe('when loading', () => {
        it('passes isLoadingWorkflows as true', () => {
          // not awaiting simulates loading
          createWrapper();
          expect(findIndexComponent().props('isLoadingWorkflows')).toBe(true);
        });
      });

      describe('on successful fetch', () => {
        beforeEach(async () => {
          await createWrapper();
        });

        it('fetches workflows data', () => {
          expect(getAgentFlowsHandler).toHaveBeenCalledTimes(1);
          expect(getAgentFlowsHandler).toHaveBeenCalledWith({
            projectPath,
            after: null,
            before: null,
            first: 20,
            last: null,
            type: 'non_foundational_chat_agents',
            sort: 'UPDATED_DESC',
          });
        });

        it('passes workflows to DuoAgentsPlatformIndex component', () => {
          const expectedWorkflows =
            mockAgentFlowsResponse.data.project.duoWorkflowWorkflows.edges.map((w) => w.node);

          expect(findIndexComponent().props('workflows')).toEqual(expectedWorkflows);
        });

        it('passes workflowsPageInfo to DuoAgentsPlatformIndex component', () => {
          const expectedPageInfo =
            mockAgentFlowsResponse.data.project.duoWorkflowWorkflows.pageInfo;

          expect(findIndexComponent().props('workflowsPageInfo')).toEqual(expectedPageInfo);
        });
      });

      describe('when a user-selected flow-type filter is applied', () => {
        beforeEach(async () => {
          await createWrapper();
          findIndexComponent().vm.$emit('query-variables-updated', {
            sort: 'UPDATED_DESC',
            pagination: { before: null, after: null, first: 20, last: null },
            filters: { type: 'chat' },
            updatedAfter: null,
          });
          await waitForPromises();
        });

        it('overrides the default non_foundational_chat_agents type', () => {
          expect(getAgentFlowsHandler).toHaveBeenLastCalledWith(
            expect.objectContaining({ type: 'chat' }),
          );
        });
      });

      describe('when workflows query fails', () => {
        const errorMessage = 'Network error';

        beforeEach(async () => {
          getAgentFlowsHandler.mockRejectedValue(new Error(errorMessage));
          await createWrapper();
        });

        it('calls createAlert with the error message', () => {
          expect(createAlert).toHaveBeenCalledWith({
            message: errorMessage,
            captureError: true,
          });
        });

        it('passes empty array to DuoAgentsPlatformIndex component', () => {
          expect(findIndexComponent().props('workflows')).toEqual([]);
        });
      });

      describe('when workflows query fails without error message', () => {
        beforeEach(async () => {
          getAgentFlowsHandler.mockRejectedValue(new Error());
          await createWrapper();
        });

        it('calls createAlert with default error message', () => {
          expect(createAlert).toHaveBeenCalledWith({
            message: 'Failed to fetch workflows',
            captureError: true,
          });
        });
      });

      describe('when workflows query returns empty edges', () => {
        beforeEach(async () => {
          getAgentFlowsHandler.mockResolvedValue({
            data: {
              project: {
                id: 'gid://gitlab/Project/1',
                duoWorkflowWorkflows: {
                  pageInfo: {
                    startCursor: null,
                    endCursor: null,
                    hasNextPage: false,
                    hasPreviousPage: false,
                  },
                  edges: [],
                },
              },
            },
          });
          await createWrapper();
        });

        it('passes empty array to DuoAgentsPlatformIndex component', () => {
          expect(findIndexComponent().props('workflows')).toEqual([]);
        });

        it('passes correct page info to DuoAgentsPlatformIndex component', () => {
          const expectedPageInfo = {
            startCursor: null,
            endCursor: null,
            hasNextPage: false,
            hasPreviousPage: false,
          };
          expect(findIndexComponent().props('workflowsPageInfo')).toEqual(expectedPageInfo);
        });
      });
    });
  });

  describe('pagination state preservation', () => {
    describe('when a previous mount saved variables for this project', () => {
      beforeEach(async () => {
        getSessionsQueryVariables.mockReturnValue({
          sort: 'CREATED_ASC',
          pagination: { first: null, after: null, before: 'cursor123', last: 20 },
          filters: { statusGroup: 'ACTIVE' },
        });

        await createWrapper();
      });

      it('looks up the saved variables using the project path', () => {
        expect(getSessionsQueryVariables).toHaveBeenCalledWith('some/project/path');
      });

      it('queries using the saved sort, pagination and filters', () => {
        expect(getAgentFlowsHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            sort: 'CREATED_ASC',
            first: null,
            after: null,
            before: 'cursor123',
            last: 20,
            statusGroup: 'ACTIVE',
          }),
        );
      });

      it('passes the saved filters down so the search bar shows them', () => {
        expect(findIndexComponent().props('initialFilters')).toEqual({ statusGroup: 'ACTIVE' });
      });
    });

    describe('when nothing was saved for this project', () => {
      beforeEach(async () => {
        await createWrapper();
      });

      it('queries using the default sort and first page', () => {
        expect(getAgentFlowsHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            sort: 'UPDATED_DESC',
            first: 20,
            after: null,
            before: null,
            last: null,
          }),
        );
      });
    });

    describe('when query variables are updated', () => {
      beforeEach(async () => {
        await createWrapper();

        findIndexComponent().vm.$emit('query-variables-updated', {
          sort: 'CREATED_ASC',
          pagination: { first: null, after: null, before: 'cursor456', last: 20 },
          filters: { statusGroup: 'FINISHED' },
          updatedAfter: null,
        });
        await waitForPromises();
      });

      it('saves them against the project path so a later mount can restore them', () => {
        expect(saveSessionsQueryVariables).toHaveBeenCalledWith('some/project/path', {
          sort: 'CREATED_ASC',
          pagination: { first: null, after: null, before: 'cursor456', last: 20 },
          filters: { statusGroup: 'FINISHED' },
        });
      });
    });
  });
});
