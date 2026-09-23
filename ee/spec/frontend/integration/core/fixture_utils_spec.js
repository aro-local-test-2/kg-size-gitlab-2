import { setFixtureData, setFixtureErrors, setFixtureItemsCount } from './fixture_utils';

const buildFixture = () => ({
  data: {
    namespace: {
      workItem: {
        id: 'gid://gitlab/WorkItem/1',
        userPermissions: { updateWorkItem: true },
        widgets: {
          nodes: [{ id: 'gid://gitlab/Node/1', __typename: 'Node' }],
          __typename: 'WidgetConnection',
        },
      },
    },
  },
  errors: [],
});

describe('fixture_utils', () => {
  describe('setFixtureData', () => {
    it('sets the first matching key and returns a new fixture', () => {
      const fixture = buildFixture();

      const result = setFixtureData(fixture, 'updateWorkItem', false);

      expect(result.data.namespace.workItem.userPermissions.updateWorkItem).toBe(false);
    });

    it('does not mutate the fixture it receives', () => {
      const fixture = buildFixture();

      setFixtureData(fixture, 'updateWorkItem', false);

      expect(fixture.data.namespace.workItem.userPermissions.updateWorkItem).toBe(true);
    });

    describe('when the fixture is not a valid GraphQL fixture', () => {
      it('throws', () => {
        expect(() => setFixtureData({ notData: true }, 'foo', 1)).toThrow(
          /Invalid GraphQL fixture/,
        );
      });
    });

    describe('when no key matches', () => {
      it('throws', () => {
        const fixture = buildFixture();

        expect(() => setFixtureData(fixture, 'doesNotExist', false)).toThrow(
          /Property "doesNotExist" was not found/,
        );
      });
    });

    describe('when the selector is neither a key nor a path object', () => {
      it('throws', () => {
        expect(() => setFixtureData(buildFixture(), null, 1)).toThrow(/non-empty key name/);
      });
    });

    describe('when given a path selector', () => {
      const buildAmbiguousFixture = () => ({
        data: {
          namespace: {
            note: {
              awardEmoji: { nodes: [{ name: 'thumbsup' }] },
              userPermissions: { awardEmoji: true },
            },
          },
        },
        errors: [],
      });

      it('targets the exact node instead of the first key match', () => {
        const fixture = buildAmbiguousFixture();

        const result = setFixtureData(
          fixture,
          { path: 'namespace.note.userPermissions.awardEmoji' },
          false,
        );

        expect(result.data.namespace.note.userPermissions.awardEmoji).toBe(false);
        expect(result.data.namespace.note.awardEmoji.nodes).toHaveLength(1);
      });

      it('does not mutate the fixture it receives', () => {
        const fixture = buildAmbiguousFixture();

        setFixtureData(fixture, { path: 'namespace.note.userPermissions.awardEmoji' }, false);

        expect(fixture.data.namespace.note.userPermissions.awardEmoji).toBe(true);
      });
    });
  });

  describe('setFixtureErrors', () => {
    it('sets errors, clears data, and returns a new fixture', () => {
      const fixture = buildFixture();

      const result = setFixtureErrors(fixture, ['Boom']);

      expect(result.errors).toEqual([{ message: 'Boom' }]);
      expect(result.data).toEqual({});
    });

    it('does not mutate the fixture it receives', () => {
      const fixture = buildFixture();

      setFixtureErrors(fixture, ['Boom']);

      expect(fixture.errors).toEqual([]);
      expect(fixture.data.namespace).toBeDefined();
    });

    describe('when errors is not an array of strings', () => {
      it('throws', () => {
        expect(() => setFixtureErrors(buildFixture(), [{}])).toThrow(/array of error messages/);
      });
    });
  });

  describe('setFixtureItemsCount', () => {
    it('grows a connection by cloning the last node and incrementing its id', () => {
      const fixture = buildFixture();

      const result = setFixtureItemsCount({ fixture, lookupKey: 'widgets', itemCount: 3 });
      const { nodes } = result.data.namespace.workItem.widgets;

      expect(nodes).toHaveLength(3);
      expect(nodes.map((n) => n.id)).toEqual([
        'gid://gitlab/Node/1',
        'gid://gitlab/Node/2',
        'gid://gitlab/Node/3',
      ]);
    });

    it('shrinks a connection and does not mutate the input', () => {
      const fixture = buildFixture();

      const result = setFixtureItemsCount({ fixture, lookupKey: 'widgets', itemCount: 0 });

      expect(result.data.namespace.workItem.widgets.nodes).toHaveLength(0);
      expect(fixture.data.namespace.workItem.widgets.nodes).toHaveLength(1);
    });

    describe('when the lookupKey is "nodes"', () => {
      it('throws', () => {
        expect(() =>
          setFixtureItemsCount({ fixture: buildFixture(), lookupKey: 'nodes', itemCount: 1 }),
        ).toThrow(/must be the connection key/);
      });
    });
  });
});
