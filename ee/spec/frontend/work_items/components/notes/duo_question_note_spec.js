import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapse } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoQuestionNote from 'ee/work_items/components/notes/duo_question_note.vue';
import DuoCustomAnswerInput from 'ee/work_items/components/notes/duo_custom_answer_input.vue';
import DuoMultiSelectOptions from 'ee/work_items/components/notes/duo_multi_select_options.vue';
import DuoSingleSelectOptions from 'ee/work_items/components/notes/duo_single_select_options.vue';
import createNoteMutation from '~/work_items/graphql/notes/create_work_item_note.mutation.graphql';
import toggleResolveDiscussionMutation from '~/work_items/graphql/notes/toggle_work_item_note_resolve_discussion.mutation.graphql';
import {
  createWorkItemNoteResponse,
  mockToggleResolveDiscussionResponse,
} from 'ee_jest/work_items/mock_data';

Vue.use(VueApollo);

const fenced = (payload) => `Which cutover approach should we use?

\`\`\`json:duo-question
${JSON.stringify(payload)}
\`\`\``;

// Most cases vary only the options of a closed question.
const closedBody = (options) => fenced({ type: 'closed', question: 'Which?', options });

const OPTIONS = [
  { id: 'hard_removal', label: 'Hard removal', description: 'One patch.' },
  { id: 'staged', label: 'Staged deprecation', recommended: true },
];
const CLOSED_QUESTION = closedBody(OPTIONS);
const MULTI_QUESTION = fenced({
  type: 'closed',
  question: 'Which SAML 2.0 capabilities are in scope?',
  multiple: true,
  options: [
    { id: 'sp_sso', label: 'SP-initiated SSO', recommended: true },
    { id: 'jit', label: 'Just-in-time provisioning', recommended: true },
    { id: 'idp_sso', label: 'IdP-initiated SSO' },
  ],
});

const NOTE_ID = 'gid://gitlab/Note/7';
const WORK_ITEM_ID = 'gid://gitlab/WorkItem/1';
const DISCUSSION_ID = 'gid://gitlab/Discussion/abc';

describe('DuoQuestionNote', () => {
  useLocalStorageSpy();

  let wrapper;
  let createNoteHandler;
  let resolveHandler;

  const createComponent = ({
    body = CLOSED_QUESTION,
    replies = [],
    isDiscussionResolved = false,
    isDiscussionResolvable = true,
    canReply = true,
    duoWorkplanAsyncFlow = true,
    mountFn = shallowMountExtended,
  } = {}) => {
    createNoteHandler = jest.fn().mockResolvedValue(createWorkItemNoteResponse());
    resolveHandler = jest.fn().mockResolvedValue(mockToggleResolveDiscussionResponse);

    wrapper = mountFn(DuoQuestionNote, {
      apolloProvider: createMockApollo([
        [createNoteMutation, createNoteHandler],
        [toggleResolveDiscussionMutation, resolveHandler],
      ]),
      propsData: {
        note: { id: NOTE_ID, body, internal: false },
        workItemId: WORK_ITEM_ID,
        discussionId: DISCUSSION_ID,
        replies,
        isDiscussionResolved,
        isDiscussionResolvable,
        canReply,
      },
      provide: { glFeatures: { duoWorkplanAsyncFlow } },
    });
  };

  const findCard = () => wrapper.findByTestId('duo-question-note');
  const findCustomAnswerInput = () => wrapper.findComponent(DuoCustomAnswerInput);
  const findSingleSelect = () => wrapper.findComponent(DuoSingleSelectOptions);
  const findMultiSelect = () => wrapper.findComponent(DuoMultiSelectOptions);
  const findAnswer = () => wrapper.findByTestId('duo-answer');
  const findAnswers = () => wrapper.findAllByTestId('duo-answer');
  const findSubmit = () => wrapper.findComponentByTestId('duo-question-submit');
  const findOptionsToggle = () => wrapper.findComponentByTestId('duo-question-options-toggle');
  const findCollapse = () => wrapper.findComponent(GlCollapse);
  const answerText = () => (findAnswer().exists() ? findAnswer().text() : null);
  const asReplies = (bodies) => bodies.map((body) => ({ body }));
  // The option rows live in their own components, so the note only sees a choice.
  const chooseOption = async (index) => {
    await findSingleSelect().vm.$emit('select', OPTIONS[index]);
    await waitForPromises();
  };

  describe('when a closed question is present', () => {
    beforeEach(() => createComponent());

    it('hands the parsed options to the single-select rows', () => {
      expect(findSingleSelect().props('options')).toEqual([
        {
          id: 'hard_removal',
          label: 'Hard removal',
          description: 'One patch.',
          recommended: false,
        },
        { id: 'staged', label: 'Staged deprecation', description: '', recommended: true },
      ]);
      expect(findMultiSelect().exists()).toBe(false);
    });

    it('renders no answer until one is chosen', () => {
      expect(findAnswer().exists()).toBe(false);
    });
  });

  describe('answering in your own words', () => {
    const RATIONALE = 'We already ship a per-IP limiter, so neither option fits.';
    const ANSWER_BODY = `${RATIONALE}\n\n<!-- duo-answer: rejected -->`;
    const DRAFT_KEY = `autosave/${DISCUSSION_ID}-duo-answer`;
    // The input owns the answer being written, so the note only sees a finished one.
    const submitCustom = async (answer = RATIONALE) => {
      await findCustomAnswerInput().vm.$emit('submit', answer);
      await waitForPromises();
    };

    beforeEach(() => createComponent());

    it('offers the input alongside the options, keyed apart from the reply box', () => {
      expect(findCustomAnswerInput().props('draftKey')).toBe(`${DISCUSSION_ID}-duo-answer`);
      expect(findCustomAnswerInput().props('inputId')).toBe(`duo-custom-answer-${NOTE_ID}`);
      expect(findSingleSelect().exists()).toBe(true);
    });

    it('posts and resolves, marking the answer as custom', async () => {
      await submitCustom();

      expect(createNoteHandler).toHaveBeenCalledWith({
        input: {
          noteableId: WORK_ITEM_ID,
          discussionId: DISCUSSION_ID,
          body: ANSWER_BODY,
          internal: false,
        },
      });
      expect(resolveHandler).toHaveBeenCalledWith({ id: DISCUSSION_ID, resolve: true });
      expect(findSingleSelect().exists()).toBe(false);
      expect(findCustomAnswerInput().exists()).toBe(false);
      expect(answerText()).toBe(RATIONALE);
    });

    it('tells the input it is busy while the answer is in flight', async () => {
      findCustomAnswerInput().vm.$emit('submit', RATIONALE);
      await nextTick();

      expect(findCustomAnswerInput().props('disabled')).toBe(true);
      expect(findCustomAnswerInput().props('submitting')).toBe(true);
    });

    // The note discards the draft itself, because by this point Apollo has re-rendered
    // it into its answered state and the input is no longer mounted.
    it('discards the draft once the answer is posted', async () => {
      localStorage.setItem(DRAFT_KEY, RATIONALE);
      await submitCustom();

      expect(localStorage.getItem(DRAFT_KEY)).toBeNull();
    });

    it('keeps the draft when posting fails, so the answer is not lost', async () => {
      localStorage.setItem(DRAFT_KEY, RATIONALE);
      createNoteHandler.mockRejectedValue(new Error('nope'));
      await submitCustom();

      expect(localStorage.getItem(DRAFT_KEY)).toBe(RATIONALE);
    });

    it('recovers a custom answer from the thread after a reload', () => {
      createComponent({ replies: asReplies([ANSWER_BODY]), isDiscussionResolved: true });

      expect(findSingleSelect().exists()).toBe(false);
      expect(answerText()).toBe(RATIONALE);
    });
  });

  describe('when the question accepts several answers', () => {
    // Every checkbox shares one array model, so a change emits the whole selection.
    const tick = (ids) => {
      findMultiSelect().vm.$emit('input', ids);
      return nextTick();
    };
    const submitSelection = async (ids) => {
      await tick(ids);
      findSubmit().vm.$emit('click');
      await waitForPromises();
    };

    beforeEach(() => createComponent({ body: MULTI_QUESTION }));

    it('renders in its multi-select shape, so nothing settles on the first click', () => {
      expect(findMultiSelect().props('options')).toHaveLength(3);
      expect(findSingleSelect().exists()).toBe(false);
      expect(findCustomAnswerInput().props('multiple')).toBe(true);
    });

    it('keeps submit disabled until something is ticked', async () => {
      expect(findSubmit().props('disabled')).toBe(true);

      await tick(['jit']);

      expect(findSubmit().props('disabled')).toBe(false);
    });

    // Bodies name the choices in the order the question offered them, not the order they
    // were ticked, so the reply reads the way the card does.
    it.each`
      scenario                        | ticked                   | typed                    | body                                                                                         | answers
      ${'options alone'}              | ${['idp_sso', 'sp_sso']} | ${''}                    | ${'- SP-initiated SSO\n- IdP-initiated SSO\n\n<!-- duo-answer: sp_sso,idp_sso -->'}          | ${['SP-initiated SSO', 'IdP-initiated SSO']}
      ${'options and a typed answer'} | ${['jit']}               | ${'Single logout (SLO)'} | ${'- Just-in-time provisioning\n- Single logout (SLO)\n\n<!-- duo-answer: jit,rejected -->'} | ${['Just-in-time provisioning', 'Single logout (SLO)']}
    `(
      'sends $scenario as one reply, resolves, and lists what was answered',
      async ({ ticked, typed, body, answers }) => {
        if (typed) await findCustomAnswerInput().vm.$emit('change', typed);
        await submitSelection(ticked);

        expect(createNoteHandler).toHaveBeenCalledWith({
          input: { noteableId: WORK_ITEM_ID, discussionId: DISCUSSION_ID, body, internal: false },
        });
        expect(resolveHandler).toHaveBeenCalledWith({ id: DISCUSSION_ID, resolve: true });
        expect(findMultiSelect().exists()).toBe(false);
        expect(findAnswers().wrappers.map((w) => w.text())).toEqual(answers);
      },
    );

    describe('when option is clicked', () => {
      const selectedOption = () =>
        wrapper
          .findAll('[data-testid="duo-question-option"] input[type="checkbox"]')
          .wrappers.filter((box) => box.element.checked).length;

      beforeEach(() => {
        wrapper = mountExtended(DuoQuestionNote, {
          apolloProvider: createMockApollo([
            [createNoteMutation, jest.fn().mockResolvedValue(createWorkItemNoteResponse())],
            [
              toggleResolveDiscussionMutation,
              jest.fn().mockResolvedValue(mockToggleResolveDiscussionResponse),
            ],
          ]),
          propsData: {
            note: { id: NOTE_ID, body: MULTI_QUESTION, internal: false },
            workItemId: WORK_ITEM_ID,
            discussionId: DISCUSSION_ID,
            replies: [],
            isDiscussionResolved: false,
            isDiscussionResolvable: true,
            canReply: true,
          },
          provide: { glFeatures: { duoWorkplanAsyncFlow: true } },
        });
      });

      // Clicking the row rather than the box is covered by the click area
      // `MultipleChoiceSelectorItem` lays over the label, which jsdom cannot hit.
      it('toggles when the label is clicked instead of the checkbox', async () => {
        await wrapper.findAll('[data-testid="duo-question-option"] label').at(0).trigger('click');
        expect(selectedOption()).toBe(1);

        await wrapper.findAll('[data-testid="duo-question-option"] label').at(1).trigger('click');
        expect(selectedOption()).toBe(2);
      });
    });

    // A reload has no component state, so the answers come back out of the reply. The
    // labels are read from its bullets, since a typed answer exists nowhere else.
    it('recovers every answer from the thread after a reload', () => {
      createComponent({
        body: MULTI_QUESTION,
        replies: asReplies([
          '- SP-initiated SSO\n- Single logout (SLO)\n\n<!-- duo-answer: sp_sso,rejected -->',
        ]),
        isDiscussionResolved: true,
      });

      expect(findAnswers().wrappers.map((w) => w.text())).toEqual([
        'SP-initiated SSO',
        'Single logout (SLO)',
      ]);
    });

    it('renders separate rows when answers have the same label', () => {
      createComponent({
        body: MULTI_QUESTION,
        replies: asReplies(['- Same label\n- Same label\n\n<!-- duo-answer: sp_sso,jit -->']),
        isDiscussionResolved: true,
      });

      expect(findAnswers().wrappers.map((answer) => answer.text())).toEqual([
        'Same label',
        'Same label',
      ]);
    });
  });

  describe('when nothing is renderable', () => {
    it.each`
      scenario                                            | props
      ${'the async flow flag is off'}                     | ${{ duoWorkplanAsyncFlow: false }}
      ${'the parser finds no question'}                   | ${{ body: 'Just an ordinary comment.' }}
      ${'the parser rejects the payload'}                 | ${{ body: '```json:duo-question\n{not json\n```' }}
      ${'the question is open, so nothing can be picked'} | ${{ body: fenced({ type: 'open', question: 'How many users?' }) }}
    `('renders nothing when $scenario', ({ props }) => {
      createComponent(props);

      expect(findCard().exists()).toBe(false);
    });
  });

  describe('when an option is chosen', () => {
    beforeEach(async () => {
      createComponent();
      await chooseOption(1);
    });

    it('posts the label as a reply, resolves the thread, and shows the answer', () => {
      expect(createNoteHandler).toHaveBeenCalledWith({
        input: {
          noteableId: WORK_ITEM_ID,
          discussionId: DISCUSSION_ID,
          // The id rides along so a later run can tell which option was picked.
          body: 'Staged deprecation\n\n<!-- duo-answer: staged -->',
          internal: false,
        },
      });
      expect(resolveHandler).toHaveBeenCalledWith({ id: DISCUSSION_ID, resolve: true });
      expect(findSingleSelect().exists()).toBe(false);
      expect(findAnswer().text()).toContain('Staged deprecation');
    });
  });

  describe('when the thread already carries an answer', () => {
    // A reload has no component state to fall back on, so the answer has to come
    // back out of the reply that carries it.
    it.each`
      scenario                       | markerId          | answer            | optionsShown
      ${'matches an offered option'} | ${'hard_removal'} | ${'Hard removal'} | ${false}
      ${'matches no offered option'} | ${'nope'}         | ${null}           | ${true}
    `('when the marker $scenario', ({ markerId, answer, optionsShown }) => {
      createComponent({
        replies: asReplies([`some reply\n\n<!-- duo-answer: ${markerId} -->`]),
        isDiscussionResolved: true,
      });

      expect(answerText()).toBe(answer);
      expect(findSingleSelect().exists()).toBe(optionsShown);
    });

    // Threads collect ordinary conversation too, and a peer quoting an earlier
    // answer must not read as a fresh one.
    it.each`
      scenario                            | replies
      ${'discussion precedes the answer'} | ${['What are the trade-offs?', 'Hard removal\n\n<!-- duo-answer: hard_removal -->']}
      ${'discussion follows the answer'}  | ${['Hard removal\n\n<!-- duo-answer: hard_removal -->', 'Agreed.']}
      ${'a peer quotes another option'}   | ${['Hard removal\n\n<!-- duo-answer: hard_removal -->', '> <!-- duo-answer: staged -->\n\nI prefer this.']}
    `('still shows the chosen option when $scenario', ({ replies }) => {
      createComponent({ replies: asReplies(replies), isDiscussionResolved: true });

      expect(answerText()).toBe('Hard removal');
    });

    it('prefers the most recent answer when the thread carries more than one', () => {
      createComponent({
        replies: asReplies([
          'Hard removal\n\n<!-- duo-answer: hard_removal -->',
          'Staged deprecation\n\n<!-- duo-answer: staged -->',
        ]),
        isDiscussionResolved: true,
      });

      expect(answerText()).toBe('Staged deprecation');
    });

    it('does not resolve an already-resolved thread a second time', async () => {
      createComponent({ isDiscussionResolved: true });
      await chooseOption(0);

      expect(createNoteHandler).toHaveBeenCalled();
      expect(resolveHandler).not.toHaveBeenCalled();
    });
  });

  describe('when the user cannot resolve the thread', () => {
    const DRAFT_KEY = `autosave/${DISCUSSION_ID}-duo-answer`;

    it('posts the answer, leaves the thread open, and keeps the options on offer', async () => {
      createComponent({ isDiscussionResolvable: false });
      await chooseOption(0);

      expect(createNoteHandler).toHaveBeenCalledWith({
        input: {
          noteableId: WORK_ITEM_ID,
          discussionId: DISCUSSION_ID,
          body: 'Hard removal\n\n<!-- duo-answer: hard_removal -->',
          internal: false,
        },
      });
      expect(resolveHandler).not.toHaveBeenCalled();
      expect(findSingleSelect().exists()).toBe(true);
      expect(findAnswer().exists()).toBe(false);
    });

    it('drops the ticked options and the drafted answer, so nothing reads as accepted', async () => {
      localStorage.setItem(DRAFT_KEY, 'Neither option fits.');
      createComponent({ body: MULTI_QUESTION, isDiscussionResolvable: false });

      findMultiSelect().vm.$emit('input', ['sp_sso']);
      await nextTick();
      findSubmit().vm.$emit('click');
      await waitForPromises();

      expect(findMultiSelect().props('checkedIds')).toEqual([]);
      expect(localStorage.getItem(DRAFT_KEY)).toBe(null);
      expect(findAnswers()).toHaveLength(0);
    });

    it.each`
      scenario         | isDiscussionResolvable
      ${'a guest'}     | ${false}
      ${'anyone else'} | ${true}
    `(
      'shows an unresolved thread as unanswered to $scenario, whoever replied',
      ({ isDiscussionResolvable }) => {
        createComponent({
          replies: asReplies(['Hard removal\n\n<!-- duo-answer: hard_removal -->']),
          isDiscussionResolved: false,
          isDiscussionResolvable,
        });

        expect(findSingleSelect().exists()).toBe(true);
        expect(findAnswer().exists()).toBe(false);
      },
    );
  });

  describe('when the thread is resolved without an answer', () => {
    const findOptionRows = () => wrapper.findAllByTestId('duo-question-option');

    it.each`
      shape              | body               | find
      ${'single select'} | ${CLOSED_QUESTION} | ${findSingleSelect}
      ${'multi select'}  | ${MULTI_QUESTION}  | ${findMultiSelect}
    `('collapses $shape options behind a toggle and offers nothing to click', ({ body, find }) => {
      createComponent({ body, isDiscussionResolved: true });

      expect(findOptionsToggle().text()).toBe('Show suggested answers');
      expect(findCollapse().props('visible')).toBe(false);
      expect(find().props('disabled')).toBe(true);
      expect(findSubmit().exists()).toBe(false);
    });

    it.each`
      shape              | body
      ${'single select'} | ${CLOSED_QUESTION}
      ${'multi select'}  | ${MULTI_QUESTION}
    `('offers no typed answer on a $shape question', ({ body }) => {
      createComponent({ body, isDiscussionResolved: true });

      expect(findCustomAnswerInput().exists()).toBe(false);
    });

    it('reveals the options and flips the toggle when it is clicked', async () => {
      createComponent({ isDiscussionResolved: true });
      await findOptionsToggle().vm.$emit('click');

      expect(findOptionsToggle().text()).toBe('Hide suggested answers');
      expect(findCollapse().props('visible')).toBe(true);

      await findOptionsToggle().vm.$emit('click');

      expect(findOptionsToggle().text()).toBe('Show suggested answers');
      expect(findCollapse().props('visible')).toBe(false);
    });

    it('leaves the revealed rows unfocusable, so the record cannot be answered', async () => {
      createComponent({ isDiscussionResolved: true, mountFn: mountExtended });
      await findOptionsToggle().trigger('click');

      expect(findOptionRows()).toHaveLength(OPTIONS.length);
      findOptionRows().wrappers.forEach((row) => {
        expect(row.attributes('disabled')).toBeDefined();
      });
    });

    it.each`
      scenario                          | props
      ${'the thread is unresolved'}     | ${{}}
      ${'the thread carries an answer'} | ${{ isDiscussionResolved: true, replies: [{ body: 'Hard removal\n\n<!-- duo-answer: hard_removal -->' }] }}
    `('offers no toggle when $scenario', ({ props }) => {
      createComponent(props);

      expect(findOptionsToggle().exists()).toBe(false);
    });
  });

  describe('when the user cannot reply', () => {
    it.each`
      shape              | body               | find
      ${'single select'} | ${CLOSED_QUESTION} | ${findSingleSelect}
      ${'multi select'}  | ${MULTI_QUESTION}  | ${findMultiSelect}
    `('shows $shape options but offers nothing to click', ({ body, find }) => {
      createComponent({ body, canReply: false });

      expect(find().props('disabled')).toBe(true);
      expect(findCustomAnswerInput().exists()).toBe(false);
      expect(findSubmit().exists()).toBe(false);
    });

    it('still shows the answer a resolved thread carries', () => {
      createComponent({
        replies: asReplies(['Hard removal\n\n<!-- duo-answer: hard_removal -->']),
        isDiscussionResolved: true,
        canReply: false,
      });

      expect(answerText()).toBe('Hard removal');
    });
  });

  describe('when the answer posts but the thread will not resolve', () => {
    beforeEach(async () => {
      createComponent();
      resolveHandler.mockRejectedValueOnce(new Error('nope'));
      await chooseOption(0);
    });

    it('keeps the answer and reports the thread, not the answer, as the failure', () => {
      expect(answerText()).toBe('Hard removal');
      expect(wrapper.emitted('error')).toEqual([
        [
          'Your answer was posted, but the thread could not be resolved. Resolve it manually so GitLab Duo can continue.',
        ],
      ]);
    });
  });

  describe('when posting the answer fails', () => {
    it.each`
      scenario                        | fail
      ${'the request rejects'}        | ${(handler) => handler.mockRejectedValueOnce(new Error('nope'))}
      ${'the payload carries errors'} | ${(handler) => handler.mockResolvedValueOnce(createWorkItemNoteResponse({ errors: ['Note cannot be created'] }))}
    `('leaves the question answerable when $scenario', async ({ fail }) => {
      createComponent();
      fail(createNoteHandler);
      await chooseOption(0);

      expect(wrapper.emitted('error')).toHaveLength(1);
      expect(findSingleSelect().exists()).toBe(true);
      expect(findAnswer().exists()).toBe(false);
      // No reply was posted, so resolving would settle a question nobody answered.
      expect(resolveHandler).not.toHaveBeenCalled();
    });
  });
});
