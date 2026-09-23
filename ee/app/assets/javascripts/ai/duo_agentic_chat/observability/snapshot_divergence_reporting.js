import { WorkflowUtils } from '../utils/workflow_utils';
import { captureExceptionForDuoChat } from './sentry_utils';

/**
 * Reconciles a reloaded thread with the pending (on-screen) snapshot — see
 * WorkflowUtils.reconcileLoadedMessages — and reports to Sentry when the
 * reconciliation drops messages the user could already see: pending messages
 * missing from the reconciled log mean the persisted checkpoint diverged from
 * what was streamed, typically a turn the backend never persisted after a
 * failure. Returns the reconciled messages.
 *
 * Only counts and workflow metadata are reported, never message content.
 * Messages without a message_id (optimistic user messages, local error
 * bubbles) are ignored — they never come from a checkpoint, so their absence
 * is not divergence.
 */
export const reconcileAndReportLoadedMessages = ({
  loaded,
  pending = [],
  workflowStatus,
  workflowId,
}) => {
  const reconciled = WorkflowUtils.reconcileLoadedMessages(loaded, pending);

  if (!pending.length) return reconciled;

  const reconciledIds = new Set(reconciled.map((msg) => msg.message_id));
  const droppedCount = pending.filter(
    (msg) => msg.message_id && !reconciledIds.has(msg.message_id),
  ).length;

  if (!droppedCount) return reconciled;

  // Sentry title, read by engineers and never by a user, so deliberately not translated.
  // eslint-disable-next-line @gitlab/require-i18n-strings
  captureExceptionForDuoChat(new Error('Duo Chat snapshot diverged from persisted checkpoint'), {
    tags: { duo_chat_snapshot_divergence: workflowStatus ?? 'unknown' },
    extra: {
      droppedCount,
      pendingCount: pending.length,
      reconciledCount: reconciled.length,
      workflowStatus: workflowStatus ?? null,
      workflowId: workflowId ?? null,
    },
  });

  return reconciled;
};
