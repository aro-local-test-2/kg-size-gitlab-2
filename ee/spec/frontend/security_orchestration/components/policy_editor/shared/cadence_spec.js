import {
  MAX_DAY_OF_MONTH,
  getMonthlyDayOptions,
} from 'ee/security_orchestration/components/policy_editor/shared/cadence';

describe('getMonthlyDayOptions', () => {
  const options = getMonthlyDayOptions();

  it('offers every day of the longest month', () => {
    expect(options).toHaveLength(MAX_DAY_OF_MONTH);
    expect(options.at(0)).toEqual({ value: 1, text: 1 });
    expect(options.at(-1)).toEqual({ value: MAX_DAY_OF_MONTH, text: MAX_DAY_OF_MONTH });
  });

  // The listbox emits `value` straight into the day-of-month cron field, so a
  // string here would round-trip as a different type than parseCronTime returns.
  it('numbers the values so they round-trip through the cron field', () => {
    expect(options.every(({ value }) => typeof value === 'number')).toBe(true);
  });
});
