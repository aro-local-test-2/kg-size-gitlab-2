import { DECISION_STATE_ARCHIVED } from './constants';

/**
 * The decisions that have been archived.
 *
 * @param {Array<Object>} decisions Decisions from the decision log query.
 * @returns {Array<Object>} The decisions whose state is archived.
 */
export const getArchivedDecisions = (decisions = []) =>
  decisions.filter((decision) => decision.state === DECISION_STATE_ARCHIVED);

/**
 * The decisions a work item currently stands on.
 *
 * An archived decision stays on the record, but it no longer counts as something the work item has
 * settled. The header button, the panel heading and the list all read the same set, so a reader
 * never sees a count that disagrees with what is on screen.
 *
 * Non-archived decisions are always active, regardless of any other status they may carry in the
 * future. Deriving active from "not archived" is therefore more robust than the inverse.
 *
 * @param {Array<Object>} decisions Decisions from the decision log query.
 * @returns {Array<Object>} The decisions that are not archived.
 */
export const activeDecisions = (decisions = []) =>
  decisions.filter((decision) => decision.state !== DECISION_STATE_ARCHIVED);

/**
 * The options a decision settled on. Only a selected option counts as settled.
 *
 * @param {Object} decision A decision from the decision log query.
 * @returns {Array<Object>} The settled options, in the order they were fetched.
 */
export const settledDecisionOptions = (decision) =>
  (decision?.options?.nodes || []).filter((option) => option.selected);

/**
 * The decision itself, as the card heads it.
 *
 * The text lives on the settled option. A record with no settled option should not exist, because
 * a decision is only logged once an option is chosen, so the title stands in for it.
 *
 * @param {Object} decision A decision from the decision log query.
 * @returns {string} The decision text, or an empty string when there is none.
 */
export const decisionText = (decision) =>
  settledDecisionOptions(decision)[0]?.content || decision?.title || '';

/**
 * The one link a decision points at.
 *
 * A decision recorded by hand carries the link its author gave. One resolved from a thread carries
 * the comment that settled it, which the author cannot change.
 *
 * @param {Object} decision A decision from the decision log query.
 * @returns {string} The link, or an empty string when there is none.
 */
export const decisionSourceUrl = (decision) => decision?.sourceLink || decision?.noteUrl || '';
