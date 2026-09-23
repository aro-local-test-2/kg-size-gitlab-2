export const WINDOW_DAYS = 7;

/**
 * Start of the reporting window the evaluation stats cover.
 *
 * The window is WINDOW_DAYS calendar days in UTC, inclusive of today, so the
 * boundary is UTC midnight (WINDOW_DAYS - 1) days back and today counts as a
 * partial day.
 *
 * The boundary is pinned to UTC midnight rather than the current instant so
 * everyone reading the same organization on the same day sees the same number,
 * and so the value is a stable Apollo cache key instead of a fresh one on
 * every mount.
 *
 * @returns {String} ISO 8601 timestamp
 */
export const startOfReportingWindow = () => {
  const start = new Date();

  start.setUTCHours(0, 0, 0, 0);
  start.setUTCDate(start.getUTCDate() - (WINDOW_DAYS - 1));

  return start.toISOString();
};

/**
 * Reads the total from a `policyEvaluations` connection.
 *
 * A null connection is a group or a viewer who cannot read the organization's
 * policies. That is not a zero, so it reads as unknown and the caller renders
 * a placeholder rather than a number nobody verified.
 *
 * @param {Object|null} connection
 * @returns {Number|null}
 */
export const toEvaluationsCount = (connection) => connection?.count ?? null;
