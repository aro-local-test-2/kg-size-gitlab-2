# Testing conventions for `ee/spec/services/ee/search/`

These specs cover search result visibility and confidentiality for the Global Search
group. They are slow, they appear regularly in the Developer Experience slow-test
triage report, and remediation issues are filed against them.

How to respond to one of those issues is documented for the whole suite in
[Report slow-test improvements](../../../../../doc/development/testing_guide/unhealthy_tests.md#report-slow-test-improvements):
a split is a readability change rather than a remediation, the runtime of every
affected file is reported before and after, and a split lists its resulting paths in
the note that closes the issue.

This file keeps only what is specific to this directory.

## Worked example: this directory

This directory is what those conventions exist to prevent. Its files were split
and moved repeatedly, each change reasonable on its own, and no single file in the
set looks alarming today. Across the six triage reports to 2026-09-07 the published
top-30 total stayed flat while this group's share of it grew.

[Issue 628106](https://gitlab.com/gitlab-org/gitlab/-/issues/628106) holds the file
counts, runtimes and per-report figures behind that. They change every week, so this
file does not repeat them.

## Related documentation

- [Unhealthy tests](../../../../../doc/development/testing_guide/unhealthy_tests.md)
  covers flaky and slow tests across the whole suite, including the common patterns
  that make a spec slow.
- [Testing best practices](../../../../../doc/development/testing_guide/best_practices.md)
  has the guidance those patterns link to.
