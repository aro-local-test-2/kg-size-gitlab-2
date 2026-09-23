import { camelCase } from 'lodash-es';
import { isValidGraphqlFixture } from './fixture_utils';

const UPPER_SNAKE_CASE_RE = /^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$/;

const variantRegistry = new Map();

/**
 * Low-level primitive: activates a variant by query name and key string. Prefer
 * setQueryVariant(constant) in specs; reach for this only when the key is dynamic
 * (a runtime value), e.g. a shared helper that is handed a variant key.
 *
 * @param {string} query - The camelCase GraphQL operation name.
 * @param {string} variantKey - The UPPER_SNAKE_CASE variant key to activate.
 */
export function activateVariant(query, variantKey) {
  const entry = variantRegistry.get(query);

  if (!entry) {
    throw new Error(
      `activateVariant: no variants registered for query "${query}". ` +
        'Did you forget to import the variant file?',
    );
  }

  if (!(variantKey in entry.variants)) {
    const available = Object.keys(entry.variants).join(', ');
    throw new Error(
      `activateVariant: unknown variant "${variantKey}" for query "${query}". Available: ${available}`,
    );
  }

  entry.active = variantKey;
}

/**
 * Defines and registers a named set of fixture variants for a GraphQL operation.
 *
 * Every variant file must call this function and export its return value as the
 * default export. The `BASE` variant is mandatory — it is the fixture served by
 * default and the reference point for all other variants.
 *
 * @param {Object} param0
 * @param {string} param0.query - The camelCase GraphQL operation name (must match the MSW handler key).
 * @param {Object} param0.variants - A map of UPPER_SNAKE_CASE variant keys to valid GraphQL fixture objects.
 *   `BASE` is required.
 * @returns {Object} The validated variants object (frozen).
 *
 * @example
 * export default defineFixtureVariants({
 *   query: 'namespaceWorkItem',
 *   variants: {
 *     BASE: namespaceWorkItemFixture,
 *     WITH_ERROR: setFixtureErrors(cloneDeep(namespaceWorkItemFixture), ['Something went wrong']),
 *   },
 * });
 */
export function defineFixtureVariants({ query, variants } = {}) {
  if (!query || typeof query !== 'string') {
    throw new Error('defineFixtureVariants: "query" must be a non-empty string');
  }

  if (!variants || typeof variants !== 'object' || Array.isArray(variants)) {
    throw new Error('defineFixtureVariants: "variants" must be a plain object');
  }

  if (!('BASE' in variants)) {
    throw new Error(
      `defineFixtureVariants: "variants.BASE" is required for query "${query}". ` +
        'BASE is the default fixture served when no variant is active.',
    );
  }

  const normalised = {};

  for (const [key, value] of Object.entries(variants)) {
    if (!UPPER_SNAKE_CASE_RE.test(key)) {
      throw new Error(
        `defineFixtureVariants: variant key "${key}" must be UPPER_SNAKE_CASE (e.g. BASE, WITH_ERROR, EMPTY_LIST).`,
      );
    }

    const fixture = { errors: [], ...value };

    if (!isValidGraphqlFixture(fixture)) {
      throw new Error(
        `defineFixtureVariants: variant "${key}" for query "${query}" is not a valid GraphQL fixture. ` +
          'Each variant must be an object with "data" (object) and "errors" (array) fields.',
      );
    }

    normalised[key] = fixture;
  }

  if (variantRegistry.has(query)) {
    throw new Error(
      `defineFixtureVariants: variants for query "${query}" are already registered. ` +
        'Each query must be registered exactly once; check for a duplicate or copy-pasted variant file.',
    );
  }

  // Tag the returned object with its query name (non-enumerable so the object
  // still iterates as the pure variants map) so setQueryVariant can resolve the
  // query from the constant a spec passes in.
  Object.defineProperty(normalised, 'query', { value: query });

  const frozen = Object.freeze(normalised);

  variantRegistry.set(query, { variants: frozen, active: 'BASE' });

  return frozen;
}

/**
 * Activates a fixture variant through a query constant, so specs read
 * `setQueryVariant(namespaceWorkItem).archived()` instead of two loose strings.
 *
 * The query constant is the default export of a variant file (the object from
 * defineFixtureVariants). Each returned method activates one variant and is named
 * after its key (ARCHIVED becomes archived()), so an invalid (query, key) pair is
 * unspellable and editor autocomplete lists exactly this query's variants.
 *
 * @param {Object} queryConstant - A variant file's default export.
 * @returns {Object<string, Function>} A map of camelCased variant keys to activators.
 */
export function setQueryVariant(queryConstant) {
  const query = queryConstant?.query;
  const entry = query && variantRegistry.get(query);

  if (!entry) {
    throw new Error(
      'setQueryVariant: expected a query constant from defineFixtureVariants ' +
        '(a variant file default export). Did you pass a variant key string by mistake?',
    );
  }

  const activators = Object.create(null);
  for (const key of Object.keys(entry.variants)) {
    activators[camelCase(key)] = () => activateVariant(query, key);
  }

  return activators;
}

/**
 * Returns a specific named variant for a query, or null if not registered.
 *
 * @param {string} query - The camelCase GraphQL operation name.
 * @param {string} variantKey - The UPPER_SNAKE_CASE variant key.
 * @returns {Object|null}
 */
export function getVariant(query, variantKey) {
  const entry = variantRegistry.get(query);
  if (!entry) return null;
  return entry.variants[variantKey] ?? null;
}

/**
 * Returns the currently active fixture for a given operation name, but only
 * when a test has explicitly called setQueryVariant. Returns null when the
 * query is at its default (BASE) state so the handler can apply its own
 * fallback logic.
 *
 * @param {string} query - The camelCase GraphQL operation name.
 * @returns {Object|null}
 */
export function getActiveVariant(query) {
  const entry = variantRegistry.get(query);
  if (!entry || entry.active === 'BASE') return null;
  return entry.variants[entry.active];
}

/**
 * Resets all registered queries back to their BASE variant.
 * Called automatically in afterEach by test_setup.js.
 */
export function resetAllVariants() {
  for (const entry of variantRegistry.values()) {
    entry.active = 'BASE';
  }
}

/**
 * Returns a keys-only snapshot of every registered query and its variant keys.
 * Read hook for the manifest generator; not used at test time.
 *
 * @returns {Object<string, string[]>} query name -> sorted variant keys
 */
export function dumpRegistry() {
  const out = {};
  for (const [query, entry] of variantRegistry) {
    out[query] = Object.keys(entry.variants).sort();
  }
  return out;
}
