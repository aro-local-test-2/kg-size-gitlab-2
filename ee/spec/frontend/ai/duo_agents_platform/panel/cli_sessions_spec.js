import { isCliSession, isIdleCliSession } from 'ee/ai/duo_agents_platform/panel/cli_sessions';

describe('isCliSession', () => {
  it.each`
    reason                                     | session                                               | expected
    ${'sourceType is CLI'}                     | ${{ sourceType: 'CLI', flowMetadataVersion: null }}   | ${true}
    ${'flow version is 2.0.0-interactive'}     | ${{ flowMetadataVersion: '2.0.0-interactive' }}       | ${true}
    ${'flow version is 2.1.0-interactive'}     | ${{ flowMetadataVersion: '2.1.0-interactive' }}       | ${true}
    ${'the CLI /goal flow is not interactive'} | ${{ flowMetadataVersion: '2.0.0-goal' }}              | ${false}
    ${'flow metadata is null (pre-19.3 row)'}  | ${{ flowMetadataVersion: null }}                      | ${false}
    ${'flow metadata is undefined'}            | ${{ flowMetadataVersion: undefined }}                 | ${false}
    ${'flow version is unrelated'}             | ${{ flowMetadataVersion: '3.0.0' }}                   | ${false}
    ${'sourceType is not CLI'}                 | ${{ sourceType: 'SLACK', flowMetadataVersion: null }} | ${false}
  `('returns $expected when $reason', ({ session, expected }) => {
    expect(isCliSession(session)).toBe(expected);
  });
});

describe('isIdleCliSession', () => {
  describe('when the session is a CLI session', () => {
    let session;

    beforeEach(() => {
      session = { flowMetadataVersion: '2.1.0-interactive' };
    });

    it.each`
      status                           | expected
      ${'INPUT_REQUIRED'}              | ${true}
      ${'FAILED'}                      | ${false}
      ${'FINISHED'}                    | ${false}
      ${'RUNNING'}                     | ${false}
      ${'PLAN_APPROVAL_REQUIRED'}      | ${false}
      ${'TOOL_CALL_APPROVAL_REQUIRED'} | ${false}
    `('returns $expected for status $status', ({ status, expected }) => {
      expect(isIdleCliSession({ ...session, status })).toBe(expected);
    });
  });

  describe('when the session is not a CLI session', () => {
    let session;

    beforeEach(() => {
      session = { flowMetadataVersion: '2.0.0' };
    });

    it('returns false even in INPUT_REQUIRED', () => {
      expect(isIdleCliSession({ ...session, status: 'INPUT_REQUIRED' })).toBe(false);
    });
  });
});
