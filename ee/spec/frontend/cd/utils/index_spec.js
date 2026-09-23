import { buildRowClass } from 'ee/cd/utils';

describe('CD utils', () => {
  describe('buildRowClass', () => {
    const matchingId = 'gid://gitlab/Cd::Rollout/1';
    const otherId = 'gid://gitlab/Cd::Rollout/2';
    const baseClass = 'gl-cursor-pointer hover:gl-bg-subtle';

    it('returns the base row class for a non-matching id', () => {
      expect(buildRowClass('gid://gitlab/Cd::Rollout/3', [[matchingId, 'first']])).toBe(baseClass);
    });

    it('appends the matched class for a matching id', () => {
      expect(buildRowClass(matchingId, [[matchingId, 'first']])).toEqual([baseClass, 'first']);
    });

    it('returns the first matching class among multiple matches', () => {
      expect(
        buildRowClass(matchingId, [
          [matchingId, 'first'],
          [matchingId, 'second'],
        ]),
      ).toEqual([baseClass, 'first']);
    });

    it('does not match a null id against a null matcher', () => {
      expect(
        buildRowClass(null, [
          [null, 'first'],
          [otherId, 'second'],
        ]),
      ).toBe(baseClass);
    });
  });
});
