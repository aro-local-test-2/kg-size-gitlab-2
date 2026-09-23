import { activeDecisions } from 'ee/work_items/components/decision_log/utils';

describe('activeDecisions', () => {
  const resolved = { id: 1, state: 'RESOLVED' };
  const archived = { id: 2, state: 'ARCHIVED' };

  describe('when the log mixes archived and resolved decisions', () => {
    it('keeps only the ones that are not archived', () => {
      expect(activeDecisions([resolved, archived])).toEqual([resolved]);
    });
  });

  describe('when the log is empty', () => {
    it('returns nothing', () => {
      expect(activeDecisions([])).toEqual([]);
    });
  });

  describe('when no decisions are given', () => {
    it('returns nothing', () => {
      expect(activeDecisions()).toEqual([]);
    });
  });
});
