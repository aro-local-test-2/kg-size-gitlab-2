import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import {
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
  VISIBILITY_LEVEL_PUBLIC,
  VISIBILITY_LEVEL_RESTRICTED,
  VISIBILITY_LEVEL_PRIVATE,
} from './constants';

/**
 * Checks whether an AI Catalog item is enabled at the group level.
 *
 * @param {Object} item - The AI Catalog item
 * @returns {Boolean}
 */
export const isAiCatalogItemEnabledInGroup = (item) => {
  return Boolean(item?.configurationForGroup?.enabled);
};

/**
 * Checks whether an AI Catalog item is enabled at the project level.
 *
 * @param {Object} item - The AI Catalog item
 * @returns {Boolean}
 */
export const isAiCatalogItemEnabledInProject = (item) => {
  return Boolean(item?.configurationForProject?.enabled);
};

/**
 * Checks whether an AI Catalog item is enabled in the project that manages it
 * (the owning project of a private item).
 *
 * Backed by the `isEnabledInManagedByProject` GraphQL field, which is resolved
 * server-side against the item's owning project and is available regardless of
 * the current namespace context (Explore, project, group).
 *
 * @param {Object} item - The AI Catalog item
 * @returns {Boolean}
 */
export const isAiCatalogItemEnabledInManagedByProject = (item) => {
  return Boolean(item?.isEnabledInManagedByProject);
};

/**
 * Checks whether an AI Catalog item is currently enabled in the active namespace.
 *
 * For private items, "enabled" is determined by the single owning project via
 * `isEnabledInManagedByProject`, since a private item can only ever be enabled
 * in that one project. This works in any namespace context (Explore, project,
 * group) without needing a `projectId` query variable.
 *
 * For restricted items, enabled state is scoped to the current namespace just
 * like public items, since a restricted item can be enabled across any project
 * within the same top-level group.
 *
 * For public items, falls back to the namespace-scoped configuration field.
 *
 * @param {Object} item - The AI Catalog item
 * @param {Object} options
 * @param {Boolean} options.isProjectNamespace - Whether viewing from a project page
 * @returns {Boolean}
 */
export const isAiCatalogItemEnabled = (item, options = {}) => {
  const { isProjectNamespace = false } = options;

  if (item && item.visibility === VISIBILITY_LEVEL_PRIVATE) {
    return isAiCatalogItemEnabledInManagedByProject(item);
  }

  return isProjectNamespace
    ? isAiCatalogItemEnabledInProject(item)
    : isAiCatalogItemEnabledInGroup(item);
};

/**
 * Checks whether the "Enable from global" action should be shown.
 * Shown on the explore page when the item is not foundational (unless it is
 * a third-party flow, which is always showable).
 *
 * Login state is intentionally not considered here — the button is still
 * rendered when logged out so it can show a "Log in to enable" tooltip.
 *
 * @param {Object} item - The AI Catalog item
 * @param {Object} options
 * @param {Boolean} options.isGlobalNamespace - Whether viewing from the explore page
 * @returns {Boolean}
 */
export const showEnableFromGlobalAction = (item, options = {}) => {
  const { isGlobalNamespace = false } = options;
  return (
    isGlobalNamespace &&
    (!item?.foundational || item?.itemType === AI_CATALOG_TYPE_THIRD_PARTY_FLOW)
  );
};

/**
 * Returns the numeric ID of an AI Catalog item's owning project.
 *
 * @param {Object} item - The AI Catalog item
 * @returns {Number|null}
 */
export const getAiCatalogItemOwningProjectId = (item) => {
  const projectGid = item?.project?.id;
  return projectGid ? getIdFromGraphQLId(projectGid) : null;
};

/**
 * Returns the `nameWithNamespace` of the AI Catalog item's owning project.
 *
 * @param {Object} item - The AI Catalog item
 * @returns {String|null}
 */
export const getAiCatalogItemOwningProjectName = (item) => {
  return item?.project?.nameWithNamespace ?? null;
};

/**
 * Whether a private AI Catalog item is being viewed from a project other
 * than its owning project. Only gates project namespaces.
 *
 * Public items, restricted items, and items with a missing owning project id
 * return false. Restricted items can be enabled from any project in the same
 * top-level group, so the owning-project constraint does not apply to them.
 *
 * @param {Object} item - The AI Catalog item
 * @param {Object} options
 * @param {Boolean} options.isProjectNamespace - Viewing from a project page
 * @param {String|Number} options.projectId - Current project id (numeric)
 * @returns {Boolean}
 */
export const isAiCatalogItemOutsideOwningProject = (item, options = {}) => {
  const { isProjectNamespace = false, projectId = null } = options;

  if (item?.visibility === VISIBILITY_LEVEL_PUBLIC) return false;
  if (item?.visibility === VISIBILITY_LEVEL_RESTRICTED) return false;
  if (!isProjectNamespace) return false;

  const owningProjectId = getAiCatalogItemOwningProjectId(item);
  if (!owningProjectId) return false;

  return Number(projectId) !== Number(owningProjectId);
};
