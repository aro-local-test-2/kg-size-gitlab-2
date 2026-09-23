// Interim, frontend-only CLI session detection for
// https://gitlab.com/gitlab-org/gitlab/-/work_items/627777. Delete this module
// once https://gitlab.com/gitlab-org/gitlab/-/work_items/627798 ships a real
// `source_type: cli` and the CLI sends it
// (https://gitlab.com/gitlab-org/editor-extensions/gitlab-lsp/-/issues/2836).
export const CLI_FLOW_VERSION_SUFFIX = '-interactive';

const INPUT_REQUIRED = 'INPUT_REQUIRED';

// `-goal` (the CLI `/goal` command) is deliberately excluded: it runs a
// non-interactive implement/verify loop, so its INPUT_REQUIRED isn't the
// "user exited the CLI" case this heuristic targets.
export const isCliSession = (session) =>
  session?.sourceType === 'CLI' ||
  Boolean(session?.flowMetadataVersion?.endsWith(CLI_FLOW_VERSION_SUFFIX));

// Only INPUT_REQUIRED is misleading for a CLI session (the user closed the
// terminal). Failed, finished and approval-pending CLI sessions keep their
// real status.
export const isIdleCliSession = (session) =>
  session?.status === INPUT_REQUIRED && isCliSession(session);
