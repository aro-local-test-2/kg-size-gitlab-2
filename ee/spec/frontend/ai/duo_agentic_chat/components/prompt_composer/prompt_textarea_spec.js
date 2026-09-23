import { GlFormTextarea } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PromptTextarea from 'ee/ai/duo_agentic_chat/components/prompt_composer/prompt_textarea.vue';

describe('PromptTextarea', () => {
  let wrapper;

  const createComponent = ({ propsData = {}, mountFn = mountExtended } = {}) => {
    wrapper = mountFn(PromptTextarea, {
      propsData: { value: '', ...propsData },
    });
  };

  const findTextarea = () => wrapper.findComponent(GlFormTextarea);
  const findNative = () => wrapper.find('textarea');
  const pressKey = (key, options = {}) => findNative().trigger('keyup', { key, ...options });

  describe('rendering', () => {
    it('renders the value it is given', () => {
      createComponent({ propsData: { value: 'hello' } });

      expect(findNative().element.value).toBe('hello');
    });

    it('renders the placeholder it is given', () => {
      createComponent({ propsData: { placeholder: 'Ask away' } });

      expect(findNative().attributes('placeholder')).toBe('Ask away');
    });

    it('disables the input when told to', () => {
      createComponent({ propsData: { disabled: true } });

      expect(findNative().attributes('disabled')).toBeDefined();
    });

    it('limits auto-grow height', () => {
      createComponent({ mountFn: shallowMountExtended });

      expect(findTextarea().props('maxRows')).toBe(20);
    });

    it.each([
      [true, 'true'],
      [false, undefined],
    ])('sets autofocus to %p when the `autofocus` prop is %p', (autofocus, expected) => {
      createComponent({ mountFn: shallowMountExtended, propsData: { autofocus } });

      expect(findTextarea().attributes('autofocus')).toBe(expected);
    });

    // The composer's header row supplies the top spacing when it is there; without
    // it the input has to provide its own, and the min-height floor that keeps the
    // auto-height measurement layout-neutral has to match that padding.
    it.each([
      [false, true],
      [true, false],
    ])('when hasHeaderRow is %p, pads its own top: %p', (hasHeaderRow, padded) => {
      createComponent({ propsData: { hasHeaderRow } });

      expect(findNative().classes().includes('!gl-pt-4')).toBe(padded);
      expect(findNative().classes().includes('agentic-chat-textarea-padded')).toBe(padded);
    });
  });

  describe('character count', () => {
    it.each`
      value                | message
      ${'a'.repeat(16284)} | ${'100 characters remaining.'}
      ${'a'.repeat(16383)} | ${'1 character remaining.'}
      ${'a'.repeat(16384)} | ${'0 characters remaining.'}
      ${'a'.repeat(16385)} | ${'1 character over limit.'}
      ${'a'.repeat(16386)} | ${'2 characters over limit.'}
    `('displays "$message"', ({ value, message }) => {
      createComponent({ propsData: { value } });

      expect(findTextarea().text()).toContain(message);
    });

    it('stays quiet until the prompt approaches the limit', () => {
      createComponent({ propsData: { value: 'short' } });

      expect(findTextarea().text()).toBe('');
    });
  });

  describe('input', () => {
    it('emits what the user typed without holding it', async () => {
      createComponent();

      await findNative().setValue('typed');

      expect(wrapper.emitted('input')).toEqual([['typed']]);
      // The composer owns the draft, so the input only reports the change.
      expect(wrapper.props('value')).toBe('');
    });
  });

  describe('focus', () => {
    it('reports focus coming and going', async () => {
      createComponent();

      await findNative().trigger('focusin');
      await findNative().trigger('focusout');

      expect(wrapper.emitted('focus-change')).toEqual([[true], [false]]);
    });

    it('focuses the input when asked', () => {
      createComponent();
      jest.spyOn(findNative().element, 'focus');

      wrapper.vm.focus();

      expect(findNative().element.focus).toHaveBeenCalled();
    });
  });

  describe('submitting with Enter', () => {
    beforeEach(() => {
      createComponent();
    });

    it('emits submit on a bare Enter', async () => {
      await pressKey('Enter');

      expect(wrapper.emitted('submit')).toHaveLength(1);
    });

    it.each([
      ['⌘', { metaKey: true }],
      ['Ctrl', { ctrlKey: true }],
      ['Alt', { altKey: true }],
      ['Shift', { shiftKey: true }],
    ])('does not submit on Enter + %s', async (_, modifier) => {
      await pressKey('Enter', modifier);

      expect(wrapper.emitted('submit')).toBeUndefined();
    });

    it('does not submit while an IME composition is in flight', async () => {
      await pressKey('Enter', { isComposing: true });

      expect(wrapper.emitted('submit')).toBeUndefined();
    });

    it('swallows the Enter that ends a composition, then submits on the next one', async () => {
      await findNative().trigger('compositionend');

      await pressKey('Enter');
      expect(wrapper.emitted('submit')).toBeUndefined();

      await pressKey('Enter');
      expect(wrapper.emitted('submit')).toHaveLength(1);
    });

    // The menu swallows the keyup that picked a command, so the composer clears the
    // flag itself; otherwise the next Enter is silently discarded.
    it('submits on the next Enter once the composition flag is reset', async () => {
      await findNative().trigger('compositionend');

      wrapper.vm.resetComposition();
      await pressKey('Enter');

      expect(wrapper.emitted('submit')).toHaveLength(1);
    });
  });

  describe('verify all keys are working correctly', () => {
    beforeEach(() => {
      document.execCommand = jest.fn();
      createComponent();
    });

    it.each`
      desc                 | eventOptions                                 | expectedCommand
      ${'a'}               | ${{ key: 'a' }}                              | ${'a'}
      ${'b'}               | ${{ key: 'b' }}                              | ${'b'}
      ${'c'}               | ${{ key: 'c' }}                              | ${'c'}
      ${'d'}               | ${{ key: 'd' }}                              | ${'d'}
      ${'e'}               | ${{ key: 'e' }}                              | ${'e'}
      ${'f'}               | ${{ key: 'f' }}                              | ${'f'}
      ${'g'}               | ${{ key: 'g' }}                              | ${'g'}
      ${'h'}               | ${{ key: 'h' }}                              | ${'h'}
      ${'i'}               | ${{ key: 'i' }}                              | ${'i'}
      ${'j'}               | ${{ key: 'j' }}                              | ${'j'}
      ${'k'}               | ${{ key: 'k' }}                              | ${'k'}
      ${'l'}               | ${{ key: 'l' }}                              | ${'l'}
      ${'m'}               | ${{ key: 'm' }}                              | ${'m'}
      ${'n'}               | ${{ key: 'n' }}                              | ${'n'}
      ${'o'}               | ${{ key: 'o' }}                              | ${'o'}
      ${'p'}               | ${{ key: 'p' }}                              | ${'p'}
      ${'q'}               | ${{ key: 'q' }}                              | ${'q'}
      ${'r'}               | ${{ key: 'r' }}                              | ${'r'}
      ${'s'}               | ${{ key: 's' }}                              | ${'s'}
      ${'t'}               | ${{ key: 't' }}                              | ${'t'}
      ${'u'}               | ${{ key: 'u' }}                              | ${'u'}
      ${'v'}               | ${{ key: 'v' }}                              | ${'v'}
      ${'w'}               | ${{ key: 'w' }}                              | ${'w'}
      ${'x'}               | ${{ key: 'x' }}                              | ${'x'}
      ${'y'}               | ${{ key: 'y' }}                              | ${'y'}
      ${'z'}               | ${{ key: 'z' }}                              | ${'z'}
      ${'A'}               | ${{ key: 'A', shiftKey: true }}              | ${'A'}
      ${'B'}               | ${{ key: 'B', shiftKey: true }}              | ${'B'}
      ${'C'}               | ${{ key: 'C', shiftKey: true }}              | ${'C'}
      ${'D'}               | ${{ key: 'D', shiftKey: true }}              | ${'D'}
      ${'E'}               | ${{ key: 'E', shiftKey: true }}              | ${'E'}
      ${'F'}               | ${{ key: 'F', shiftKey: true }}              | ${'F'}
      ${'G'}               | ${{ key: 'G', shiftKey: true }}              | ${'G'}
      ${'H'}               | ${{ key: 'H', shiftKey: true }}              | ${'H'}
      ${'I'}               | ${{ key: 'I', shiftKey: true }}              | ${'I'}
      ${'J'}               | ${{ key: 'J', shiftKey: true }}              | ${'J'}
      ${'K'}               | ${{ key: 'K', shiftKey: true }}              | ${'K'}
      ${'L'}               | ${{ key: 'L', shiftKey: true }}              | ${'L'}
      ${'M'}               | ${{ key: 'M', shiftKey: true }}              | ${'M'}
      ${'N'}               | ${{ key: 'N', shiftKey: true }}              | ${'N'}
      ${'O'}               | ${{ key: 'O', shiftKey: true }}              | ${'O'}
      ${'P'}               | ${{ key: 'P', shiftKey: true }}              | ${'P'}
      ${'Q'}               | ${{ key: 'Q', shiftKey: true }}              | ${'Q'}
      ${'R'}               | ${{ key: 'R', shiftKey: true }}              | ${'R'}
      ${'S'}               | ${{ key: 'S', shiftKey: true }}              | ${'S'}
      ${'T'}               | ${{ key: 'T', shiftKey: true }}              | ${'T'}
      ${'U'}               | ${{ key: 'U', shiftKey: true }}              | ${'U'}
      ${'V'}               | ${{ key: 'V', shiftKey: true }}              | ${'V'}
      ${'W'}               | ${{ key: 'W', shiftKey: true }}              | ${'W'}
      ${'X'}               | ${{ key: 'X', shiftKey: true }}              | ${'X'}
      ${'Y'}               | ${{ key: 'Y', shiftKey: true }}              | ${'Y'}
      ${'Z'}               | ${{ key: 'Z', shiftKey: true }}              | ${'Z'}
      ${'period'}          | ${{ key: '.' }}                              | ${'.'}
      ${'comma'}           | ${{ key: ',' }}                              | ${','}
      ${'semicolon'}       | ${{ key: ';' }}                              | ${';'}
      ${'apostrophe'}      | ${{ key: "'" }}                              | ${"'"}
      ${'slash'}           | ${{ key: '/' }}                              | ${'/'}
      ${'backslash'}       | ${{ key: '\\' }}                             | ${'\\'}
      ${'bracket left'}    | ${{ key: '[' }}                              | ${'['}
      ${'bracket right'}   | ${{ key: ']' }}                              | ${']'}
      ${'minus'}           | ${{ key: '-' }}                              | ${'-'}
      ${'equals'}          | ${{ key: '=' }}                              | ${'='}
      ${'question mark'}   | ${{ key: '?', shiftKey: true }}              | ${'?'}
      ${'exclamation'}     | ${{ key: '!', shiftKey: true }}              | ${'!'}
      ${'colon'}           | ${{ key: ':', shiftKey: true }}              | ${':'}
      ${'quotes'}          | ${{ key: '"', shiftKey: true }}              | ${'"'}
      ${'less than'}       | ${{ key: '<', shiftKey: true }}              | ${'<'}
      ${'greater than'}    | ${{ key: '>', shiftKey: true }}              | ${'>'}
      ${'underscore'}      | ${{ key: '_', shiftKey: true }}              | ${'_'}
      ${'plus'}            | ${{ key: '+', shiftKey: true }}              | ${'+'}
      ${'paren left'}      | ${{ key: '(', shiftKey: true }}              | ${'('}
      ${'paren right'}     | ${{ key: ')', shiftKey: true }}              | ${')'}
      ${'curly left'}      | ${{ key: '{', shiftKey: true }}              | ${'{'}
      ${'curly right'}     | ${{ key: '}', shiftKey: true }}              | ${'}'}
      ${'pipe'}            | ${{ key: '|', shiftKey: true }}              | ${'|'}
      ${'at symbol'}       | ${{ key: '@', shiftKey: true }}              | ${'@'}
      ${'hash'}            | ${{ key: '#', shiftKey: true }}              | ${'#'}
      ${'dollar'}          | ${{ key: '$', shiftKey: true }}              | ${'$'}
      ${'percent'}         | ${{ key: '%', shiftKey: true }}              | ${'%'}
      ${'caret'}           | ${{ key: '^', shiftKey: true }}              | ${'^'}
      ${'ampersand'}       | ${{ key: '&', shiftKey: true }}              | ${'&'}
      ${'asterisk'}        | ${{ key: '*', shiftKey: true }}              | ${'*'}
      ${'Tab'}             | ${{ key: 'Tab' }}                            | ${'Tab'}
      ${'Escape'}          | ${{ key: 'Escape' }}                         | ${'Escape'}
      ${'Backspace'}       | ${{ key: 'Backspace' }}                      | ${'Backspace'}
      ${'Delete'}          | ${{ key: 'Delete' }}                         | ${'Delete'}
      ${'ArrowUp'}         | ${{ key: 'ArrowUp' }}                        | ${'ArrowUp'}
      ${'ArrowDown'}       | ${{ key: 'ArrowDown' }}                      | ${'ArrowDown'}
      ${'ArrowLeft'}       | ${{ key: 'ArrowLeft' }}                      | ${'ArrowLeft'}
      ${'ArrowRight'}      | ${{ key: 'ArrowRight' }}                     | ${'ArrowRight'}
      ${'Home'}            | ${{ key: 'Home' }}                           | ${'Home'}
      ${'End'}             | ${{ key: 'End' }}                            | ${'End'}
      ${'PageUp'}          | ${{ key: 'PageUp' }}                         | ${'PageUp'}
      ${'PageDown'}        | ${{ key: 'PageDown' }}                       | ${'PageDown'}
      ${'Ctrl+a (Win)'}    | ${{ key: 'a', ctrlKey: true }}               | ${'selectAll'}
      ${'Cmd+a (Mac)'}     | ${{ key: 'a', metaKey: true }}               | ${'selectAll'}
      ${'Ctrl+c (Win)'}    | ${{ key: 'c', ctrlKey: true }}               | ${'copy'}
      ${'Cmd+c (Mac)'}     | ${{ key: 'c', metaKey: true }}               | ${'copy'}
      ${'Ctrl+x (Win)'}    | ${{ key: 'x', ctrlKey: true }}               | ${'cut'}
      ${'Cmd+x (Mac)'}     | ${{ key: 'x', metaKey: true }}               | ${'cut'}
      ${'Ctrl+v (Win)'}    | ${{ key: 'v', ctrlKey: true }}               | ${'paste'}
      ${'Cmd+v (Mac)'}     | ${{ key: 'v', metaKey: true }}               | ${'paste'}
      ${'Ctrl+s (Win)'}    | ${{ key: 's', ctrlKey: true }}               | ${'save'}
      ${'Cmd+s (Mac)'}     | ${{ key: 's', metaKey: true }}               | ${'save'}
      ${'Ctrl+f (Win)'}    | ${{ key: 'f', ctrlKey: true }}               | ${'find'}
      ${'Cmd+f (Mac)'}     | ${{ key: 'f', metaKey: true }}               | ${'find'}
      ${'Ctrl+h (Win)'}    | ${{ key: 'h', ctrlKey: true }}               | ${'replace'}
      ${'Cmd+Alt+f (Mac)'} | ${{ key: 'f', metaKey: true, altKey: true }} | ${'replace'}
      ${'Ctrl+g (Win)'}    | ${{ key: 'g', ctrlKey: true }}               | ${'findNext'}
      ${'Cmd+g (Mac)'}     | ${{ key: 'g', metaKey: true }}               | ${'findNext'}
      ${'Ctrl+b (Win)'}    | ${{ key: 'b', ctrlKey: true }}               | ${'bold'}
      ${'Cmd+b (Mac)'}     | ${{ key: 'b', metaKey: true }}               | ${'bold'}
      ${'Ctrl+i (Win)'}    | ${{ key: 'i', ctrlKey: true }}               | ${'italic'}
      ${'Cmd+i (Mac)'}     | ${{ key: 'i', metaKey: true }}               | ${'italic'}
      ${'Ctrl+u (Win)'}    | ${{ key: 'u', ctrlKey: true }}               | ${'underline'}
      ${'Cmd+u (Mac)'}     | ${{ key: 'u', metaKey: true }}               | ${'underline'}
      ${'Ctrl+k (Win)'}    | ${{ key: 'k', ctrlKey: true }}               | ${'link'}
      ${'Cmd+k (Mac)'}     | ${{ key: 'k', metaKey: true }}               | ${'link'}
      ${'Ctrl+o (Win)'}    | ${{ key: 'o', ctrlKey: true }}               | ${'open'}
      ${'Cmd+o (Mac)'}     | ${{ key: 'o', metaKey: true }}               | ${'open'}
      ${'Ctrl+n (Win)'}    | ${{ key: 'n', ctrlKey: true }}               | ${'new'}
      ${'Cmd+n (Mac)'}     | ${{ key: 'n', metaKey: true }}               | ${'new'}
      ${'Ctrl+p (Win)'}    | ${{ key: 'p', ctrlKey: true }}               | ${'print'}
      ${'Cmd+p (Mac)'}     | ${{ key: 'p', metaKey: true }}               | ${'print'}
      ${'Ctrl+w (Win)'}    | ${{ key: 'w', ctrlKey: true }}               | ${'close'}
      ${'Cmd+w (Mac)'}     | ${{ key: 'w', metaKey: true }}               | ${'close'}
      ${'Ctrl+q (Win)'}    | ${{ key: 'q', ctrlKey: true }}               | ${'quit'}
      ${'Cmd+q (Mac)'}     | ${{ key: 'q', metaKey: true }}               | ${'quit'}
      ${'Ctrl+r (Win)'}    | ${{ key: 'r', ctrlKey: true }}               | ${'refresh'}
      ${'Cmd+r (Mac)'}     | ${{ key: 'r', metaKey: true }}               | ${'refresh'}
      ${'F5'}              | ${{ key: 'F5' }}                             | ${'refresh'}
      ${'Ctrl+d (Win)'}    | ${{ key: 'd', ctrlKey: true }}               | ${'duplicate'}
      ${'Cmd+d (Mac)'}     | ${{ key: 'd', metaKey: true }}               | ${'duplicate'}
      ${'Ctrl+/ (Win)'}    | ${{ key: '/', ctrlKey: true }}               | ${'comment'}
      ${'Cmd+/ (Mac)'}     | ${{ key: '/', metaKey: true }}               | ${'comment'}
      ${'Ctrl+Enter'}      | ${{ key: 'Enter', ctrlKey: true }}           | ${'submit'}
      ${'Cmd+Enter'}       | ${{ key: 'Enter', metaKey: true }}           | ${'submit'}
      ${'Shift+Enter'}     | ${{ key: 'Enter', shiftKey: true }}          | ${'lineBreak'}
      ${'Shift+Tab'}       | ${{ key: 'Tab', shiftKey: true }}            | ${'outdent'}
      ${'Alt+ArrowUp'}     | ${{ key: 'ArrowUp', altKey: true }}          | ${'moveUp'}
      ${'Alt+ArrowDown'}   | ${{ key: 'ArrowDown', altKey: true }}        | ${'moveDown'}
    `('should handle $desc key', async ({ eventOptions, expectedCommand }) => {
      const preventDefaultSpy = jest.fn();
      const stopPropagationSpy = jest.fn();

      await findNative().trigger('keydown', {
        ...eventOptions,
        preventDefault: preventDefaultSpy,
        stopPropagation: stopPropagationSpy,
      });

      expect(preventDefaultSpy).not.toHaveBeenCalled();
      expect(document.execCommand).not.toHaveBeenCalledWith(expectedCommand);

      await findNative().setValue(expectedCommand);
      await pressKey('Enter');

      expect(wrapper.emitted('submit')).toHaveLength(1);
    });
  });

  describe('undo and redo', () => {
    beforeEach(() => {
      document.execCommand = jest.fn();
      createComponent();
    });

    it.each`
      desc                       | eventOptions                                   | expectedCommand
      ${'Ctrl+Z for undo'}       | ${{ key: 'z', ctrlKey: true }}                 | ${'undo'}
      ${'Cmd+Z for undo'}        | ${{ key: 'z', metaKey: true }}                 | ${'undo'}
      ${'Ctrl+Shift+Z for redo'} | ${{ key: 'z', ctrlKey: true, shiftKey: true }} | ${'redo'}
      ${'Cmd+Shift+Z for redo'}  | ${{ key: 'z', metaKey: true, shiftKey: true }} | ${'redo'}
      ${'Ctrl+Y for redo'}       | ${{ key: 'y', ctrlKey: true }}                 | ${'redo'}
      ${'Cmd+Y for redo'}        | ${{ key: 'y', metaKey: true }}                 | ${'redo'}
    `('handles $desc', async ({ eventOptions, expectedCommand }) => {
      await findNative().trigger('keydown', eventOptions);

      expect(document.execCommand).toHaveBeenCalledWith(expectedCommand);
    });
  });
});
