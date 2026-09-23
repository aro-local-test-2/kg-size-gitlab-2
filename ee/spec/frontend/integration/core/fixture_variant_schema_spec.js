import {
  defineFixtureVariants,
  getVariant,
  getActiveVariant,
  setQueryVariant,
  activateVariant,
  resetAllVariants,
} from './fixture_variant_schema';

const validFixture = (overrides = {}) => ({ data: { foo: 'bar' }, errors: [], ...overrides });

describe('fixture_variant_schema', () => {
  describe('defineFixtureVariants', () => {
    it('registers variants and returns the frozen map', () => {
      const variants = defineFixtureVariants({
        query: 'testQueryRegisters',
        variants: { BASE: validFixture(), WITH_ERROR: validFixture() },
      });

      expect(Object.isFrozen(variants)).toBe(true);
      expect(getVariant('testQueryRegisters', 'BASE')).toEqual(validFixture());
    });

    it('normalises a fixture that omits the errors field', () => {
      defineFixtureVariants({
        query: 'testQueryNormalises',
        variants: { BASE: { data: { foo: 'bar' } } },
      });

      expect(getVariant('testQueryNormalises', 'BASE').errors).toEqual([]);
    });

    describe('when BASE is missing', () => {
      it('throws', () => {
        expect(() =>
          defineFixtureVariants({
            query: 'testQueryNoBase',
            variants: { WITH_ERROR: validFixture() },
          }),
        ).toThrow(/"variants.BASE" is required/);
      });
    });

    describe('when a variant key is not UPPER_SNAKE_CASE', () => {
      it('throws', () => {
        expect(() =>
          defineFixtureVariants({
            query: 'testQueryBadKey',
            variants: { BASE: validFixture(), withError: validFixture() },
          }),
        ).toThrow(/must be UPPER_SNAKE_CASE/);
      });
    });

    describe('when a variant is not a valid GraphQL fixture', () => {
      it('throws', () => {
        expect(() =>
          defineFixtureVariants({
            query: 'testQueryBadFixture',
            variants: { BASE: { notData: true } },
          }),
        ).toThrow(/not a valid GraphQL fixture/);
      });
    });
  });

  describe('getActiveVariant', () => {
    beforeAll(() => {
      defineFixtureVariants({
        query: 'testQueryActive',
        variants: { BASE: validFixture(), WITH_ERROR: validFixture({ data: {} }) },
      });
    });

    afterAll(() => {
      resetAllVariants();
    });

    it('returns null while the query is at its BASE default', () => {
      expect(getActiveVariant('testQueryActive')).toBe(null);
    });

    describe('when a variant is activated', () => {
      beforeEach(() => {
        activateVariant('testQueryActive', 'WITH_ERROR');
      });

      it('returns the active variant', () => {
        expect(getActiveVariant('testQueryActive')).toEqual(validFixture({ data: {} }));
      });
    });
  });

  describe('activateVariant', () => {
    beforeAll(() => {
      defineFixtureVariants({
        query: 'testQueryActivate',
        variants: { BASE: validFixture() },
      });
    });

    afterAll(() => {
      resetAllVariants();
    });

    describe('when the query has no registered variants', () => {
      it('throws', () => {
        expect(() => activateVariant('unknownQuery', 'BASE')).toThrow(/no variants registered/);
      });
    });

    describe('when the variant key is unknown', () => {
      it('throws', () => {
        expect(() => activateVariant('testQueryActivate', 'NOPE')).toThrow(/unknown variant/);
      });
    });
  });

  describe('setQueryVariant', () => {
    let constant;

    beforeAll(() => {
      constant = defineFixtureVariants({
        query: 'testQuerySetVariant',
        variants: { BASE: validFixture(), WITH_ERROR: validFixture({ data: {} }) },
      });
    });

    afterEach(() => {
      resetAllVariants();
    });

    it('activates a variant via a key-named method on the query constant', () => {
      setQueryVariant(constant).withError();

      expect(getActiveVariant('testQuerySetVariant')).toEqual(validFixture({ data: {} }));
    });

    describe('when passed something other than a query constant', () => {
      it('throws', () => {
        expect(() => setQueryVariant('testQuerySetVariant')).toThrow(/expected a query constant/);
      });
    });
  });

  describe('resetAllVariants', () => {
    it('resets an activated query back to BASE', () => {
      defineFixtureVariants({
        query: 'testQueryReset',
        variants: { BASE: validFixture(), WITH_ERROR: validFixture({ data: {} }) },
      });
      activateVariant('testQueryReset', 'WITH_ERROR');
      expect(getActiveVariant('testQueryReset')).not.toBe(null);

      resetAllVariants();

      expect(getActiveVariant('testQueryReset')).toBe(null);
    });
  });
});
