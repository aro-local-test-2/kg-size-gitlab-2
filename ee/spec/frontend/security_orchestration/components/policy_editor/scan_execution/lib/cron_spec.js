import {
  setCronTime,
  parseCronTime,
  getCronPeriod,
  isCronWeekly,
  isCronMonthly,
  isCronRuleModeSupported,
  DAYS,
  HOUR_MINUTE_LIST,
} from 'ee/security_orchestration/components/policy_editor/scan_execution/lib';

describe('Cron time', () => {
  describe('setCronTime', () => {
    it.each`
      params                                   | expectedResult
      ${{ time: 0 }}                           | ${'0 0 * * *'}
      ${{ time: 6 }}                           | ${'0 6 * * *'}
      ${{ time: 1, day: 1 }}                   | ${'0 1 * * 1'}
      ${{ time: 6, day: 6 }}                   | ${'0 6 * * 6'}
      ${{ time: 0, day: 0 }}                   | ${'0 0 * * 0'}
      ${{ time: 9, daysOfMonth: [1] }}         | ${'0 9 1 * *'}
      ${{ time: 0, daysOfMonth: [15, 1] }}     | ${'0 0 1,15 * *'}
      ${{ time: 0, daysOfMonth: [] }}          | ${'0 0 * * *'}
      ${{ time: 0, day: 3, daysOfMonth: [4] }} | ${'0 0 4 * *'}
      ${{ time: 0, daysOfMonth: [1, 1, 15] }}  | ${'0 0 1,15 * *'}
    `('builds cron string $expectedResult', ({ params, expectedResult }) => {
      expect(setCronTime(params)).toBe(expectedResult);
    });
  });

  describe('parseCronTime', () => {
    it.each`
      cronString        | expectedResult
      ${'0 0 * * *'}    | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[0], timeIndex: '0', daysOfMonth: [] }}
      ${'0 1 * * 4'}    | ${{ day: DAYS[4], dayIndex: '4', time: HOUR_MINUTE_LIST[1], timeIndex: '1', daysOfMonth: [] }}
      ${'0 9 1,15 * *'} | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[9], timeIndex: '9', daysOfMonth: [1, 15] }}
      ${'0 a * * *'}    | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[0], timeIndex: '0', daysOfMonth: [] }}
      ${'0 25 * * *'}   | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[0], timeIndex: '0', daysOfMonth: [] }}
      ${'0 07 * * *'}   | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[7], timeIndex: '7', daysOfMonth: [] }}
      ${'0  18 * * *'}  | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[18], timeIndex: '18', daysOfMonth: [] }}
      ${'0 0 * * 04'}   | ${{ day: DAYS[4], dayIndex: '4', time: HOUR_MINUTE_LIST[0], timeIndex: '0', daysOfMonth: [] }}
      ${'0 9 15,1 * *'} | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[9], timeIndex: '9', daysOfMonth: [1, 15] }}
      ${'0 9 1,1 * *'}  | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[9], timeIndex: '9', daysOfMonth: [1] }}
      ${''}             | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[0], timeIndex: '0', daysOfMonth: [] }}
      ${null}           | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[0], timeIndex: '0', daysOfMonth: [] }}
      ${undefined}      | ${{ day: DAYS[0], dayIndex: '0', time: HOUR_MINUTE_LIST[0], timeIndex: '0', daysOfMonth: [] }}
    `('parses $cronString correctly', ({ cronString, expectedResult }) => {
      expect(parseCronTime(cronString)).toEqual(expectedResult);
    });

    it('round-trips a monthly cron built with setCronTime', () => {
      const cron = setCronTime({ time: 9, daysOfMonth: [3, 10, 17] });
      expect(parseCronTime(cron).daysOfMonth).toEqual([3, 10, 17]);
    });
  });

  describe('period detection', () => {
    it.each`
      cronString        | period       | weekly   | monthly
      ${'0 0 * * *'}    | ${'daily'}   | ${false} | ${false}
      ${'0 0 * * 0'}    | ${'weekly'}  | ${true}  | ${false}
      ${'0 0 * * 04'}   | ${'weekly'}  | ${true}  | ${false}
      ${'0 0 * * 7'}    | ${'daily'}   | ${false} | ${false}
      ${'0 0 1 * *'}    | ${'monthly'} | ${false} | ${true}
      ${'0 0 1,15 * *'} | ${'monthly'} | ${false} | ${true}
      ${'0 0 * * 1-5'}  | ${'daily'}   | ${false} | ${false}
      ${''}             | ${'daily'}   | ${false} | ${false}
      ${null}           | ${'daily'}   | ${false} | ${false}
      ${undefined}      | ${'daily'}   | ${false} | ${false}
    `('classifies $cronString as $period', ({ cronString, period, weekly, monthly }) => {
      expect(getCronPeriod(cronString)).toBe(period);
      expect(isCronWeekly(cronString)).toBe(weekly);
      expect(isCronMonthly(cronString)).toBe(monthly);
    });
  });

  describe('isCronRuleModeSupported', () => {
    it.each`
      cronString           | supported
      ${'0 0 * * *'}       | ${true}
      ${'0 18 * * *'}      | ${true}
      ${'0 0 * * 0'}       | ${true}
      ${'0 9 1 * *'}       | ${true}
      ${'0 9 1,15,31 * *'} | ${true}
      ${'30 9 * * *'}      | ${false}
      ${'0 9-17 * * *'}    | ${false}
      ${'0 0 1-5 * *'}     | ${false}
      ${'0 0 */2 * *'}     | ${false}
      ${'0 0 L * *'}       | ${false}
      ${'0 0 1 6 *'}       | ${false}
      ${'0 0 * * 1-5'}     | ${false}
      ${'0 0 1 * * *'}     | ${false}
      ${'0 25 * * *'}      | ${false}
      ${'0 0 0 * *'}       | ${false}
      ${'0 0 32 * *'}      | ${false}
      ${'0  18 * * *'}     | ${true}
      ${'0 18 * * * '}     | ${true}
      ${'00 18 * * *'}     | ${true}
      ${'0 0 * * 04'}      | ${true}
      ${'0 0 * * 7'}       | ${false}
      ${''}                | ${false}
      ${null}              | ${false}
    `('returns $supported for $cronString', ({ cronString, supported }) => {
      expect(isCronRuleModeSupported(cronString)).toBe(supported);
    });
  });
});
