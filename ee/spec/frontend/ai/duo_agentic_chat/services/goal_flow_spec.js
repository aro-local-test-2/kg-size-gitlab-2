import getConfiguredFlows from 'ee/ai/graphql/get_configured_flows.query.graphql';
import {
  GOAL_FLOW_MODE,
  GOAL_FLOW_REFERENCE,
  getGoalFlow,
} from 'ee/ai/duo_agentic_chat/services/goal_flow';

describe('goal flow', () => {
  const PROJECT_ID = 'gid://gitlab/Project/1';

  beforeEach(() => {
    window.gon = { features: { duoChatGoalCommand: true } };
  });

  const apolloReturning = (...consumers) => ({
    query: jest.fn().mockResolvedValue({
      data: { aiCatalogConfiguredItems: { nodes: consumers } },
    }),
  });

  // Goal mode selects a configuration; it must not change which flow runs.
  it('names the Developer flow and the mode that configures it', () => {
    expect(GOAL_FLOW_REFERENCE).toBe('developer/v1');
    expect(GOAL_FLOW_MODE).toBe('goal');
  });

  it('asks for the Developer flow configured in the project the chat is pointed at', async () => {
    const apollo = apolloReturning();

    await getGoalFlow({ apollo, projectId: PROJECT_ID });

    expect(apollo.query).toHaveBeenCalledWith(
      expect.objectContaining({
        query: getConfiguredFlows,
        variables: { projectId: PROJECT_ID, foundationalFlowReference: GOAL_FLOW_REFERENCE },
      }),
    );
  });

  // Cache-first is what makes two callers cost one request.
  it('leaves the fetch policy to the client default', async () => {
    const apollo = apolloReturning();

    await getGoalFlow({ apollo, projectId: PROJECT_ID });

    expect(apollo.query.mock.calls[0][0]).not.toHaveProperty('fetchPolicy');
  });

  // The envelope carries an id rather than a GID.
  it('resolves the flow, carrying its consumer id as a number', async () => {
    const apollo = apolloReturning({ id: 'gid://gitlab/Ai::Catalog::ItemConsumer/7' });

    await expect(getGoalFlow({ apollo, projectId: PROJECT_ID })).resolves.toEqual({
      consumerId: 7,
    });
  });

  it('takes the first when the project has more than one', async () => {
    const apollo = apolloReturning(
      { id: 'gid://gitlab/Ai::Catalog::ItemConsumer/7' },
      { id: 'gid://gitlab/Ai::Catalog::ItemConsumer/9' },
    );

    await expect(getGoalFlow({ apollo, projectId: PROJECT_ID })).resolves.toEqual({
      consumerId: 7,
    });
  });

  // Every reason answers alike, so a caller asks once rather than working a checklist.
  describe('when goal mode cannot run', () => {
    it.each([{ features: {} }, { features: { duoChatGoalCommand: false } }, {}, undefined])(
      'is null, and asks nothing, with gon of %p',
      async (gon) => {
        window.gon = gon;
        const apollo = apolloReturning({ id: 'gid://gitlab/Ai::Catalog::ItemConsumer/7' });

        await expect(getGoalFlow({ apollo, projectId: PROJECT_ID })).resolves.toBeNull();
        expect(apollo.query).not.toHaveBeenCalled();
      },
    );

    // Also how a user without `read_ai_foundational_flow` looks.
    it('is null when the flow is not configured', async () => {
      await expect(
        getGoalFlow({ apollo: apolloReturning(), projectId: PROJECT_ID }),
      ).resolves.toBeNull();
    });

    it('is null, and asks nothing, without a project', async () => {
      const apollo = apolloReturning();

      await expect(getGoalFlow({ apollo })).resolves.toBeNull();
      expect(apollo.query).not.toHaveBeenCalled();
    });

    it('is null when called with nothing at all', async () => {
      await expect(getGoalFlow()).resolves.toBeNull();
    });

    it('is null when the response carries no data', async () => {
      const apollo = { query: jest.fn().mockResolvedValue({}) };

      await expect(getGoalFlow({ apollo, projectId: PROJECT_ID })).resolves.toBeNull();
    });
  });
});
