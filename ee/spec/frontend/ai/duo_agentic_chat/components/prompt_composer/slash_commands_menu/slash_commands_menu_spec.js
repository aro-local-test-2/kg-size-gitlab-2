import { GlDisclosureDropdownItem } from '@gitlab/ui';
import { nextTick } from 'vue';
import { computePosition } from '@floating-ui/dom';
import getCaretCoordinates from 'textarea-caret';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { ignoreConsoleMessages } from 'helpers/console_watcher';
import SlashCommandsMenu from 'ee/ai/duo_agentic_chat/components/prompt_composer/slash_commands_menu/slash_commands_menu.vue';

// jsdom does no layout, so the real implementation would return NaN and every
// assertion built on it would silently pass.
jest.mock('textarea-caret', () => jest.fn(() => ({ top: 20, left: 8, height: 18 })));

jest.mock('@floating-ui/dom', () => ({
  computePosition: jest.fn().mockResolvedValue({ x: 5, y: 10 }),
  offset: jest.fn(),
  flip: jest.fn(),
  shift: jest.fn(),
}));

// Mirrors production: the shipped commands act on the conversation and so are
// startOnly. `/attach` stands in for a future command that is valid anywhere.
const COMMANDS = [
  { value: '/new', description: 'Start a new conversation', startOnly: true },
  {
    value: '/compact',
    label: 'Compact conversation',
    description: 'Summarize this conversation',
    startOnly: true,
  },
  { value: '/attach', description: 'Attach a file' },
];

const [NEW_COMMAND, , ATTACH_COMMAND] = COMMANDS;

describe('SlashCommandsMenu', () => {
  let wrapper;
  let textarea;

  const createComponent = ({
    value = '',
    commands = COMMANDS,
    isLoading = false,
    disabled = false,
  } = {}) => {
    wrapper = mountExtended(SlashCommandsMenu, {
      attachTo: document.body,
      propsData: { commands, value, isLoading, disabled },
      slots: { default: '<textarea data-testid="textarea"></textarea>' },
    });
    textarea = wrapper.findByTestId('textarea').element;
  };

  const findPanel = () => wrapper.findByTestId('slash-commands-panel');
  const findPanelContainer = () => wrapper.findByTestId('slash-commands-panel-container');
  const findOptions = () => wrapper.findAllComponents(GlDisclosureDropdownItem);

  // The sections the listbox owns: `group` when labelled, `presentation` for the
  // ungrouped one so its options stay owned by the listbox directly.
  const findSections = () => findPanel().findAll('ul[role="group"], ul[role="presentation"]');
  const findLabelledSections = () => findPanel().findAll('ul[role="group"]');
  const findHeading = (section) => findPanel().find(`#${section.attributes('aria-labelledby')}`);
  const optionLabels = () =>
    findOptions().wrappers.map((o) => o.find('.gl-new-dropdown-item-text-wrapper > span').text());

  // Sets the textarea's value and caret, then fires the event the component listens to.
  const type = async (value, caret = value.length, event = 'input') => {
    textarea.value = value;
    textarea.setSelectionRange(caret, caret);
    textarea.dispatchEvent(new Event(event, { bubbles: true }));
    await nextTick();
  };

  const open = async (commands) => {
    createComponent({ commands });
    await type('/');
  };

  const pressKey = (key, options = {}) => {
    const event = new KeyboardEvent('keydown', {
      key,
      bubbles: true,
      cancelable: true,
      ...options,
    });
    textarea.dispatchEvent(event);
    return event;
  };

  describe('opening', () => {
    it('opens when a slash starts the prompt', async () => {
      createComponent();

      await type('/');

      expect(findPanel().exists()).toBe(true);
      expect(findOptions()).toHaveLength(3);
    });

    it('opens for a slash after whitespace', async () => {
      createComponent();

      await type('hello /');

      expect(findPanel().exists()).toBe(true);
    });

    describe('startOnly commands', () => {
      it('offers them when the slash opens the prompt', async () => {
        createComponent();

        await type('/');

        expect(findOptions().wrappers.map((o) => o.text())).toEqual(
          expect.arrayContaining([expect.stringContaining('/new')]),
        );
      });

      it('suppresses them once there is text in front', async () => {
        createComponent();

        await type('hello /');

        const names = findOptions().wrappers.map((o) => o.text());
        expect(names).toHaveLength(1);
        expect(names[0]).toContain('/attach');
      });

      // With nothing left to offer there is no menu, rather than an empty panel.
      it('closes when every match is filtered out', async () => {
        createComponent();

        await type('hello /n');

        expect(findPanel().exists()).toBe(false);
      });
    });

    it('opens for a slash typed before the commands arrived', async () => {
      createComponent({ commands: [] });
      await type('/');

      expect(findPanel().exists()).toBe(false);

      await wrapper.setProps({ commands: COMMANDS });

      expect(findPanel().exists()).toBe(true);
      expect(findOptions()).toHaveLength(3);
    });

    // The reason the trigger requires a leading boundary at all.
    it('stays closed for a slash inside a word', async () => {
      createComponent();

      await type('https://gitlab.com');

      expect(findPanel().exists()).toBe(false);
    });

    it('stays closed when the caret is not at the end of the token', async () => {
      createComponent();

      await type('/new more text', 2);

      expect(findPanel().exists()).toBe(false);
    });

    it('stays closed when there is a text selection', async () => {
      createComponent();
      textarea.value = '/n';
      textarea.setSelectionRange(0, 2);
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      await nextTick();

      expect(findPanel().exists()).toBe(false);
    });
  });

  // The composer disables the menu once a flow is selected: picking a command is how a
  // flow gets selected, so there is nothing left to offer and a slash is just text.
  describe('when disabled', () => {
    it('does not open on a slash', async () => {
      createComponent({ disabled: true });

      await type('/');

      expect(findPanel().exists()).toBe(false);
    });

    it('stays shut while commands are still being fetched', async () => {
      createComponent({ disabled: true, commands: [], isLoading: true });

      await type('/');

      expect(findPanel().exists()).toBe(false);
    });

    // Nothing the user types follows, so the panel has to close on the prop alone.
    it('closes a panel that is already open', async () => {
      createComponent();
      await type('/');
      expect(findPanel().exists()).toBe(true);

      await wrapper.setProps({ disabled: true });

      expect(findPanel().exists()).toBe(false);
    });

    // With the panel shut the composer owns the keyboard again, so Enter sends.
    it('leaves Enter to the composer', async () => {
      createComponent({ disabled: true });
      await type('/');

      const event = pressKey('Enter');

      expect(event.defaultPrevented).toBe(false);
    });
  });

  describe('filtering', () => {
    it('narrows the list as the query grows', async () => {
      createComponent();

      await type('/co');

      expect(findOptions()).toHaveLength(1);
      expect(findOptions().at(0).text()).toContain('Compact conversation');
    });

    // The point of a label distinct from the value: the user searches the words
    // they can see, not the token those words insert.
    it('matches a word in a command label', async () => {
      createComponent();

      await type('/conv');

      expect(findOptions()).toHaveLength(1);
      expect(findOptions().at(0).text()).toContain('Compact conversation');
    });

    it('matches a label word that is not the first', async () => {
      createComponent();

      await type('/conv');

      expect(findOptions()).toHaveLength(1);
      expect(findOptions().at(0).text()).toContain('Compact conversation');
    });

    // Mid-word matching would make `/li` pull in every "Pipelines" command.
    it('does not match the middle of a label word', async () => {
      createComponent();

      await type('/versation');

      expect(findPanel().exists()).toBe(false);
    });

    it('closes when nothing matches', async () => {
      createComponent();

      await type('/zzz');

      expect(findPanel().exists()).toBe(false);
    });

    // Otherwise Enter would re-select instead of sending the finished command.
    it('closes once the token is exactly a command', async () => {
      createComponent();

      await type('/new');

      expect(findPanel().exists()).toBe(false);
    });
  });

  describe('the `commands` contract', () => {
    const { validator } = SlashCommandsMenu.props.commands;

    it('accepts commands and groups side by side', () => {
      expect(
        validator([
          { value: '/plain', description: 'Ungrouped' },
          { label: 'Quality', order: 10, items: [{ value: '/lint', description: 'Lint' }] },
        ]),
      ).toBe(true);
    });

    // A provider with nothing to offer in this context is not a malformed one.
    it('accepts a group with no items', () => {
      expect(validator([{ label: 'Quality', items: [] }])).toBe(true);
    });

    // Only `value` is required of a command: a label is optional, and a missing
    // one falls back to the value when the row renders.
    it('accepts a command with no label', () => {
      expect(validator([{ value: '/plain' }])).toBe(true);
    });

    it.each([
      ['a command with no value', [{ description: 'no value' }]],
      ['a command whose value is not a string', [{ value: 7 }]],
      ['a group with no label', [{ items: [{ value: '/lint' }] }]],
      ['a group labelled with whitespace', [{ label: '   ', items: [{ value: '/lint' }] }]],
      ['a group whose label is not a string', [{ label: 7, items: [{ value: '/lint' }] }]],
      ['a group holding a valueless command', [{ label: 'Quality', items: [{ text: 'nope' }] }]],
      ['a null entry', [null]],
      ['a value that is not an array', 'not an array'],
    ])('rejects %s', (_, commands) => {
      expect(validator(commands)).toBe(false);
    });
  });

  describe('grouping', () => {
    const DEPLOY = { value: '/deploy', description: 'Deploy' };
    const RETRY = { value: '/retry', description: 'Retry' };
    const LINT = { value: '/lint', description: 'Lint' };
    const PLAIN = { value: '/plain', description: 'Belongs nowhere' };

    // Valid anywhere, so a bare `/` offers all of them and the render order is
    // entirely down to the grouping. The two Pipelines groups stand in for two
    // plugins contributing to one section.
    const ENTRIES = [
      { label: 'Pipelines', order: 20, items: [DEPLOY] },
      PLAIN,
      { label: 'Code', order: 10, items: [LINT] },
      { label: 'Pipelines', order: 20, items: [RETRY] },
    ];

    it('reads a group as a section and a bare command as ungrouped', async () => {
      await open(ENTRIES);

      expect(findSections()).toHaveLength(3);
      expect(findLabelledSections()).toHaveLength(2);
      expect(optionLabels()).toHaveLength(4);
    });

    it('lists ungrouped commands first, then each group in `order`', async () => {
      await open(ENTRIES);

      expect(optionLabels()).toEqual(['/plain', '/lint', '/deploy', '/retry']);
    });

    it('merges groups that share a label into one section', async () => {
      await open(ENTRIES);

      expect(findSections().at(2).findAll('[role="option"]')).toHaveLength(2);
    });

    // Otherwise the second plugin to reach a section could drag it in front of
    // one the user has already learned the position of.
    it('leaves the position of a merged section to the group that opened it', async () => {
      await open([
        { label: 'Pipelines', order: 20, items: [DEPLOY] },
        { label: 'Code', order: 30, items: [LINT] },
        { label: 'Pipelines', order: 1, items: [RETRY] },
      ]);

      expect(optionLabels()).toEqual(['/deploy', '/retry', '/lint']);
    });

    // Otherwise a plugin that omits `order` would jump ahead of, or behind, the
    // groups declared before it depending on Map iteration.
    it('keeps groups without an `order` in the order the plugins offered them', async () => {
      await open([
        { label: 'Second', items: [{ value: '/b', description: 'Second' }] },
        { label: 'First', items: [{ value: '/a', description: 'First' }] },
      ]);

      expect(findLabelledSections().wrappers.map((section) => findHeading(section).text())).toEqual(
        ['Second', 'First'],
      );
    });

    // Naming the section is a way of asking for what is in it, so the items are
    // offered whether or not they match the query themselves.
    it('offers everything in a group whose label matches', async () => {
      createComponent({ commands: ENTRIES });

      await type('/pipe');

      expect(optionLabels()).toEqual(['/deploy', '/retry']);
      expect(findLabelledSections().wrappers.map((section) => findHeading(section).text())).toEqual(
        ['Pipelines'],
      );
    });

    // Otherwise naming a section would smuggle in commands the prompt cannot
    // take at this position.
    it('still holds back startOnly commands when the group label matches', async () => {
      const commands = [
        {
          label: 'Pipelines',
          items: [DEPLOY, { value: '/demo-reset', description: 'Reset', startOnly: true }],
        },
      ];
      createComponent({ commands });

      await type('hello /pipe');

      expect(optionLabels()).toEqual(['/deploy']);
    });

    // Only `value` is validated, so a label of the wrong type reaches the menu
    // and would otherwise throw inside a computed on every keystroke.
    it.each([null, 7, {}])('survives a command label of %p', async (label) => {
      await open([{ value: '/demo-typed', label, description: 'Odd label' }]);

      expect(optionLabels()).toEqual(['/demo-typed']);
    });

    // A heading is prose a plugin picks, so it can be anything the ungrouped
    // section's own key might have been spelled as.
    it('keeps a group labelled like the ungrouped section apart from it', async () => {
      await open([PLAIN, { label: 'ungrouped', items: [LINT] }]);

      expect(findSections()).toHaveLength(2);
      expect(findLabelledSections().wrappers.map((section) => findHeading(section).text())).toEqual(
        ['ungrouped'],
      );
      expect(optionLabels()).toEqual(['/plain', '/lint']);
    });

    // The `commands` validator is what reports these; the render path only has
    // to not break, so the group goes the same way the capability sends it.
    describe('a group with no usable heading', () => {
      ignoreConsoleMessages([/^\[Vue warn\]: Invalid prop/]);

      it.each(['', '   ', undefined, 7])('drops a group labelled %p', async (label) => {
        await open([PLAIN, { label, items: [LINT] }]);

        expect(findSections()).toHaveLength(1);
        expect(findLabelledSections()).toHaveLength(0);
        expect(optionLabels()).toEqual(['/plain']);
      });
    });

    it('trims a section heading rather than rendering the padding', async () => {
      await open([{ label: '  Quality  ', items: [LINT] }]);

      expect(findHeading(findLabelledSections().at(0)).text()).toBe('Quality');
    });

    // `toSections` used to hold the first group's `items` array and push the
    // second group's commands into it.
    it('does not write the merged commands back into the entries', async () => {
      const pipelines = { label: 'Pipelines', order: 20, items: [DEPLOY] };
      await open([pipelines, { label: 'Pipelines', order: 20, items: [RETRY] }]);

      expect(optionLabels()).toEqual(['/deploy', '/retry']);
      expect(pipelines.items).toEqual([DEPLOY]);
    });

    // A group whose every command was filtered out would otherwise render as a
    // heading with nothing under it.
    it('drops a section the query has emptied', async () => {
      createComponent({ commands: ENTRIES });

      await type('/li');

      expect(findLabelledSections().wrappers.map((section) => findHeading(section).text())).toEqual(
        ['Code'],
      );
    });

    it('names each labelled section so its options read as a set', async () => {
      await open(ENTRIES);

      const heading = findHeading(findLabelledSections().at(0));

      expect(heading.text()).toBe('Code');
      // Presentational, so the heading is not itself an option of the listbox.
      expect(heading.attributes('role')).toBe('presentation');
    });

    // A listbox may only own options and groups, so the wrapper around the
    // ungrouped commands has to disappear from the accessibility tree.
    it('does not wrap the ungrouped commands in a group', async () => {
      await open(ENTRIES);

      const ungrouped = findSections().at(0);

      expect(ungrouped.attributes('role')).toBe('presentation');
      expect(ungrouped.attributes('aria-labelledby')).toBeUndefined();
      expect(findOptions().at(0).element.closest('[role="group"]')).toBe(null);
    });

    // What separates one section from the next visually, since the panel has no
    // dividers of its own.
    it('rules off every section but the first', async () => {
      await open(ENTRIES);

      expect(findSections().wrappers.map((section) => section.classes('gl-border-t-1'))).toEqual([
        false,
        true,
        true,
      ]);
    });

    it('walks the options in render order, across group boundaries', async () => {
      await open(ENTRIES);

      pressKey('ArrowUp');
      await nextTick();

      expect(findOptions().at(3).classes()).toContain('gl-new-dropdown-item-highlighted');
    });

    it('selects the command the render order points at, not the given order', async () => {
      await open(ENTRIES);

      pressKey('ArrowDown');
      pressKey('Enter');

      expect(wrapper.emitted('select')[0][0]).toEqual(LINT);
    });

    // The token is complete once it names a command, wherever that command sits.
    it('closes on an exact match with a command inside a group', async () => {
      createComponent({ commands: ENTRIES });

      await type('/lint');

      expect(findPanel().exists()).toBe(false);
    });
  });

  describe('closing', () => {
    beforeEach(async () => {
      createComponent();
      await type('/');
    });

    it('closes on Escape', async () => {
      pressKey('Escape');
      await nextTick();

      expect(findPanel().exists()).toBe(false);
    });

    it('closes when composition starts', async () => {
      textarea.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
      await nextTick();

      expect(findPanel().exists()).toBe(false);
    });

    it('closes when focus leaves the component', async () => {
      textarea.dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: null }));
      await nextTick();

      expect(findPanel().exists()).toBe(false);
    });

    it('closes when the caret moves away by click', async () => {
      await type('/', 0, 'click');

      expect(findPanel().exists()).toBe(false);
    });

    // setPromptAndFocus() writes through v-model and fires no native input
    // event, so the prop watcher is the only thing that notices.
    it('closes when the prompt is changed programmatically', async () => {
      await wrapper.setProps({ value: '/' });
      textarea.value = '';
      textarea.setSelectionRange(0, 0);

      await wrapper.setProps({ value: '' });
      await nextTick();

      expect(findPanel().exists()).toBe(false);
    });
  });

  describe('keyboard navigation', () => {
    beforeEach(async () => {
      createComponent();
      await type('/');
    });

    it('moves the active option down and wraps', async () => {
      pressKey('ArrowDown');
      await nextTick();
      expect(textarea.getAttribute('aria-activedescendant')).toContain('option-1');

      pressKey('ArrowDown');
      pressKey('ArrowDown');
      await nextTick();
      expect(textarea.getAttribute('aria-activedescendant')).toContain('option-0');
    });

    it('moves the active option up and wraps', async () => {
      pressKey('ArrowUp');
      await nextTick();

      expect(textarea.getAttribute('aria-activedescendant')).toContain('option-2');
    });

    it('keeps focus on the textarea', () => {
      textarea.focus();
      pressKey('ArrowDown');

      expect(document.activeElement).toBe(textarea);
    });

    it.each(['Enter', 'Tab'])('selects the active command on %s', (key) => {
      const event = pressKey(key);

      expect(wrapper.emitted('select')[0][0]).toEqual(NEW_COMMAND);
      expect(event.defaultPrevented).toBe(true);
    });

    it('reports the matched range alongside the command', async () => {
      await type('hello /at');

      pressKey('Enter');

      expect(wrapper.emitted('select')[0][0]).toEqual(ATTACH_COMMAND);
      expect(wrapper.emitted('select')[0][1]).toEqual({ triggerIndex: 6, token: '/at' });
    });

    // The composer sends on Enter *keyup*, so consuming only the keydown would
    // still let the release through and submit.
    describe('swallowing the paired keyup', () => {
      const pressKeyup = (key) => {
        const event = new KeyboardEvent('keyup', { key, bubbles: true, cancelable: true });
        textarea.dispatchEvent(event);
        return event;
      };

      it('swallows the release of a key it consumed', () => {
        pressKey('Enter');

        expect(pressKeyup('Enter').defaultPrevented).toBe(true);
      });

      it('lets an unrelated release through', () => {
        pressKey('Enter');

        expect(pressKeyup('a').defaultPrevented).toBe(false);
      });

      // Otherwise a stale mark would eat a later, unrelated press.
      it('only swallows once', () => {
        pressKey('Enter');
        pressKeyup('Enter');

        expect(pressKeyup('Enter').defaultPrevented).toBe(false);
      });

      it('does not swallow when it never consumed a keydown', () => {
        expect(pressKeyup('Enter').defaultPrevented).toBe(false);
      });
    });

    it('does not intercept Shift+Enter', () => {
      const event = pressKey('Enter', { shiftKey: true });

      expect(wrapper.emitted('select')).toBeUndefined();
      expect(event.defaultPrevented).toBe(false);
    });

    it('does not intercept while an IME is composing', () => {
      const event = pressKey('Enter', { isComposing: true });

      expect(wrapper.emitted('select')).toBeUndefined();
      expect(event.defaultPrevented).toBe(false);
    });
  });

  it('does not intercept Enter when closed', () => {
    createComponent();

    const event = pressKey('Enter');

    expect(event.defaultPrevented).toBe(false);
  });

  // The whole point of emitting rather than writing: the parent owns the value.
  it('never mutates the textarea', async () => {
    createComponent();
    const onInput = jest.fn();
    textarea.addEventListener('input', onInput);

    await type('/');
    onInput.mockClear();
    pressKey('Enter');

    expect(textarea.value).toBe('/');
    expect(onInput).not.toHaveBeenCalled();
  });

  describe('option markup', () => {
    beforeEach(async () => {
      createComponent();
      await type('/');
    });

    // GlListboxItem, the obvious choice, always reserves a checkmark gutter
    // because it is built for selectable lists. Nothing here is selectable, so
    // the indent was dead space.
    it('leaves no room for a selection checkmark', () => {
      expect(findPanel().find('[data-testid="dropdown-item-checkbox"]').exists()).toBe(false);
    });

    // ARIA forbids interactive elements inside role="option", which is what the
    // component's own #list-item slot would produce.
    it('puts no interactive element inside an option', () => {
      const option = findOptions().at(0).element;

      expect(option.getAttribute('role')).toBe('option');
      expect(option.querySelector('button, a')).toBe(null);
    });

    it('shows the label, keeping the inserted value out of the row', () => {
      const compact = findOptions().at(1);

      expect(compact.text()).toContain('Compact conversation');
      expect(compact.text()).not.toContain('/compact');
    });

    // Most commands read fine as the token they insert, so a label is optional.
    it('falls back to the value when a command has no label', () => {
      expect(findOptions().at(0).text()).toContain('/new');
    });

    // Catalog descriptions are free-form prose, so the row would wrap without
    // this and swamp the fixed-width panel.
    it('limits the description to a single truncated line', () => {
      const descriptions = findOptions().wrappers.map((o) =>
        o.find('.gl-new-dropdown-item-text-wrapper > p'),
      );

      expect(descriptions).toHaveLength(3);
      descriptions.forEach((description) => {
        expect(description.classes()).toContain('gl-truncate');
      });
    });

    // Choosing a command runs it, so there is no selection state to report.
    // Which row is active is carried by aria-activedescendant instead.
    it('reports no selection state', () => {
      expect(findOptions().wrappers.map((o) => o.attributes('aria-selected'))).toEqual([
        undefined,
        undefined,
        undefined,
      ]);
    });
  });

  // The @gitlab/ui panel styles are nested under .gl-new-dropdown-container, so
  // without that ancestor the panel renders with no background — invisible in
  // light mode, obviously broken in dark mode.
  describe('panel styling', () => {
    it('scopes the panel so the @gitlab/ui dropdown styles apply', async () => {
      createComponent();

      await type('/');

      expect(findPanelContainer().classes()).toContain('gl-new-dropdown-container');
      expect(findPanel().classes()).toEqual(
        expect.arrayContaining(['gl-new-dropdown-panel', '!gl-block']),
      );
    });
  });

  describe('accessibility', () => {
    // Without the role, aria-expanded is a state the input's implicit textbox
    // role does not support, and assistive tech has nothing to attach the
    // popup relationship to.
    it('marks the input as a combobox owning a listbox', () => {
      createComponent();

      expect(textarea.getAttribute('role')).toBe('combobox');
      expect(textarea.getAttribute('aria-haspopup')).toBe('listbox');
    });

    // Watchers only fire on change, so this is the state before the menu has
    // ever opened -- the point at which assistive tech first meets the field.
    it('marks the input as collapsed from the start', () => {
      createComponent();

      expect(textarea.getAttribute('aria-expanded')).toBe('false');
      expect(textarea.getAttribute('aria-activedescendant')).toBeNull();
    });

    it('points aria-activedescendant at a real option', async () => {
      createComponent();

      await type('/');

      const id = textarea.getAttribute('aria-activedescendant');
      expect(document.getElementById(id)).not.toBeNull();
      expect(textarea.getAttribute('aria-controls')).toBe(wrapper.vm.listboxId);
      expect(textarea.getAttribute('aria-expanded')).toBe('true');
    });

    it('clears aria-activedescendant on close so it cannot dangle', async () => {
      createComponent();
      await type('/');

      pressKey('Escape');
      await nextTick();

      expect(textarea.getAttribute('aria-activedescendant')).toBeNull();
      expect(textarea.getAttribute('aria-expanded')).toBe('false');
    });
  });

  it('anchors at the trigger, not the live caret', async () => {
    createComponent();

    await type('hello /at');

    expect(getCaretCoordinates).toHaveBeenCalledWith(textarea, 6);
  });

  it('keeps focus in the textarea when an option is clicked', async () => {
    createComponent();
    await type('/');

    const event = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
    findPanel().element.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
  });

  it('uses fixed strategy to position the dropdown menu', async () => {
    createComponent();
    await type('/');

    expect(computePosition).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      expect.objectContaining({
        strategy: 'fixed',
      }),
    );
    expect(findPanel().classes()).toContain('gl-fixed');
  });

  describe('while commands are still being fetched', () => {
    it('stays open on an empty list, so the trigger does not look ignored', async () => {
      createComponent({ commands: [], isLoading: true });

      await type('/');

      expect(findPanel().exists()).toBe(true);
      expect(wrapper.findByTestId('slash-commands-loading').exists()).toBe(true);
    });

    it('closes once the fetch ends with nothing to offer', async () => {
      createComponent({ commands: [], isLoading: true });
      await type('/');

      await wrapper.setProps({ isLoading: false });

      expect(findPanel().exists()).toBe(false);
    });

    it('shows the commands once they arrive', async () => {
      createComponent({ commands: [], isLoading: true });
      await type('/ne');

      await wrapper.setProps({ commands: COMMANDS, isLoading: false });

      expect(findOptions()).toHaveLength(1);
      expect(wrapper.findByTestId('slash-commands-loading').exists()).toBe(false);
    });

    // The keystroke belongs to the composer while there is nothing to choose: Enter
    // still sends the prompt rather than being silently dropped by the menu.
    it.each(['Enter', 'Tab'])('lets %s through with nothing to choose yet', async (key) => {
      createComponent({ commands: [], isLoading: true });
      await type('/');

      const event = pressKey(key);

      expect(event.defaultPrevented).toBe(false);
      expect(wrapper.emitted('select')).toBeUndefined();
    });

    it('still closes on Escape', async () => {
      createComponent({ commands: [], isLoading: true });
      await type('/');

      pressKey('Escape');
      await nextTick();

      expect(findPanel().exists()).toBe(false);
    });

    it('points aria-activedescendant at nothing until there is an option', async () => {
      createComponent({ commands: [], isLoading: true });
      await type('/');

      expect(textarea.getAttribute('aria-expanded')).toBe('true');
      expect(textarea.getAttribute('aria-activedescendant')).toBeNull();

      await wrapper.setProps({ commands: COMMANDS, isLoading: false });

      const id = textarea.getAttribute('aria-activedescendant');
      expect(document.getElementById(id)).not.toBeNull();
    });

    // Nothing to move between, and the modulo would otherwise produce NaN.
    it('survives the arrow keys with nothing to show yet', async () => {
      createComponent({ commands: [], isLoading: true });
      await type('/');

      pressKey('ArrowDown');
      await nextTick();

      expect(findPanel().exists()).toBe(true);
    });
  });
});
