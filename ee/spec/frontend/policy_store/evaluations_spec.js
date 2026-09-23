import { useFakeDate } from 'helpers/fake_date';
import { startOfReportingWindow, toEvaluationsCount } from 'ee/policy_store/evaluations';

describe('startOfReportingWindow', () => {
  useFakeDate(2026, 8, 9, 17, 42);

  // Pinned to UTC midnight so the number does not change as the day passes and
  // the Apollo cache key stays stable across mounts.
  it('starts at UTC midnight six days back, so today counts as the seventh day', () => {
    expect(startOfReportingWindow()).toBe('2026-09-03T00:00:00.000Z');
  });
});

describe('toEvaluationsCount', () => {
  it('reads the total from the connection', () => {
    expect(toEvaluationsCount({ count: 12 })).toBe(12);
  });

  it('counts zero as zero rather than unknown', () => {
    expect(toEvaluationsCount({ count: 0 })).toBe(0);
  });

  it.each([null, undefined, {}])('reads %p as unknown', (connection) => {
    expect(toEvaluationsCount(connection)).toBe(null);
  });
});
