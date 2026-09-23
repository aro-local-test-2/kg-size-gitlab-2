import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { ACTIONS } from './catalog/actions';
import { RULES } from './catalog/rules';
import { TRIGGERS } from './catalog/triggers';

/**
 * A rejected GraphQL mutation's user-facing store message, thrown so callers
 * can tell a store rejection from a failed request.
 */
export class PolicyStoreMutationError extends Error {
  constructor(message) {
    super(message);
    // Sentry groups by error.name, which plain subclassing leaves as 'Error'.
    this.name = 'PolicyStoreMutationError';
  }
}

/**
 * Reads the reason the Policy Store rejected a write from a failed request.
 *
 * A rejected mutation carries it as the PolicyStoreMutationError message. The
 * mutations also raise user-facing top-level GraphQL errors (a missing
 * policy, the experiment being off, an engine fault), which Apollo rejects as
 * an error with `graphQLErrors`. A REST 400 carries it under `message` (e.g.
 * a duplicate name), or under `error` for Grape param validation. A plain
 * request error yields nothing, so callers keep their own copy. An
 * empty-string message is returned as-is, so callers should fall back to
 * their own generic copy on any falsy result.
 *
 * @param {Error} error - The error from the failed request.
 * @returns {string|undefined} The store's message, if the error carried one.
 */
export const apiErrorMessage = (error) => {
  if (error instanceof PolicyStoreMutationError) return error.message;

  // GraphQL top-level errors
  if (error?.graphQLErrors?.[0]?.message) return error.graphQLErrors[0].message;

  // REST errors (axios wraps the response under error.response.data)
  const data = error?.response?.data;
  return [data?.message, data?.error].find((reason) => typeof reason === 'string');
};

export const EMPTY_CATALOGS = Object.freeze({
  triggers: [],
  rules: [],
  actions: [],
});

const LOCAL_CATALOGS = { triggers: TRIGGERS, rules: RULES, actions: ACTIONS };

export const CATALOG_NAMES = Object.freeze(Object.keys(LOCAL_CATALOGS));

export const presentable = ({ id, name }, localCatalog) =>
  localCatalog.find((entry) => entry.id === id) ?? {
    id,
    label: name || id,
    description: '',
    icon: 'question-o',
    fields: [],
  };

const toCatalog = (name, remoteEntries) => {
  const entries = Array.isArray(remoteEntries) ? remoteEntries.filter((remote) => remote?.id) : [];

  // An empty catalog cannot build a policy, so a healthy-but-empty response is
  // as unusable as a missing one.
  if (!entries.length) {
    Sentry.captureException(new Error(`Policy Store returned no ${name}`), {
      tags: { policyStoreCatalog: name },
    });

    return null;
  }

  return entries.map((remote) => presentable(remote, LOCAL_CATALOGS[name]));
};

/**
 * Maps the `policyStore` GraphQL payload to the wizard's catalogs.
 *
 * The local catalog files supply the presentation (label, description, icon,
 * category, config fields) for the ids the API returns. Each catalog fails
 * independently: one that is missing or empty resolves as an empty list and
 * its name appears in `failedCatalogs`, while the others keep their entries.
 * Every failure is reported to Sentry, tagged with the failing catalog.
 *
 * @param {Object|null} policyStore - The `organization.policyStore` query
 *   result; null when the experiment is not active for the organization.
 * @returns {{ catalogs: { triggers: Array, rules: Array, actions: Array },
 *   failedCatalogs: string[] }}
 */
export const toCatalogs = (policyStore) => {
  // Not EMPTY_CATALOGS: that object is frozen and shared, but this one
  // gets filled in below, so it needs to be a fresh, mutable object.
  const catalogs = { triggers: [], rules: [], actions: [] };
  const failedCatalogs = [];

  CATALOG_NAMES.forEach((name) => {
    const entries = toCatalog(name, policyStore?.[name]);

    if (entries) {
      catalogs[name] = entries;
    } else {
      failedCatalogs.push(name);
    }
  });

  return { catalogs, failedCatalogs };
};

/**
 * Whether a store message reports the org-wide unique-name rule was violated.
 *
 * Matched exactly: both store backends raise this bare string, and the
 * ActiveRecord backend joins multiple validation failures into one sentence —
 * a combined message must fall through to the page alert so the other
 * failure reasons stay visible.
 *
 * @param {string|undefined} message - The message from apiErrorMessage.
 * @returns {boolean} Whether the save failed only because the name is taken.
 */
export const isDuplicateNameError = (message) =>
  /^name has already been taken$/i.test((message || '').trim());

const RULE_REGO_PARSE_REFUSAL = /^rules\[\d+\] is invalid:/i;

/**
 * Whether a store message reports a rule whose Rego does not parse.
 *
 * Matched on the whole message, not on segments: the store reports only the
 * first unparseable rule, as `rules[N] is invalid: <engine message> (at
 * <line>:<column>)`, and joins that one rule's engine errors with `; ` inside
 * it — so a two-typo program is still a single refusal.
 *
 * A merged-program refusal (`policy_rego is invalid: ...`, raised when rules
 * parse alone but conflict once combined) is author input too, but is a
 * different shape and is deliberately not matched here.
 *
 * @param {string|undefined} message - The message from apiErrorMessage.
 * @returns {boolean} Whether the save failed on unparseable rule Rego.
 */
export const isRuleRegoParseError = (message) =>
  RULE_REGO_PARSE_REFUSAL.test((message || '').trim());
