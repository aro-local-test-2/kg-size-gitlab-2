import getCaretCoordinates from 'textarea-caret';
import { createInputAdapter } from 'ee/ai/duo_agentic_chat/components/prompt_composer/slash_commands_menu/input_adapters';

// Measuring the caret needs real layout, which jsdom does not do — unmocked it
// would return NaN and every assertion built on it would silently pass.
jest.mock('textarea-caret', () => jest.fn(() => ({ top: 20, left: 8, height: 18 })));

describe('duo_agentic_chat/prompt_composer/slash_commands_menu/input_adapters', () => {
  let element;

  afterEach(() => {
    element?.remove();
  });

  const appendTextarea = (value = 'hello world') => {
    element = document.createElement('textarea');
    element.value = value;
    document.body.appendChild(element);
    return createInputAdapter(element);
  };

  describe('textarea', () => {
    it('reads the text', () => {
      expect(appendTextarea('abc').getText()).toBe('abc');
    });

    it('reads the caret offset', () => {
      const adapter = appendTextarea();
      element.setSelectionRange(3, 3);

      expect(adapter.getCaretOffset()).toBe(3);
    });

    describe('hasTextSelection', () => {
      it('is false for a collapsed caret', () => {
        const adapter = appendTextarea();
        element.setSelectionRange(3, 3);

        expect(adapter.hasTextSelection()).toBe(false);
      });

      // A range selection is not a caret, so there is nothing to anchor to.
      it('is true while a range is selected', () => {
        const adapter = appendTextarea();
        element.setSelectionRange(0, 4);

        expect(adapter.hasTextSelection()).toBe(true);
      });
    });

    it('converts the mirror measurement into viewport coordinates', () => {
      const adapter = appendTextarea();
      jest.spyOn(element, 'getBoundingClientRect').mockReturnValue({ top: 100, left: 50 });

      expect(adapter.getCaretRect(3)).toEqual({ top: 120, left: 58, height: 18 });
      expect(getCaretCoordinates).toHaveBeenCalledWith(element, 3);
    });

    it('subtracts the element scroll offset', () => {
      const adapter = appendTextarea();
      jest.spyOn(element, 'getBoundingClientRect').mockReturnValue({ top: 100, left: 50 });
      Object.defineProperty(element, 'scrollTop', { value: 5, configurable: true });

      expect(adapter.getCaretRect(3).top).toBe(115);
    });

    it('falls back to a default height when line-height cannot be measured', () => {
      getCaretCoordinates.mockReturnValueOnce({ top: 0, left: 0, height: NaN });
      const adapter = appendTextarea();
      jest.spyOn(element, 'getBoundingClientRect').mockReturnValue({ top: 0, left: 0 });

      expect(adapter.getCaretRect(0).height).toBe(16);
    });
  });

  describe('adapter selection', () => {
    it('drives a textarea', () => {
      expect(appendTextarea('picked').getText()).toBe('picked');
    });

    // Anything else is a deliberate gap. Failing loudly beats silently reading
    // a `value` the element does not have, which would just never open the menu.
    it.each(['div', 'input'])('throws for <%s>, which it cannot drive', (tag) => {
      element = document.createElement(tag);
      document.body.appendChild(element);

      expect(() => createInputAdapter(element)).toThrow(
        `SlashCommandsMenu: no input adapter for <${tag}>. Supported elements: TEXTAREA.`,
      );
    });
  });
});
