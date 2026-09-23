import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  apiErrorMessage,
  EMPTY_CATALOGS,
  isDuplicateNameError,
  isRuleRegoParseError,
  PolicyStoreMutationError,
  toCatalogs,
} from 'ee/policy_store/utils';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { RULES } from 'ee/policy_store/catalog/rules';
import { TRIGGERS } from 'ee/policy_store/catalog/triggers';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('apiErrorMessage', () => {
  it('returns the store message a rejected mutation carries', () => {
    const error = new PolicyStoreMutationError('Name has already been taken');

    expect(apiErrorMessage(error)).toBe('Name has already been taken');
  });

  it('returns an empty store message as-is for callers to fall back on', () => {
    expect(apiErrorMessage(new PolicyStoreMutationError(''))).toBe('');
  });

  it('returns the first top-level GraphQL error message the mutation raised', () => {
    const error = Object.assign(new Error('GraphQL error: not available'), {
      graphQLErrors: [{ message: 'not available' }, { message: 'second' }],
    });

    expect(apiErrorMessage(error)).toBe('not available');
  });

  it.each`
    description                        | error
    ${'a request error'}               | ${new Error('network down')}
    ${'an empty GraphQL errors array'} | ${{ graphQLErrors: [] }}
    ${'nothing at all'}                | ${undefined}
  `('returns nothing for $description', ({ error }) => {
    expect(apiErrorMessage(error)).toBeUndefined();
  });

  describe('REST error responses (group API)', () => {
    it('extracts the message from an axios error response.data.message', () => {
      const error = { response: { data: { message: 'Name has already been taken' } } };

      expect(apiErrorMessage(error)).toBe('Name has already been taken');
    });

    it('extracts the error from an axios error response.data.error (Grape validation)', () => {
      const error = { response: { data: { error: 'rule 0: unsupported type' } } };

      expect(apiErrorMessage(error)).toBe('rule 0: unsupported type');
    });

    it('prefers message over error when both are present', () => {
      const error = {
        response: { data: { message: 'Validation failed', error: 'param missing' } },
      };

      expect(apiErrorMessage(error)).toBe('Validation failed');
    });

    it('returns undefined for a non-string message (Rails-style nested errors)', () => {
      const error = { response: { data: { message: { name: ['is too long'] } } } };

      expect(apiErrorMessage(error)).toBeUndefined();
    });

    it('returns undefined when response.data has neither message nor error', () => {
      const error = { response: { data: { other: 'field' } } };

      expect(apiErrorMessage(error)).toBeUndefined();
    });
  });
});

describe('policy store catalogs', () => {
  const healthyPolicyStore = ({
    triggers = [{ id: 'deployment_requested', name: 'Deployment' }],
    rules = [{ id: 'custom', name: 'Custom' }],
    actions = [{ id: 'block', name: 'Block' }],
  } = {}) => ({ triggers, rules, actions });

  it('exposes empty catalogs for consumers to start from', () => {
    expect(EMPTY_CATALOGS).toEqual({ triggers: [], rules: [], actions: [] });
  });

  it('presents an id the local catalog knows with its full local entry', () => {
    const { catalogs, failedCatalogs } = toCatalogs(
      healthyPolicyStore({
        rules: [
          { id: 'calendar', name: 'Calendar' },
          { id: 'environment', name: 'Environment' },
        ],
      }),
    );

    expect(failedCatalogs).toEqual([]);
    expect(catalogs.triggers).toEqual([TRIGGERS.find(({ id }) => id === 'deployment_requested')]);
    expect(catalogs.rules).toEqual([
      RULES.find(({ id }) => id === 'calendar'),
      RULES.find(({ id }) => id === 'environment'),
    ]);
    expect(catalogs.actions).toEqual([ACTIONS.find(({ id }) => id === 'block')]);
  });

  it('presents an unknown id as a minimal entry named by the API', () => {
    const { catalogs } = toCatalogs(
      healthyPolicyStore({ rules: [{ id: 'holiday', name: 'Holiday' }] }),
    );

    expect(catalogs.rules).toEqual([
      { id: 'holiday', label: 'Holiday', description: '', icon: 'question-o', fields: [] },
    ]);
  });

  it('drops entries without an id, which cannot serve as the wire value', () => {
    const { catalogs } = toCatalogs(
      healthyPolicyStore({
        rules: [{}, { name: 'No id' }, { id: 'custom', name: 'Custom' }, null],
      }),
    );

    expect(catalogs.rules).toEqual([RULES.find(({ id }) => id === 'custom')]);
  });

  it('names an empty catalog as failed while the others keep their entries', () => {
    const { catalogs, failedCatalogs } = toCatalogs(healthyPolicyStore({ triggers: [] }));

    expect(failedCatalogs).toEqual(['triggers']);
    expect(catalogs.triggers).toEqual([]);
    expect(catalogs.rules).toEqual([RULES.find(({ id }) => id === 'custom')]);
    expect(catalogs.actions).toEqual([ACTIONS.find(({ id }) => id === 'block')]);
    expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error), {
      tags: { policyStoreCatalog: 'triggers' },
    });
  });

  it('names every failing catalog when several are empty', () => {
    const { failedCatalogs } = toCatalogs(healthyPolicyStore({ triggers: [], actions: [] }));

    expect(failedCatalogs).toEqual(['triggers', 'actions']);
  });

  it('treats a catalog with only unusable entries as failed', () => {
    const { failedCatalogs } = toCatalogs(healthyPolicyStore({ actions: [{}, { name: 'No id' }] }));

    expect(failedCatalogs).toEqual(['actions']);
  });

  it('treats a malformed catalog as failed', () => {
    const { failedCatalogs } = toCatalogs(healthyPolicyStore({ triggers: { not: 'an array' } }));

    expect(failedCatalogs).toEqual(['triggers']);
    expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error), {
      tags: { policyStoreCatalog: 'triggers' },
    });
  });

  it('fails every catalog for a null policyStore, as when the experiment is off', () => {
    const { catalogs, failedCatalogs } = toCatalogs(null);

    expect(failedCatalogs).toEqual(['triggers', 'rules', 'actions']);
    expect(catalogs).toEqual(EMPTY_CATALOGS);
  });
});

describe('isDuplicateNameError', () => {
  it.each`
    description                                          | message                                                                    | expected
    ${'the bare message both backends raise'}            | ${'Name has already been taken'}                                           | ${true}
    ${'the bare message regardless of case and padding'} | ${' name HAS already been taken '}                                         | ${true}
    ${'a sentence combining it with other failures'}     | ${'Name has already been taken and Namespace must match the organization'} | ${false}
    ${'an unrelated validation message'}                 | ${'rule 0: unsupported rule type "calendar"'}                              | ${false}
    ${'no message at all'}                               | ${undefined}                                                               | ${false}
  `('recognises $description as $expected', ({ message, expected }) => {
    expect(isDuplicateNameError(message)).toBe(expected);
  });
});

describe('isRuleRegoParseError', () => {
  it.each`
    description                                        | message                                                             | expected
    ${'the refusal the store raises for one error'}    | ${'rules[0] is invalid: expecting expression (at 5:1)'}             | ${true}
    ${"one rule's engine errors joined with '; '"}     | ${'rules[0] is invalid: unexpected token; missing value'}           | ${true}
    ${'an engine message that quotes source with ;'}   | ${'rules[0] is invalid: unexpected eof: allow { a; b } (at 1:1)'}   | ${true}
    ${'a truncated engine message'}                    | ${'rules[0] is invalid: expecting expression in rule body allo...'} | ${true}
    ${'a refusal for a rule past the first ten'}       | ${'rules[11] is invalid: expecting expression (at 1:1)'}            | ${true}
    ${'a refusal with surrounding padding'}            | ${'  rules[0] is invalid: expecting expression (at 5:1)  '}         | ${true}
    ${'a merged-program refusal, a different shape'}   | ${'policy_rego is invalid: var msg is unsafe (at 3:3)'}             | ${false}
    ${'an engine fault, which is not a parse failure'} | ${'rules[0] could not be validated'}                                | ${false}
    ${'an unrelated validation message'}               | ${'Name has already been taken'}                                    | ${false}
    ${'a non-Rego rule validation message'}            | ${'rule 0: unsupported rule type "calendar"'}                       | ${false}
    ${'an empty message'}                              | ${''}                                                               | ${false}
    ${'no message at all'}                             | ${undefined}                                                        | ${false}
  `('recognises $description as $expected', ({ message, expected }) => {
    expect(isRuleRegoParseError(message)).toBe(expected);
  });
});
