import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import DuoCustomAnswerInput from 'ee/work_items/components/notes/duo_custom_answer_input.vue';

const DRAFT_KEY = 'gid://gitlab/Discussion/abc-duo-answer';
const AUTOSAVE_KEY = `autosave/${DRAFT_KEY}`;
const INPUT_ID = 'duo-custom-answer-1';
const RATIONALE = 'We already ship a per-IP limiter, so neither option fits.';

describe('DuoCustomAnswerInput', () => {
  useLocalStorageSpy();

  let wrapper;

  const createComponent = ({ disabled = false, submitting = false, multiple = false } = {}) => {
    wrapper = shallowMountExtended(DuoCustomAnswerInput, {
      propsData: { draftKey: DRAFT_KEY, inputId: INPUT_ID, disabled, submitting, multiple },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findInput = () => wrapper.findComponentByTestId('duo-custom-answer-input');
  const findSubmit = () => wrapper.findComponentByTestId('duo-custom-answer-submit');
  const findCheckbox = () => wrapper.findComponentByTestId('duo-custom-answer-checkbox');
  const setCustomAnswer = (text) => findInput().vm.$emit('input', text);
  const clickSubmit = () => findSubmit().vm.$emit('click');
  // Enter reaches the handler even when the button is disabled, so the two paths are
  // not equally reachable and both are worth covering.
  const pressEnter = () =>
    findInput().vm.$emit('keydown', new KeyboardEvent('keydown', { key: 'Enter' }));
  const submit = async (text, via = clickSubmit) => {
    await setCustomAnswer(text);
    await via();
  };

  beforeEach(() => createComponent());

  it('labels the input for screen readers, since the placeholder is not a label', () => {
    expect(wrapper.find('label').attributes('for')).toBe(INPUT_ID);
    expect(wrapper.find('label').text()).toBe('Answer in your own words');
  });

  it.each`
    answer               | text                  | disabled
    ${'empty'}           | ${''}                 | ${true}
    ${'only spaces'}     | ${'   '}              | ${true}
    ${'something typed'} | ${RATIONALE}          | ${false}
    ${'padded'}          | ${`  ${RATIONALE}  `} | ${false}
  `('submit is disabled=$disabled while the answer is $answer', async ({ text, disabled }) => {
    await setCustomAnswer(text);

    expect(findSubmit().props('disabled')).toBe(disabled);
  });

  // A lone icon does not say why it cannot be pressed. `GlButton` renders `aria-disabled`
  // rather than `disabled`, so it keeps hover and keyboard focus and the tooltip is
  // reachable either way.
  it.each`
    state            | text         | tooltip
    ${'an unusable'} | ${''}        | ${'An answer is required to submit'}
    ${'a ready'}     | ${RATIONALE} | ${''}
  `('explains $state answer through the submit tooltip', async ({ text, tooltip }) => {
    await setCustomAnswer(text);

    expect(getBinding(findSubmit().element, 'gl-tooltip').value).toBe(tooltip);
    // The name stays the action, so the reason is heard as a description, not twice.
    expect(findSubmit().attributes('aria-label')).toBe('Send answer');
  });

  it.each`
    scenario                    | text                  | via
    ${'submitted with a click'} | ${RATIONALE}          | ${clickSubmit}
    ${'submitted with Enter'}   | ${RATIONALE}          | ${pressEnter}
    ${'padded with whitespace'} | ${`  ${RATIONALE}  `} | ${clickSubmit}
  `('emits the trimmed answer when $scenario', async ({ text, via }) => {
    await submit(text, via);

    expect(wrapper.emitted('submit')).toEqual([[RATIONALE]]);
  });

  it.each`
    path         | via
    ${'a click'} | ${clickSubmit}
    ${'Enter'}   | ${pressEnter}
  `('emits nothing when only whitespace is submitted via $path', async ({ via }) => {
    await submit('   ', via);

    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  // `parseDuoAnswer` takes the first marker in the body, so a marker typed into the
  // answer would otherwise be read back instead of the one the poster appends.
  it.each`
    placement                 | typed
    ${'at the start'}         | ${`<!-- duo-answer: staged --> ${RATIONALE}`}
    ${'stacked with another'} | ${`<!-- duo-answer: x --><!-- duo-answer: staged --> ${RATIONALE}`}
    ${'at the end'}           | ${`${RATIONALE} <!-- duo-answer: staged -->`}
    ${'on either side'}       | ${`<!-- duo-answer: x --> ${RATIONALE} <!-- duo-answer: staged -->`}
  `('strips a marker $placement before emitting', async ({ typed }) => {
    await submit(typed);

    expect(wrapper.emitted('submit')).toEqual([[RATIONALE]]);
  });

  it.each`
    count            | text
    ${'one marker'}  | ${'<!-- duo-answer: staged -->'}
    ${'two markers'} | ${'<!-- duo-answer: x --><!-- duo-answer: staged -->'}
  `('keeps submit disabled when $count is all that was typed', async ({ text }) => {
    await setCustomAnswer(text);

    expect(findSubmit().props('disabled')).toBe(true);
  });

  describe('the draft', () => {
    it('restores a half-written answer, so a reload does not lose it', () => {
      localStorage.setItem(AUTOSAVE_KEY, RATIONALE);
      createComponent();

      expect(findInput().props('value')).toBe(RATIONALE);
    });

    it('saves the answer as it is typed, under the key it was given', async () => {
      await setCustomAnswer(RATIONALE);

      expect(localStorage.getItem(AUTOSAVE_KEY)).toBe(RATIONALE);
    });

    it('keeps the draft on submit, since only a posted answer should discard it', async () => {
      await submit(RATIONALE);

      expect(localStorage.getItem(AUTOSAVE_KEY)).toBe(RATIONALE);
    });
  });

  describe('while the answer is being posted', () => {
    beforeEach(() => createComponent({ disabled: true, submitting: true }));

    it('disables the input and shows the button as loading', () => {
      expect(findInput().props('disabled')).toBe(true);
      expect(findSubmit().props('loading')).toBe(true);
      expect(findSubmit().props('disabled')).toBe(true);
    });
  });

  // A question that accepts several answers collects this one with the options and sends
  // the set together, so there is a checkbox here and the send button goes away.
  describe('when the question accepts several answers', () => {
    beforeEach(() => createComponent({ multiple: true }));

    it('offers a checkbox instead of a send button', () => {
      expect(findCheckbox().exists()).toBe(true);
      expect(findSubmit().exists()).toBe(false);
    });

    // Two controls in one row, so they cannot share a name: the box selects the answer,
    // the input holds it.
    it('names the checkbox apart from the input it selects', () => {
      expect(findCheckbox().text()).toBe('Include your answer');
      expect(wrapper.find(`label[for="${INPUT_ID}"]`).text()).toBe('Answer in your own words');
    });

    it('counts a restored draft straight away, rather than waiting for a keystroke', () => {
      localStorage.setItem(AUTOSAVE_KEY, RATIONALE);
      createComponent({ multiple: true });

      expect(findInput().props('value')).toBe(RATIONALE);
      expect(findCheckbox().props('checked')).toBe(true);
      expect(wrapper.emitted('change').at(-1)).toEqual([RATIONALE]);
    });

    it('reports the answer as typed, so the note can send it with the ticked options', async () => {
      await setCustomAnswer(RATIONALE);

      expect(wrapper.emitted('change').at(-1)).toEqual([RATIONALE]);
    });

    // Ticking and typing both change what this row contributes, so reporting from each
    // in turn would tell the note the same thing twice.
    it('reports once per change, not once per cause', async () => {
      const atStart = wrapper.emitted('change').length;

      await setCustomAnswer(RATIONALE);
      expect(wrapper.emitted('change').length - atStart).toBe(1);

      await findCheckbox().vm.$emit('input', false);
      expect(wrapper.emitted('change').length - atStart).toBe(2);
    });

    // A ticked box that is also disabled reads as "this empty answer still counts", so
    // clearing the text has to untick as well as disable.
    it('unticks when the text is cleared, rather than leaving a ticked disabled box', async () => {
      await setCustomAnswer(RATIONALE);

      expect(findCheckbox().props('checked')).toBe(true);
      expect(findCheckbox().props('disabled')).toBe(false);

      await setCustomAnswer('');

      expect(findCheckbox().props('checked')).toBe(false);
      expect(findCheckbox().props('disabled')).toBe(true);
      expect(wrapper.emitted('change').at(-1)).toEqual(['']);
    });

    it('reports nothing once unticked, keeping the text for a change of mind', async () => {
      await setCustomAnswer(RATIONALE);
      await findCheckbox().vm.$emit('input', false);

      expect(wrapper.emitted('change').at(-1)).toEqual(['']);
      expect(findInput().props('value')).toBe(RATIONALE);
    });

    // Correcting a typo is not a decision to include the answer again, so an explicit
    // uncheck has to survive further editing.
    it('stays unticked while the excluded text is edited', async () => {
      await setCustomAnswer(RATIONALE);
      await findCheckbox().vm.$emit('input', false);
      await setCustomAnswer(`${RATIONALE} and one more thought`);

      expect(findCheckbox().props('checked')).toBe(false);
      expect(wrapper.emitted('change').at(-1)).toEqual(['']);
    });

    it('ticks again once the text is cleared and something new is typed', async () => {
      await setCustomAnswer(RATIONALE);
      await findCheckbox().vm.$emit('input', false);
      await setCustomAnswer('');
      await setCustomAnswer('A fresh answer');

      expect(findCheckbox().props('checked')).toBe(true);
      expect(wrapper.emitted('change').at(-1)).toEqual(['A fresh answer']);
    });

    it('never emits submit, since the note sends the whole set', async () => {
      await setCustomAnswer(RATIONALE);
      await pressEnter();

      expect(wrapper.emitted('submit')).toBeUndefined();
    });
  });
});
