import {
  availableDateRangeOptions,
  initialDateRangeOption,
} from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/shared/components/utils';

const option = (value, startDate, endDate) => ({ value, startDate, endDate });

const THIS_MONTH = option('this_month', '2026-04-01', '2026-04-30');
const LAST_MONTH = option('last_month', '2026-03-01', '2026-03-31');
const LAST_7_DAYS = option('last_7_days', '2026-03-25', '2026-04-01');
const CUSTOM = { value: 'custom' };

const OPTIONS = [THIS_MONTH, LAST_MONTH, LAST_7_DAYS, CUSTOM];

describe('availableDateRangeOptions', () => {
  describe('when there is no subscription start date', () => {
    it('returns the options unchanged', () => {
      expect(availableDateRangeOptions(OPTIONS, null)).toBe(OPTIONS);
    });
  });

  describe('when the subscription started before every option', () => {
    it('returns the options unchanged', () => {
      expect(availableDateRangeOptions(OPTIONS, '2026-01-01')).toEqual(OPTIONS);
    });
  });

  describe('when the subscription started mid-range', () => {
    const result = () => availableDateRangeOptions(OPTIONS, '2026-04-01');

    it('clamps the start date of ranges that begin earlier', () => {
      expect(result()).toContainEqual(option('last_7_days', '2026-04-01', '2026-04-01'));
    });

    it('drops ranges that end before the subscription started', () => {
      expect(result().map(({ value }) => value)).not.toContain('last_month');
    });

    it('keeps ranges that start after the subscription started', () => {
      expect(result()).toContainEqual(THIS_MONTH);
    });

    it('keeps the custom option, which has no fixed dates', () => {
      expect(result()).toContainEqual(CUSTOM);
    });
  });

  describe('when the subscription started on an option boundary', () => {
    it('keeps a range ending exactly on the subscription start date', () => {
      const result = availableDateRangeOptions([LAST_MONTH], '2026-03-31');

      expect(result).toEqual([option('last_month', '2026-03-31', '2026-03-31')]);
    });

    it('does not clamp a range starting exactly on the subscription start date', () => {
      expect(availableDateRangeOptions([THIS_MONTH], '2026-04-01')).toEqual([THIS_MONTH]);
    });
  });

  describe('when the subscription starts after every option', () => {
    it('returns only options without fixed dates', () => {
      expect(availableDateRangeOptions(OPTIONS, '2027-01-01')).toEqual([CUSTOM]);
    });
  });

  it('does not mutate the given options', () => {
    availableDateRangeOptions(OPTIONS, '2026-04-01');

    expect(LAST_7_DAYS.startDate).toBe('2026-03-25');
  });
});

describe('initialDateRangeOption', () => {
  it('returns the option unchanged when there is no subscription start date', () => {
    expect(initialDateRangeOption(THIS_MONTH, null)).toEqual(THIS_MONTH);
  });

  it('clamps the start date to the subscription start date', () => {
    expect(initialDateRangeOption(LAST_7_DAYS, '2026-03-28')).toEqual(
      option('last_7_days', '2026-03-28', '2026-04-01'),
    );
  });

  it('falls back to the option when the subscription starts after it ends', () => {
    expect(initialDateRangeOption(THIS_MONTH, '2027-01-01')).toEqual(THIS_MONTH);
  });
});
