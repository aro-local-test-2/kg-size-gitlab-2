import { buildAgentPlanWidget, writeAgentPlanToCache } from 'ee/work_items/graphql/cache_utils';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';

describe('agent plan cache utils', () => {
  const workItemId = 'gid://gitlab/WorkItem/1';
  const workItemIid = '1';

  describe('buildAgentPlanWidget', () => {
    it('builds the agent plan widget shape', () => {
      expect(
        buildAgentPlanWidget({
          content: 'some plan',
          contentHtml: '<p>some plan</p>',
          aiPlanningEnabled: true,
          readinessScore: 72,
          generationStatus: 'GENERATING',
        }),
      ).toEqual({
        type: 'AGENT_PLAN',
        content: 'some plan',
        contentHtml: '<p>some plan</p>',
        aiPlanningEnabled: true,
        readinessScore: 72,
        generationStatus: 'GENERATING',
        __typename: 'WorkItemWidgetAgentPlan',
      });
    });

    it('defaults the readiness score to null', () => {
      expect(buildAgentPlanWidget({ content: 'some plan' }).readinessScore).toBe(null);
    });

    it('defaults the generation status to null', () => {
      expect(buildAgentPlanWidget({ content: 'some plan' }).generationStatus).toBe(null);
    });
  });

  describe('writeAgentPlanToCache', () => {
    let cache;

    beforeEach(() => {
      cache = { writeQuery: jest.fn() };
    });

    describe('when useWorkItemFeatures is false', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'widgets plan',
          contentHtml: '<p>widgets plan</p>',
          aiPlanningEnabled: true,
          useWorkItemFeatures: false,
        });
      });

      it('writes the widgets shape', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith({
          query: workItemAgentPlanQuery,
          variables: { id: workItemId, useWorkItemFeatures: false, includeReadinessScore: false },
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              iid: workItemIid,
              widgets: [
                buildAgentPlanWidget({
                  content: 'widgets plan',
                  contentHtml: '<p>widgets plan</p>',
                  aiPlanningEnabled: true,
                }),
              ],
            },
          },
        });
      });
    });

    describe('when useWorkItemFeatures is true', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'features plan',
          contentHtml: '<p>features plan</p>',
          aiPlanningEnabled: true,
          useWorkItemFeatures: true,
        });
      });

      it('writes the features shape', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith({
          query: workItemAgentPlanQuery,
          variables: { id: workItemId, useWorkItemFeatures: true, includeReadinessScore: false },
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              iid: workItemIid,
              features: {
                __typename: 'WorkItemFeatures',
                agentPlan: buildAgentPlanWidget({
                  content: 'features plan',
                  contentHtml: '<p>features plan</p>',
                  aiPlanningEnabled: true,
                }),
              },
            },
          },
        });
      });
    });

    describe('when includeReadinessScore is true', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'scored plan',
          contentHtml: '<p>scored plan</p>',
          aiPlanningEnabled: true,
          readinessScore: 85,
          useWorkItemFeatures: false,
          includeReadinessScore: true,
        });
      });

      it('requests the readiness score in the written selection set', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith(
          expect.objectContaining({
            variables: { id: workItemId, useWorkItemFeatures: false, includeReadinessScore: true },
          }),
        );
      });

      it('preserves the readiness score alongside the new content', () => {
        const { data } = cache.writeQuery.mock.calls[0][0];

        expect(data.workItem.widgets[0]).toMatchObject({
          content: 'scored plan',
          contentHtml: '<p>scored plan</p>',
          readinessScore: 85,
        });
      });
    });
  });
});
