import {
  saveSessionsQueryVariables,
  getSessionsQueryVariables,
} from 'ee/ai/duo_agents_platform/utils/sessions_query_state';

describe('sessions_query_state', () => {
  const variables = {
    sort: 'CREATED_ASC',
    pagination: { first: 20, after: 'cursor', before: null, last: null },
    filters: { statusGroup: 'ACTIVE' },
  };

  it('returns null for an unknown key', () => {
    expect(getSessionsQueryVariables('unknown/project')).toBeNull();
  });

  it('returns the saved variables for the matching key', () => {
    saveSessionsQueryVariables('saved/project', variables);

    expect(getSessionsQueryVariables('saved/project')).toEqual(variables);
  });

  it('overwrites previously saved variables for the same key', () => {
    const updated = { sort: 'UPDATED_DESC', pagination: {}, filters: {} };

    saveSessionsQueryVariables('overwritten/project', variables);
    saveSessionsQueryVariables('overwritten/project', updated);

    expect(getSessionsQueryVariables('overwritten/project')).toEqual(updated);
  });

  it('keeps keys independent of each other', () => {
    const other = { sort: 'UPDATED_DESC', pagination: {}, filters: {} };

    saveSessionsQueryVariables('independent/a', variables);
    saveSessionsQueryVariables('independent/b', other);

    expect(getSessionsQueryVariables('independent/a')).toEqual(variables);
    expect(getSessionsQueryVariables('independent/b')).toEqual(other);
  });
});
