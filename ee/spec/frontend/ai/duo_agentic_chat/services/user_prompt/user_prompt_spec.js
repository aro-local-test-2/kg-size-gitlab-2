import { createUserPrompt, EMPTY_USER_PROMPT } from 'ee/ai/duo_agentic_chat/services/user_prompt';

describe('createUserPrompt', () => {
  it('defaults every field', () => {
    expect(createUserPrompt()).toEqual({
      text: '',
      slashCommands: [],
      goalFlow: null,
      attachments: [],
    });
  });

  it('keeps the parts it is given', () => {
    const slashCommands = [{ value: '/compact' }];
    const attachments = [{ id: 'a1' }];

    expect(
      createUserPrompt({
        text: 'hello',
        slashCommands,
        goalFlow: { consumerId: 42 },
        attachments,
      }),
    ).toEqual({
      text: 'hello',
      slashCommands,
      goalFlow: { consumerId: 42 },
      attachments,
    });
  });

  it('copies the arrays so a later mutation cannot reach into the prompt', () => {
    const slashCommands = [{ value: '/compact' }];
    const prompt = createUserPrompt({ slashCommands });

    slashCommands.push({ value: '/new' });

    expect(prompt.slashCommands).toHaveLength(1);
  });

  it('survives a JSON round trip, which is how the queue persists it', () => {
    const prompt = createUserPrompt({
      text: 'hello',
      slashCommands: [{ value: '/compact' }],
      goalFlow: { consumerId: 42 },
    });

    expect(JSON.parse(JSON.stringify(prompt))).toEqual(prompt);
  });
});

describe('EMPTY_USER_PROMPT', () => {
  it('is an empty prompt', () => {
    expect(EMPTY_USER_PROMPT).toEqual({
      text: '',
      slashCommands: [],
      goalFlow: null,
      attachments: [],
    });
  });
});
