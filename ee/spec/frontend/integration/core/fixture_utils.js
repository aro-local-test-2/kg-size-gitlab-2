import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { camelCase, cloneDeep, set } from 'lodash-es';
import { captureMissingOperation } from './operation_helpers';

/**
 * Finds the fixture in `table` whose `matches` predicate accepts `variables`.
 *
 * @param {Object} variables - GraphQL variables from the intercepted MSW request.
 * @param {Array<{matches: Function}>} table - Fixture candidates to search.
 * @param {Object} options
 * @param {Function} options.guard - Returns true if `variables` carries a filter this
 *   table is responsible for; gates whether a non-match is an error.
 * @param {string} options.label - Fixture table name, used only in the error message.
 * @returns {*|undefined} The matching fixture, or `undefined` when no filter applies.
 */
export function matchFixture(variables, table, { guard, label }) {
  const match = table.find((candidate) => candidate.matches(variables));

  if (!match && guard(variables)) {
    const message = `No ${label} fixture matches ${JSON.stringify(
      variables,
    )}. Add one to the ${label} fixture table.`;

    captureMissingOperation(message);

    throw new Error(message);
  }

  return match;
}

export function loadFixturesMap(basePath) {
  const files = readdirSync(basePath).filter((f) => f.endsWith('.json'));
  const map = {};

  files.forEach((file) => {
    const operationName = camelCase(
      file.replace(/\.(query|mutation)\.graphql\.json$/, '').replace(/\.json$/, ''),
    );
    const content = JSON.parse(readFileSync(join(basePath, file), 'utf-8'));
    // Only GraphQL responses (objects with a `data` key) get a normalised `errors: []`.
    // The map also holds raw REST payloads (e.g. arrays), which must be left untouched.
    const isGraphqlResponse =
      content && typeof content === 'object' && !Array.isArray(content) && 'data' in content;
    map[operationName] = isGraphqlResponse ? { errors: [], ...content } : content;
  });

  return map;
}

export function isValidGraphqlFixture(fixture) {
  const isObject = fixture && typeof fixture === 'object';
  const hasData = isObject && 'data' in fixture;
  const isValidData = hasData && typeof fixture.data === 'object' && fixture.data !== null;
  const isValidErrors = !('errors' in fixture) || Array.isArray(fixture.errors);
  return isObject && hasData && isValidData && isValidErrors;
}

function generateGraphqlId(id, offset) {
  const match = String(id).match(/^(.*\/)(\d+)$/);
  if (!match) {
    throw new Error(`Cannot synthesize a new id from "${id}": expected a "prefix/number" format`);
  }
  const [, prefix, numericPart] = match;
  return `${prefix}${Number(numericPart) + offset}`;
}

function resizeNodes(nodes, itemCount) {
  if (itemCount <= nodes.length) {
    return nodes.slice(0, itemCount);
  }

  const template = nodes[nodes.length - 1];
  const filled = Array.from({ length: itemCount - nodes.length }, (_, index) => {
    const clone = cloneDeep(template);
    clone.id = generateGraphqlId(template.id, index + 1);
    return clone;
  });

  return [...nodes, ...filled];
}

// Main consumers are below

/**
 * Sets the `errors` field of a fixture to an array of error messages and clears the `data` field.
 *
 * @param {Object} fixture - The fixture object to modify.
 * @param {string[]} errors - An array of error messages to set in the fixture.
 * @throws {Error} If `errors` is not an array of strings.
 */

export function setFixtureErrors(fixture, errors) {
  if (!isValidGraphqlFixture(fixture)) {
    throw new Error('Invalid GraphQL fixture: must be an object with "data" and "errors" fields');
  }

  if (!errors || !Array.isArray(errors) || errors.some((e) => typeof e !== 'string')) {
    throw new Error('Errors must be an array of error messages');
  }

  const clone = cloneDeep(fixture);
  Object.assign(clone, {
    errors: errors.map((message) => ({ message })),
    data: {},
  });

  return clone;
}

/**
 * Sets the value of a property in the fixture's data.
 *
 * The selector is either a key name or an options object with a `path`. A key
 * name updates the first matching key in a depth-first walk, which cannot
 * disambiguate a key that occurs more than once (e.g. an `awardEmoji` connection
 * vs an `awardEmoji` permission). For those, pass `{ path }` with a lodash path
 * relative to `fixture.data` to target one node exactly.
 *
 * @param {Object} fixture - The fixture object to modify.
 * @param {string|{path: string}} selector - A key name, or `{ path }` for an exact
 *   lodash path relative to `fixture.data`.
 * @param {*} data - The value to set for the property.
 * @throws {Error} If `selector` is not a non-empty string or a `{ path }` object.
 */
export function setFixtureData(fixture, selector, data) {
  if (!isValidGraphqlFixture(fixture)) {
    throw new Error('Invalid GraphQL fixture: must be an object with "data" and "errors" fields');
  }

  const path = typeof selector === 'object' && selector !== null ? selector.path : null;
  const lookupKey = typeof selector === 'string' ? selector : null;

  if (!path && !lookupKey) {
    throw new Error('Selector must be a non-empty key name or an object with a "path"');
  }

  const clone = cloneDeep(fixture);
  let found = false;

  if (path) {
    set(clone.data, path, data);
    return clone;
  }

  function updateData(obj) {
    if (obj && typeof obj === 'object') {
      if (lookupKey in obj) {
        // eslint-disable-next-line no-param-reassign
        obj[lookupKey] = data;
        found = true;
      } else {
        Object.values(obj).forEach(updateData);
      }
    }
  }

  updateData(clone.data);

  if (!found) {
    throw new Error(
      `Property "${lookupKey}" was not found in the fixture data; check the key for typos`,
    );
  }

  return clone;
}

/**
 * Sets the count of items in a fixture's connection.
 *
 * When the connection exposes a scalar count field (e.g. `count`), it is kept in
 * sync with `itemCount`. Count-only queries have no `nodes`, so the field is set
 * directly without resizing.
 *
 * @param {Object} param0 - The parameters for updating the item count.
 * @param {Object} param0.fixture - The fixture object to modify.
 * @param {string} param0.lookupKey - The key of the connection to update.
 * @param {number} param0.itemCount - The desired count of items in the connection.
 * @param {string} [param0.countKey='count'] - The name of the scalar count field, if any.
 * @throws {Error} If any parameter is invalid.
 */
export function setFixtureItemsCount({ fixture, lookupKey, itemCount, countKey = 'count' } = {}) {
  if (!isValidGraphqlFixture(fixture)) {
    throw new Error('Invalid GraphQL fixture: must be an object with "data" and "errors" fields');
  }

  if (!lookupKey || typeof lookupKey !== 'string') {
    throw new Error('Property name must be a non-empty string');
  }

  if (lookupKey === 'nodes') {
    throw new Error(
      'Property name must be the connection key (e.g. "workItems"), not "nodes"; its first "nodes" child is resized',
    );
  }

  if (typeof itemCount !== 'number' || itemCount < 0) {
    throw new Error('Item count must be a non-negative number');
  }

  const clone = cloneDeep(fixture);

  function updateItemsCount(obj) {
    if (obj && typeof obj === 'object') {
      if (lookupKey in obj) {
        const connection = obj[lookupKey];
        const hasNodes =
          connection && typeof connection === 'object' && Array.isArray(connection.nodes);
        const hasCount = connection && typeof connection === 'object' && countKey in connection;

        if (!hasNodes && !hasCount) {
          throw new Error(
            `Property "${lookupKey}" must be a connection with a "nodes" array or a "${countKey}" field and cannot be resized`,
          );
        }

        if (hasNodes) {
          if (connection.nodes.length === 0 && itemCount > 0) {
            throw new Error(
              `Property "${lookupKey}.nodes" is empty; cannot synthesize items without a template`,
            );
          }

          connection.nodes = resizeNodes(connection.nodes, itemCount);
        }

        if (hasCount) {
          connection[countKey] = itemCount;
        }
      } else {
        Object.values(obj).forEach(updateItemsCount);
      }
    }
  }

  updateItemsCount(clone);

  return clone;
}
