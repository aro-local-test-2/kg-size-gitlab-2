import { UserPromptBuilder } from 'ee/ai/duo_agentic_chat/services/user_prompt';
import { MAX_PROMPT_LENGTH } from 'ee/ai/tanuki_bot/constants';

const ANY = { value: '/any', description: 'Valid anywhere in the prompt' };
const OTHER = { value: '/other', description: 'Also valid anywhere' };
const START = { value: '/start', description: 'Valid only at the start', startOnly: true };
const CATALOGUE = [ANY, OTHER];
const GOAL_FLOW = { consumerId: 42 };

const builderWith = (text, catalogue = CATALOGUE) =>
  UserPromptBuilder.empty().withCatalogue(catalogue).withText(text);

describe('UserPromptBuilder', () => {
  describe('empty', () => {
    it('builds an empty prompt', () => {
      expect(UserPromptBuilder.empty().build()).toEqual({
        text: '',
        slashCommands: [],
        goalFlow: null,
        attachments: [],
      });
    });
  });

  describe('withText', () => {
    it('does not mutate the builder it came from', () => {
      const original = UserPromptBuilder.empty();

      original.withText('hello');

      expect(original.text).toBe('');
    });

    it('trims the text when building', () => {
      expect(builderWith('  hello  ').build().text).toBe('hello');
    });
  });

  describe('slashCommands', () => {
    it('records a command the user typed by hand', () => {
      expect(builderWith('/any').build().slashCommands).toEqual([ANY]);
    });

    it('drops a command once its token is edited away', () => {
      const draft = builderWith('/any please').withText('please');

      expect(draft.build().slashCommands).toEqual([]);
    });

    it('keeps a command while text around it changes', () => {
      const draft = builderWith('/any').withText('/any everything');

      expect(draft.build().slashCommands).toEqual([ANY]);
    });

    it('orders the commands by where they appear in the text', () => {
      const commands = builderWith('/other then /any').build().slashCommands;

      expect(commands).toEqual([OTHER, ANY]);
    });

    // The menu closes on `/Any ` because it decides a typed token is a command
    // case-insensitively, so the payload has to agree or the two disagree about
    // whether a command was used at all.
    it('matches a token the user typed in a different case', () => {
      expect(builderWith('/Any').build().slashCommands).toEqual([ANY]);
    });

    it('does not match a token that is only a prefix of a longer word', () => {
      expect(builderWith('/anything').build().slashCommands).toEqual([]);
    });

    it('does not match a token inside a URL', () => {
      expect(builderWith('https://example.com/other').build().slashCommands).toEqual([]);
    });

    it('finds a command nested in a group', () => {
      const grouped = [{ label: 'Chat', items: [ANY] }];

      expect(builderWith('/any', grouped).build().slashCommands).toEqual([ANY]);
    });

    it('picks up a token typed before the catalogue resolved', () => {
      const draft = UserPromptBuilder.empty().withText('/any').withCatalogue(CATALOGUE);

      expect(draft.build().slashCommands).toEqual([ANY]);
    });

    it('is empty while the catalogue is still unresolved', () => {
      expect(UserPromptBuilder.empty().withText('/any').build().slashCommands).toEqual([]);
    });

    // A context switch reloads the catalogue, and the reloaded one need not still
    // offer a command the user has already typed. The token is in the text, so the
    // command is still part of the prompt.
    it('keeps a recorded command the reloaded catalogue no longer offers', () => {
      const draft = builderWith('/any').withCatalogue([]);

      expect(draft.build().slashCommands).toEqual([ANY]);
    });

    it('still drops that command once its token leaves the text', () => {
      const draft = builderWith('/any').withCatalogue([]).withText('never mind');

      expect(draft.build().slashCommands).toEqual([]);
    });

    describe('startOnly commands', () => {
      it('records one that opens the prompt', () => {
        expect(builderWith('/start please', [START]).build().slashCommands).toEqual([START]);
      });

      // The whole point of the flag: acting on this entry would run the command for a
      // sentence that only asked what it does.
      it('ignores one the prompt merely mentions', () => {
        expect(builderWith('tell me what /start does', [START]).build().slashCommands).toEqual([]);
      });

      it('records one behind the leading whitespace the prompt is trimmed of', () => {
        expect(builderWith('  /start', [START]).build().slashCommands).toEqual([START]);
      });

      // `tokenIndex` counts a newline as a token boundary like any other whitespace,
      // so "starts the prompt" has to mean the first line rather than any line.
      it.each([
        ['\n/start', [START]],
        ['ok\n/start', []],
      ])('records %p as %p', (text, expected) => {
        expect(builderWith(text, [START]).build().slashCommands).toEqual(expected);
      });

      it('keeps the order of the commands that survive the filter', () => {
        expect(builderWith('/start then /any', [START, ANY]).build().slashCommands).toEqual([
          START,
          ANY,
        ]);
      });

      it('drops only the flagged one from a prompt mentioning both', () => {
        expect(builderWith('tell me /start and /any', [START, ANY]).build().slashCommands).toEqual([
          ANY,
        ]);
      });

      it('drops one already recorded once an edit pushes it off the start', () => {
        const draft = builderWith('/start', [START]).withText('please /start');

        expect(draft.build().slashCommands).toEqual([]);
      });

      it('leaves a command without the flag matching anywhere', () => {
        expect(builderWith('tell me what /any does').build().slashCommands).toEqual([ANY]);
      });
    });

    it('preserves a record already held for a token across a text edit', () => {
      // Stands in for a command carrying something the catalogue cannot supply, such
      // as a selected param.
      const withParam = { ...ANY, param: { id: 'gid://gitlab/Label/1' } };
      const draft = builderWith('/any', [withParam])
        .withCatalogue(CATALOGUE)
        .withText('/any everything');

      expect(draft.build().slashCommands).toEqual([withParam]);
    });
  });

  describe('withSlashCommand', () => {
    it('replaces only the matched token', () => {
      const draft = builderWith('tell me /an about it').withSlashCommand(ANY, {
        triggerIndex: 8,
        token: '/an',
      });

      expect(draft.text).toBe('tell me /any about it');
    });

    it('adds a separator when the command would run into what follows', () => {
      const draft = builderWith('/an').withSlashCommand(ANY, {
        triggerIndex: 0,
        token: '/an',
      });

      expect(draft.text).toBe('/any ');
    });

    it('records the command it inserted', () => {
      const draft = builderWith('/an').withSlashCommand(ANY, {
        triggerIndex: 0,
        token: '/an',
      });

      expect(draft.build().slashCommands).toEqual([ANY]);
    });

    // The menu offers a startOnly command only at the start, so whatever it inserts
    // there has to survive the filter -- otherwise picking one silently does nothing.
    it('records a startOnly command inserted at the start', () => {
      const draft = builderWith('/st', [START]).withSlashCommand(START, {
        triggerIndex: 0,
        token: '/st',
      });

      expect(draft.build().slashCommands).toEqual([START]);
    });
  });

  describe('attachments', () => {
    it('adds and removes by id', () => {
      const draft = UserPromptBuilder.empty()
        .withAttachment({ id: 'a1' })
        .withAttachment({ id: 'a2' })
        .withoutAttachment('a1');

      expect(draft.build().attachments).toEqual([{ id: 'a2' }]);
    });
  });

  describe('cleared', () => {
    const GOAL_COMMAND = { value: '/goal', startOnly: true, action: 'startGoal' };

    it('empties the draft but keeps the catalogue', () => {
      const draft = builderWith('/any').withAttachment({ id: 'a1' }).cleared();

      expect(draft.build()).toEqual({
        text: '',
        slashCommands: [],
        goalFlow: null,
        attachments: [],
      });
      expect(draft.withText('/any').build().slashCommands).toEqual([ANY]);
    });

    it('leaves goal mode', () => {
      const draft = new UserPromptBuilder({
        text: 'ship it',
        catalogue: [GOAL_COMMAND],
      }).withGoalFlow(GOAL_FLOW);

      expect(draft.cleared().goalFlow).toBeNull();
    });
  });

  describe('goal mode', () => {
    const GOAL = { value: '/goal', startOnly: true, action: 'startGoal' };
    const withGoal = (text) => new UserPromptBuilder({ text, catalogue: [...CATALOGUE, GOAL] });

    it('is off to begin with', () => {
      expect(UserPromptBuilder.empty().goalFlow).toBeNull();
    });

    // The composer runs `START_GOAL` and hands the flow down; the builder only carries
    // it. Deriving it would let a later edit switch the mode off under the user.
    it('is not turned on by the goal token appearing in the text', () => {
      const draft = withGoal('/goal keep the pipeline green');

      expect(draft.goalFlow).toBeNull();
      expect(draft.text).toBe('/goal keep the pipeline green');
    });

    it('is on once the flow is recorded, and is reported on the built prompt', () => {
      const draft = withGoal('keep it green').withGoalFlow(GOAL_FLOW);

      expect(draft.goalFlow).toEqual(GOAL_FLOW);
      expect(draft.build().goalFlow).toEqual(GOAL_FLOW);
    });

    // Nothing is left in the text to read it back off.
    it('stays on while the goal is typed', () => {
      const draft = withGoal('').withGoalFlow(GOAL_FLOW).withText('keep it green');

      expect(draft.goalFlow).toEqual(GOAL_FLOW);
      expect(draft.text).toBe('keep it green');
    });

    it('survives the catalogue arriving', () => {
      const draft = new UserPromptBuilder({ text: 'keep it green' })
        .withGoalFlow(GOAL_FLOW)
        .withCatalogue([GOAL]);

      expect(draft.goalFlow).toEqual(GOAL_FLOW);
    });

    describe('withoutGoalFlow', () => {
      it('leaves the mode but keeps the goal already typed', () => {
        const draft = withGoal('keep it green').withGoalFlow(GOAL_FLOW).withoutGoalFlow();

        expect(draft.goalFlow).toBeNull();
        expect(draft.text).toBe('keep it green');
      });

      it('leaves a draft that was never in goal mode alone', () => {
        expect(withGoal('keep it green').withoutGoalFlow().goalFlow).toBeNull();
      });
    });
  });

  describe('withoutCommandToken', () => {
    const GOAL = { value: '/goal', startOnly: true, action: 'startGoal' };
    const withGoal = (text) => new UserPromptBuilder({ text, catalogue: [...CATALOGUE, GOAL] });

    // The token stands in for the command, so the prompt underneath is the goal.
    it('takes the token out of the text', () => {
      expect(withGoal('/goal keep the pipeline green').withoutCommandToken(GOAL).text).toBe(
        'keep the pipeline green',
      );
    });

    it('leaves an empty prompt when the token was all there was', () => {
      expect(withGoal('/goal ').withoutCommandToken(GOAL).text).toBe('');
    });

    // Matched case-insensitively, so removing it has to be too, or the slash is stranded.
    it.each(['/Goal ship it', '/GOAL ship it'])('takes %p out whole, cased as typed', (text) => {
      expect(withGoal(text).withoutCommandToken(GOAL).text).toBe('ship it');
    });

    it('takes the token out from where it sits, not only from the start', () => {
      const GOAL_ANYWHERE = { value: '/goal', action: 'startGoal' };
      const draft = new UserPromptBuilder({
        text: 'today /goal ship it',
        catalogue: [GOAL_ANYWHERE],
      });

      expect(draft.withoutCommandToken(GOAL_ANYWHERE).text).toBe('today ship it');
    });

    it('stops reporting the token it removed as a command', () => {
      expect(withGoal('/goal keep it green').withoutCommandToken(GOAL).slashCommands).toEqual([]);
    });

    // How the toolbar reaches `START_GOAL`: it types nothing.
    it('leaves the text alone when the command was never typed', () => {
      const draft = withGoal('keep it green');

      expect(draft.withoutCommandToken(GOAL)).toBe(draft);
    });

    it('leaves the text alone for a command with no value', () => {
      const draft = withGoal('keep it green');

      expect(draft.withoutCommandToken({})).toBe(draft);
      expect(draft.withoutCommandToken(undefined)).toBe(draft);
    });

    // A prompt asking about a command never recorded it, so its words stay put.
    it('leaves a prompt that only mentions the command alone', () => {
      const draft = withGoal('tell me what /goal does');

      expect(draft.slashCommands).toEqual([]);
      expect(draft.withoutCommandToken(GOAL).text).toBe('tell me what /goal does');
    });
  });

  describe('isTextEmpty', () => {
    it.each([
      ['', true],
      ['   ', true],
      ['hello', false],
    ])('is %p for %p', (text, expected) => {
      expect(builderWith(text).isTextEmpty).toBe(expected);
    });
  });

  describe('isTextWithinLengthLimit', () => {
    it('allows text at the limit', () => {
      expect(builderWith('a'.repeat(MAX_PROMPT_LENGTH)).isTextWithinLengthLimit).toBe(true);
    });

    it('rejects text past the limit', () => {
      expect(builderWith('a'.repeat(MAX_PROMPT_LENGTH + 1)).isTextWithinLengthLimit).toBe(false);
    });
  });
});
