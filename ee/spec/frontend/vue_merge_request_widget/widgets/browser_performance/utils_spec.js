import {
  browserPerformanceStatusIcon,
  browserPerformanceSummary,
  compareBrowserPerformanceMetrics,
} from 'ee/vue_merge_request_widget/widgets/browser_performance/utils';

describe('browser performance utils', () => {
  const report = (metrics) => [{ subject: '/some/path', metrics }];
  const metric = (overrides) => ({ name: 'Total Score', desiredSize: 'larger', ...overrides });

  describe('compareBrowserPerformanceMetrics', () => {
    it.each`
      desiredSize  | headValue | expectedGroup
      ${'larger'}  | ${90}     | ${'improved'}
      ${'larger'}  | ${70}     | ${'degraded'}
      ${'smaller'} | ${70}     | ${'improved'}
      ${'smaller'} | ${90}     | ${'degraded'}
      ${'larger'}  | ${80}     | ${'same'}
    `(
      'groups a $desiredSize metric that moved from 80 to $headValue as $expectedGroup',
      ({ desiredSize, headValue, expectedGroup }) => {
        const compared = compareBrowserPerformanceMetrics(
          report([metric({ desiredSize, value: headValue })]),
          report([metric({ desiredSize, value: 80 })]),
        );

        expect(Object.keys(compared).filter((group) => compared[group].length)).toEqual([
          expectedGroup,
        ]);
      },
    );

    it('drops metrics that the base report does not contain', () => {
      const { improved } = compareBrowserPerformanceMetrics(
        report([metric({ value: 80 }), metric({ name: 'Requests', value: 30 })]),
        report([metric({ value: 70 })]),
      );

      expect(improved.map(({ name }) => name)).toEqual(['Total Score']);
    });

    it.each([undefined, '<html>not json</html>'])('returns empty groups for %p', (data) => {
      expect(compareBrowserPerformanceMetrics(data, data)).toEqual({
        improved: [],
        degraded: [],
        same: [],
      });
    });

    it('formats the row text, rounding a fractional score to two decimals', () => {
      const { degraded } = compareBrowserPerformanceMetrics(
        report([metric({ name: 'Transfer Size (KB)', desiredSize: 'smaller', value: '1070.1' })]),
        report([metric({ name: 'Transfer Size (KB)', desiredSize: 'smaller', value: '1065.1' })]),
      );

      expect(degraded[0].text).toBe(
        'Transfer Size (KB): %{strong_start}1070.09%{strong_end} (5) (+0%) in /some/path',
      );
      expect(degraded[0].icon).toEqual({ name: 'failed' });
    });
  });

  describe('browserPerformanceStatusIcon', () => {
    it.each`
      degraded | same     | expected
      ${['d']} | ${[]}    | ${'warning'}
      ${[]}    | ${['s']} | ${'warning'}
      ${[]}    | ${[]}    | ${'success'}
    `('is $expected for $degraded degraded and $same same', ({ degraded, same, expected }) => {
      expect(browserPerformanceStatusIcon({ degraded, same })).toBe(expected);
    });
  });

  describe('browserPerformanceSummary', () => {
    it('counts every change and breaks the counts down by status', () => {
      expect(browserPerformanceSummary({ improved: ['i'], degraded: ['d'], same: ['s'] })).toEqual({
        title: 'Browser performance test metrics: %{strong_start}3%{strong_end} changes',
        subtitle:
          '%{danger_start}1 degraded%{danger_end}, %{same_start}1 same%{same_end}, and %{success_start}1 improved%{success_end}',
      });
    });
  });
});
