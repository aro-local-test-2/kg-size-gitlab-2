import { useFakeDate } from 'helpers/fake_date';
import { mockResolvers } from 'ee/security_dashboard/graphql/mock_resolvers';

describe('security dashboard MTTR mock resolvers', () => {
  // A range of five full Monday–Sunday weeks; "today" falls inside the last one.
  const startDate = '2022-06-06';
  const endDate = '2022-07-10';
  const today = '2022-07-06';

  const allSeverities = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO', 'UNKNOWN'];
  const allReportTypes = [
    'API_FUZZING',
    'CONTAINER_SCANNING',
    'COVERAGE_FUZZING',
    'DAST',
    'DEPENDENCY_SCANNING',
    'SAST',
    'SECRET_DETECTION',
  ];

  useFakeDate(today);

  const round1 = (value) => Math.round(value * 10) / 10;

  const resolve = (args) => {
    const promise = mockResolvers.SecurityMetrics.mttrOverTime({}, args);
    jest.runAllTimers();
    return promise;
  };

  it('returns one bucket per Monday–Sunday week, capping the final week at today', async () => {
    const buckets = await resolve({ startDate, endDate });

    expect(buckets.map((bucket) => [bucket.startDate, bucket.endDate])).toEqual([
      ['2022-06-06', '2022-06-12'],
      ['2022-06-13', '2022-06-19'],
      ['2022-06-20', '2022-06-26'],
      ['2022-06-27', '2022-07-03'],
      ['2022-07-04', '2022-07-06'],
    ]);
  });

  it('includes every severity and report type in each bucket', async () => {
    const buckets = await resolve({ startDate, endDate });

    buckets.forEach((bucket) => {
      expect(bucket.bySeverity.map((entry) => entry.severity)).toEqual(allSeverities);
      expect(bucket.byReportType.map((entry) => entry.reportType)).toEqual(allReportTypes);
    });
  });

  it('aggregates the top line from the severity breakdown and derives mttr', async () => {
    const [bucket] = await resolve({ startDate, endDate });

    const expectedCount = bucket.bySeverity.reduce((sum, { count }) => sum + count, 0);
    const expectedSumDays = round1(
      bucket.bySeverity.reduce((sum, { sumDays }) => sum + sumDays, 0),
    );

    expect(bucket.count).toBe(expectedCount);
    expect(bucket.sumDays).toBe(expectedSumDays);
    expect(bucket.mttr).toBe(expectedCount ? round1(expectedSumDays / expectedCount) : null);
  });

  it('derives each breakdown mttr from its own sum and count, null when the count is zero', async () => {
    const [bucket] = await resolve({ startDate, endDate });

    [...bucket.bySeverity, ...bucket.byReportType].forEach(({ count, sumDays, mttr }) => {
      expect(mttr).toBe(count ? round1(sumDays / count) : null);
    });
  });

  it('leaves the fourth week without any remediations, so the top line has a gap', async () => {
    const buckets = await resolve({ startDate, endDate });
    const emptyBucket = buckets[3];

    expect(emptyBucket.startDate).toBe('2022-06-27');
    expect(emptyBucket).toMatchObject({ count: 0, sumDays: 0, mttr: null });
    [...emptyBucket.bySeverity, ...emptyBucket.byReportType].forEach((entry) => {
      expect(entry).toMatchObject({ count: 0, sumDays: 0, mttr: null });
    });
  });

  it('restricts the severity breakdown to the requested severities', async () => {
    const [bucket] = await resolve({ startDate, endDate, severity: ['CRITICAL', 'HIGH'] });

    expect(bucket.bySeverity.map((entry) => entry.severity)).toEqual(['CRITICAL', 'HIGH']);
    expect(bucket.count).toBe(bucket.bySeverity.reduce((sum, { count }) => sum + count, 0));
  });
});
