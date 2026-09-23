import { formatSettingsErrorMessage } from 'ee/ai/settings/utils';

const defaultMessage =
  'An error occurred while saving your settings. Reload the page to try again.';

describe('formatSettingsErrorMessage', () => {
  it.each`
    scenario                            | error
    ${'error has no response'}          | ${new Error('Network Error')}
    ${'error is undefined'}             | ${undefined}
    ${'message is a number'}            | ${{ response: { data: { message: 42 } } }}
    ${'message is an empty array'}      | ${{ response: { data: { message: [] } } }}
    ${'message is an array'}            | ${{ response: { data: { message: ['some', 'array'] } } }}
    ${'message is null'}                | ${{ response: { data: { message: null } } }}
    ${'message is an empty string'}     | ${{ response: { data: { message: '' } } }}
    ${'message is a plain string'}      | ${{ response: { data: { message: 'a plain string' } } }}
    ${'field hash has no known labels'} | ${{ response: { data: { message: { some_internal_only_attribute: ['is invalid'] } } } }}
    ${'field hash has no messages'}     | ${{ response: { data: { message: { lock_duo_custom_agents_enabled: [] } } } }}
  `('returns the default message when $scenario', ({ error }) => {
    expect(formatSettingsErrorMessage(error, defaultMessage)).toBe(defaultMessage);
  });

  it('appends a single labelled field, stripped of the namespace_settings prefix', () => {
    const error = {
      response: {
        data: {
          message: {
            'namespace_settings.lock_duo_external_agents_enabled': [
              'cannot be changed because it is locked by an ancestor',
            ],
          },
        },
      },
    };

    expect(formatSettingsErrorMessage(error, defaultMessage)).toBe(
      `${defaultMessage} Allow external agents cannot be changed because it is locked by an ` +
        'ancestor',
    );
  });

  it('matches a label on the raw attribute when there is no namespace_settings prefix', () => {
    const error = {
      response: {
        data: {
          message: {
            lock_duo_features_enabled: ['cannot be changed because it is locked by an ancestor'],
          },
        },
      },
    };

    expect(formatSettingsErrorMessage(error, defaultMessage)).toBe(
      `${defaultMessage} GitLab Duo availability cannot be changed because it is locked by ` +
        'an ancestor',
    );
  });

  it('joins multiple messages for the same field with a comma', () => {
    const error = {
      response: {
        data: {
          message: { lock_duo_custom_flows_enabled: ['is invalid', 'is too long'] },
        },
      },
    };

    expect(formatSettingsErrorMessage(error, defaultMessage)).toBe(
      `${defaultMessage} Allow custom flows is invalid, is too long`,
    );
  });

  it('joins two labelled fields with "and"', () => {
    const error = {
      response: {
        data: {
          message: {
            'namespace_settings.lock_duo_custom_agents_enabled': [
              'cannot be changed because it is locked by an ancestor',
            ],
            lock_tool_approval_for_session_enabled: [
              'cannot be changed because it is locked by an ancestor',
            ],
          },
        },
      },
    };

    expect(formatSettingsErrorMessage(error, defaultMessage)).toBe(
      `${defaultMessage} Allow custom agents cannot be changed because it is locked by an ` +
        'ancestor and Tool approval for sessions cannot be changed because it is locked by an ' +
        'ancestor',
    );
  });

  it('joins three or more labelled fields with an Oxford comma', () => {
    const error = {
      response: {
        data: {
          message: {
            lock_duo_features_enabled: ['is invalid'],
            lock_duo_remote_flows_enabled: ['is invalid'],
            lock_duo_foundational_flows_enabled: ['is invalid'],
          },
        },
      },
    };

    expect(formatSettingsErrorMessage(error, defaultMessage)).toBe(
      `${defaultMessage} GitLab Duo availability is invalid, Allow flow execution is invalid, ` +
        'and Allow foundational flows is invalid',
    );
  });

  it('drops unlabelled fields while keeping labelled fields in a mixed hash', () => {
    const error = {
      response: {
        data: {
          message: {
            some_internal_only_attribute: ['is invalid'],
            lock_duo_custom_agents_enabled: [
              'cannot be changed because it is locked by an ancestor',
            ],
          },
        },
      },
    };

    expect(formatSettingsErrorMessage(error, defaultMessage)).toBe(
      `${defaultMessage} Allow custom agents cannot be changed because it is locked by an ` +
        'ancestor',
    );
  });
});
