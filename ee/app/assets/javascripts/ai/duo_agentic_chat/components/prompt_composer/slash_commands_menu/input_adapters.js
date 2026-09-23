import getCaretCoordinates from 'textarea-caret';

// Used when a line height cannot be measured (`line-height: normal` parses to NaN).
const FALLBACK_CARET_HEIGHT = 16;

const TEXT_INPUT_TAGS = ['TEXTAREA'];

/**
 * Adapters isolate the menu from the kind of element it is driving. Each one
 * answers the same three questions: what is the text, where is the collapsed
 * caret within it, and where does a given offset sit on screen. Caret rects are
 * in viewport coordinates.
 *
 * Only <textarea> is supported today. Adding <input> or a contenteditable
 * adapter would slot in here without the menu itself changing — for
 * contenteditable that means reading `textContent`, deriving the caret offset
 * from `window.getSelection()`, and measuring a `Range` rect.
 */
const textInputAdapter = (element) => ({
  element,

  getText() {
    return element.value;
  },

  hasTextSelection() {
    return element.selectionStart !== element.selectionEnd;
  },

  getCaretOffset() {
    return element.selectionStart;
  },

  getCaretRect(offset) {
    // Measured against a mirror element, which reports coordinates relative to
    // the element's border box rather than the viewport.
    const caret = getCaretCoordinates(element, offset);
    const box = element.getBoundingClientRect();

    return {
      top: box.top + caret.top - element.scrollTop,
      left: box.left + caret.left - element.scrollLeft,
      height: caret.height || FALLBACK_CARET_HEIGHT,
    };
  },
});

export const createInputAdapter = (element) => {
  if (!TEXT_INPUT_TAGS.includes(element.tagName)) {
    /* eslint-disable @gitlab/require-i18n-strings -- developer-facing, never rendered */
    throw new Error(
      `SlashCommandsMenu: no input adapter for <${element.tagName.toLowerCase()}>. ` +
        `Supported elements: ${TEXT_INPUT_TAGS.join(', ')}.`,
    );
    /* eslint-enable @gitlab/require-i18n-strings */
  }

  return textInputAdapter(element);
};
