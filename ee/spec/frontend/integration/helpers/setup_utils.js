import currentUserFixture from 'test_fixtures/graphql/work_items/integration/current_user.query.graphql.json';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';

export { setQueryVariant, activateVariant } from '../core/fixture_variant_schema';

// The signed-in user id, read from the fixture the RSpec generator signs in as.
// Deriving it (rather than hard-coding a value) keeps the session aligned with the
// fixtures even when DB id allocation shifts between fixture-generation runs.
const CURRENT_USER_ID = getIdFromGraphQLId(currentUserFixture.data.currentUser.id);

/**
 * Resets the router to its base path so each test starts from a known route.
 * Skips the push when already at base (with or without a leading slash),
 * since Vue Router rejects a redundant navigation to the current route.
 * @param {Object} router - A Vue Router instance
 * @returns {Promise<void>}
 */
export async function setupRouter(router) {
  const { path } = router.currentRoute;
  const { base } = router.history;
  if (path && path !== base && path !== `/${base}`) {
    await router.push(base);
  }
}

/**
 * Sets or clears `window.gon.current_user_id`, which `isLoggedIn()` reads.
 * The id is derived from the current_user fixture so it always matches the user
 * the fixtures were generated as, regardless of DB id allocation. Call before
 * mounting; `window.gon` is not reactive.
 * @param {boolean} flag - Whether the user should be logged in
 */
export function setUserSession(flag) {
  window.gon = { ...window.gon, current_user_id: flag ? CURRENT_USER_ID : null };
}
