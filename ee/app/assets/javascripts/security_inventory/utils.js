import {
  ALL_SCANNERS_KEY,
  SAST_ADVANCED_KEY,
  CONTAINER_SCANNING_FOR_REGISTRY_KEY,
  SCANNER_POPOVER_GROUPS,
  SECRET_DETECTION_KEY,
  SECRET_DETECTION_PIPELINE_BASED_KEY,
  SECRET_PUSH_PROTECTION_KEY,
  TOGGLEABLE_COLUMNS,
  SECURITY_ATTRIBUTES_COLUMN,
  STATUS_FILTER_KEYS,
  TOOL_STATUS_TO_AGGREGATE_VARIABLES,
} from './constants';

export const toolCoverageFilterVariables = ({ scanner, status } = {}) => {
  if (!status) return {};

  if (scanner === ALL_SCANNERS_KEY) {
    return TOOL_STATUS_TO_AGGREGATE_VARIABLES[status] ?? {};
  }

  return SCANNER_POPOVER_GROUPS[scanner]
    ? { securityAnalyzerFilters: [{ analyzerType: scanner, status }] }
    : {};
};

/**
 * Build the filter-derived query variables shared by every project query. Lives here rather
 * than in the dashboard so the three call sites cannot drift apart.
 * @param {Object} filters - The active search bar filters
 * @param {Object} toolCoverageVariables - Variables from the tool coverage card selection
 * @param {boolean} hasSearch - Whether any filter is active
 * @returns {Object} The query variables the filters and card selection combine to
 */
export const filterQueryVariables = ({
  filters = {},
  toolCoverageVariables = {},
  hasSearch = false,
} = {}) => {
  const {
    search = '',
    securityAnalyzerFilters = [],
    vulnerabilityCountFilters = [],
    attributeFilters = [],
  } = filters;
  const { securityAnalyzerFilters: coverageFilters = [], ...coverageVariables } =
    toolCoverageVariables;

  return {
    search,
    hasSearch,
    securityAnalyzerFilters: [...securityAnalyzerFilters, ...coverageFilters],
    vulnerabilityCountFilters,
    attributeFilters,
    ...Object.fromEntries(STATUS_FILTER_KEYS.map((key) => [key, filters[key] ?? null])),
    ...coverageVariables,
  };
};

export const aggregateAnalyzerStatuses = (analyzerStatuses, analyzerTypes) => {
  if (!analyzerTypes?.length) return {};

  const relevantStatuses = analyzerTypes
    /**
     *  While we're counting the sum of two types 'SAST' and 'SAST_ADVANCED', we encountered a bug and double number of projects were displayed under a group.
     * To fix that, we filter out the 'SAST_ADVANCED' type.
     * After merging https://gitlab.com/gitlab-org/gitlab/-/issues/548276, we need to remove this filter. */
    .filter((type) => type !== SAST_ADVANCED_KEY)
    // Now that container scanning values are backfilled, there's no need to merge them any more
    .filter((type) => type !== CONTAINER_SCANNING_FOR_REGISTRY_KEY)
    // The backend combines the two secret detection types into just SECRET_DETECTION, so
    // filter out one of them and map the other to the right key
    .filter((type) => type !== SECRET_DETECTION_PIPELINE_BASED_KEY)
    .map((type) => (type === SECRET_PUSH_PROTECTION_KEY ? SECRET_DETECTION_KEY : type))
    .map(
      (type) =>
        (analyzerStatuses ?? []).find((scanner) => scanner.analyzerType === type) || {
          analyzerType: type,
        },
    );

  const aggregated = relevantStatuses.reduce(
    (acc, curr) => ({
      failure: (acc.failure || 0) + (curr.failure || 0),
      stale: (acc.stale || 0) + (curr.stale || 0),
      success: (acc.success || 0) + (curr.success || 0),
      notConfigured: (acc.notConfigured || 0) + (curr.notConfigured || 0),
    }),
    {},
  );

  const mostRecentDate = relevantStatuses
    .filter(({ updatedAt }) => updatedAt)
    .sort(
      (currentDate, latestDate) => new Date(latestDate.updatedAt) - new Date(currentDate.updatedAt),
    )[0]?.updatedAt;

  return {
    ...aggregated,
    analyzerType: relevantStatuses[0]?.analyzerType,
    updatedAt: mostRecentDate,
  };
};

/**
 * The toggleable columns the current user is allowed to see. Shared so the display options
 * drawer and the table cannot drift apart, which would leave a column toggleable but never
 * rendered, or rendered with no way to hide it.
 * @param {boolean} canReadAttributes - Whether the user can read security attributes
 * @returns {Array} The toggleable column definitions
 */
export const visibleToggleableColumns = (canReadAttributes) =>
  TOGGLEABLE_COLUMNS.filter((column) => {
    if (column.key === SECURITY_ATTRIBUTES_COLUMN.key) return canReadAttributes;
    return true;
  });

/**
 * Calculate the total number of vulnerabilities across different severities
 * @param {Object} vulnerabilitySeveritiesCount - An object containing the count of vulnerabilities for each severity level
 * @returns {number} The total number of vulnerabilities
 */
export const getVulnerabilityTotal = (vulnerabilitySeveritiesCount = {}) => {
  const {
    critical = 0,
    high = 0,
    medium = 0,
    low = 0,
    info = 0,
    unknown = 0,
  } = vulnerabilitySeveritiesCount || {};

  return critical + high + medium + low + info + unknown;
};

export const isSubGroup = (item) => {
  // eslint-disable-next-line no-underscore-dangle
  return item.__typename === 'Group';
};

/**
 * Validates the structure and types of a security scanner group object
 * @param {Object} value - Object of group security scanner
 * @returns {Boolean} True if all items have valid structure, false otherwise
 */
export const securityScannerOfGroupValidator = (value) => {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }
  const typeChecks = {
    analyzerType: (val) => typeof val === 'string',
    failure: (val) => typeof val === 'number',
    notConfigured: (val) => typeof val === 'number',
    success: (val) => typeof val === 'number',
  };
  const optionalTypeChecks = {
    updatedAt: (val) => val === undefined || typeof val === 'string',
  };
  for (const [key, typeCheck] of Object.entries(typeChecks)) {
    if (!(key in value) || !typeCheck(value[key])) {
      return false;
    }
  }
  for (const [key, typeCheck] of Object.entries(optionalTypeChecks)) {
    if (key in value && !typeCheck(value[key])) {
      return false;
    }
  }
  return true;
};

/**
 * Validates the structure and types of a security scanner project object
 * @param {Array<Object>} value - Array of security scanner objects
 * @returns {Boolean} True if all items have valid structure, false otherwise
 */
export const securityScannerOfProjectValidator = (value) => {
  return value.every(
    (item) =>
      typeof item === 'object' &&
      'analyzerType' in item &&
      typeof item.analyzerType === 'string' &&
      (!('status' in item) || typeof item.status === 'string') &&
      (!('buildId' in item) || item.buildId === null || typeof item.buildId === 'string') &&
      (!('lastCall' in item) || typeof item.lastCall === 'string') &&
      (!('updatedAt' in item) || typeof item.updatedAt === 'string'),
  );
};

/**
 * Validator function for item prop
 * @param {Object} value - Object item of project tool coverage
 * @returns {Boolean} True if all items have valid structure, false otherwise
 */
export const itemValidator = (value) => {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }
  if ('analyzerStatuses' in value) {
    if (
      !Array.isArray(value.analyzerStatuses) ||
      !securityScannerOfProjectValidator(value.analyzerStatuses)
    ) {
      return false;
    }
  }
  if ('path' in value && typeof value.path !== 'string') {
    return false;
  }
  return !('webUrl' in value && typeof value.webUrl !== 'string');
};

/**
 * Checks if recursive breadcrumbs should break and display GlBreadcrumb instead
 * @param {String} currentPath - the fullPath of the group for which breadcrumbs are being rendered
 * @param {String} groupFullPath - the fullPath of the group for which the security inventory is being rendered
 * @param {Object} group - group object as returned by the GroupAvatarAndParentQuery
 * @returns {Boolean} True if we've reached groupFullPath or a group with no parent (or something has gone wrong)
 */
export const hasReachedMainGroup = (currentPath, groupFullPath, group) => {
  // something has gone wrong
  if (!currentPath || !groupFullPath || !group || !currentPath.includes(groupFullPath)) return true;

  // reached groupFullPath or group with no parent
  return currentPath === groupFullPath || !group.parent?.fullPath;
};
