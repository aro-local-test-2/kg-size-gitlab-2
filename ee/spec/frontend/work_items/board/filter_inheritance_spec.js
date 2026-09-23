import { resolveInheritedWidgetsDraft } from '~/work_items/board/filter_inheritance';
import searchIterationsQuery from 'ee/work_items/board/graphql/search_iterations.query.graphql';
import * as Sentry from '~/sentry/sentry_browser_wrapper';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('board filter inheritance (EE)', () => {
  const fullPath = 'group/project';

  const sprint = {
    __typename: 'Iteration',
    id: 'gid://gitlab/Iteration/5',
    title: 'Sprint 1',
    startDate: '2026-01-01',
    dueDate: '2026-01-14',
    webUrl: '/sprint-5',
    iterationCadence: {
      __typename: 'IterationCadence',
      id: 'gid://gitlab/Iterations::Cadence/1',
      title: 'Cadence',
    },
  };

  const iterationsResponse = (nodes, { isGroup = false } = {}) => ({
    data: isGroup
      ? { group: { id: 'gid://gitlab/Group/1', iterations: { nodes } } }
      : { project: { id: 'gid://gitlab/Project/1', iterations: { nodes } } },
  });

  const createClient = (queryImpl = () => Promise.resolve(iterationsResponse([]))) => ({
    query: jest.fn(queryImpl),
  });

  describe('iteration', () => {
    it('returns an empty draft and runs no query when no iteration filter is active', async () => {
      const apolloClient = createClient();

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: {},
      });

      expect(result).toEqual({});
      expect(apolloClient.query).not.toHaveBeenCalled();
    });

    it('resolves the iteration id into an iteration widgets-draft fragment', async () => {
      const apolloClient = createClient(() => Promise.resolve(iterationsResponse([sprint])));

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: { iterationId: '5' },
      });

      expect(apolloClient.query).toHaveBeenCalledWith({
        query: searchIterationsQuery,
        variables: { fullPath, isProject: true, id: 'gid://gitlab/Iteration/5' },
      });
      expect(result).toEqual({ ITERATION: { iteration: sprint } });
    });

    it('reads group iterations for a group board', async () => {
      const apolloClient = createClient(() =>
        Promise.resolve(iterationsResponse([sprint], { isGroup: true })),
      );

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: true,
        filters: { iterationId: '5' },
      });

      expect(apolloClient.query).toHaveBeenCalledWith({
        query: searchIterationsQuery,
        variables: { fullPath, isProject: false, id: 'gid://gitlab/Iteration/5' },
      });
      expect(result).toEqual({ ITERATION: { iteration: sprint } });
    });

    it('yields an empty draft when the id does not resolve to an iteration', async () => {
      const apolloClient = createClient(() => Promise.resolve(iterationsResponse([])));

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: { iterationId: '5' },
      });

      expect(result).toEqual({});
    });

    it('captures the error and yields an empty draft when the query fails', async () => {
      const error = new Error('error');
      const apolloClient = createClient(() => Promise.reject(error));

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: { iterationId: '5' },
      });

      expect(result).toEqual({});
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });
  });

  describe('weight', () => {
    it('returns an empty draft and runs no query when no weight filter is active', async () => {
      const apolloClient = createClient();

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: {},
      });

      expect(result).toEqual({});
      expect(apolloClient.query).not.toHaveBeenCalled();
    });

    it('inherits a numeric weight without a lookup', async () => {
      const apolloClient = createClient();

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: { weight: '3' },
      });

      expect(result).toEqual({ WEIGHT: { weight: 3 } });
      expect(apolloClient.query).not.toHaveBeenCalled();
    });

    it('does not inherit a wildcard weight filter', async () => {
      const apolloClient = createClient();

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: { weightWildcardId: 'ANY' },
      });

      expect(result).toEqual({});
    });
  });

  describe('health status', () => {
    it.each(['onTrack', 'needsAttention', 'atRisk'])(
      'inherits the %s health status without a lookup',
      async (healthStatus) => {
        const apolloClient = createClient();

        const result = await resolveInheritedWidgetsDraft({
          apolloClient,
          fullPath,
          isGroup: false,
          filters: { healthStatusFilter: healthStatus },
        });

        expect(result).toEqual({ HEALTH_STATUS: { healthStatus } });
        expect(apolloClient.query).not.toHaveBeenCalled();
      },
    );

    it.each(['ANY', 'NONE'])('does not inherit the %s wildcard health status', async (wildcard) => {
      const apolloClient = createClient();

      const result = await resolveInheritedWidgetsDraft({
        apolloClient,
        fullPath,
        isGroup: false,
        filters: { healthStatusFilter: wildcard },
      });

      expect(result).toEqual({});
    });
  });

  it('inherits iteration, weight, and health status together', async () => {
    const apolloClient = createClient(() => Promise.resolve(iterationsResponse([sprint])));

    const result = await resolveInheritedWidgetsDraft({
      apolloClient,
      fullPath,
      isGroup: false,
      filters: { iterationId: '5', weight: '2', healthStatusFilter: 'onTrack' },
    });

    expect(result).toEqual({
      ITERATION: { iteration: sprint },
      WEIGHT: { weight: 2 },
      HEALTH_STATUS: { healthStatus: 'onTrack' },
    });
  });
});
