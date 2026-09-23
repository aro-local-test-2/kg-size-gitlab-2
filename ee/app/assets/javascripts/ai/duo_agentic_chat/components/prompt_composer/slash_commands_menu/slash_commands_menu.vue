<script>
import { GlDisclosureDropdownItem } from '@gitlab/ui';
import { computePosition, offset, flip, shift } from '@floating-ui/dom';
import { uniqueId } from 'lodash-es';
import { __ } from '~/locale';
import {
  flattenSlashCommands,
  isSlashCommandGroup,
} from '../../../services/plugin_capabilities/slash_commands';
import { createInputAdapter } from './input_adapters';

// A slash opens the menu at the start of the text or after whitespace. The
// leading boundary is what stops a pasted "https://example.com" triggering it.
const TRIGGER_RE = /(?:^|\s)(\/\S*)$/;

// Override via `inputSelector` when the slot holds more than one candidate.
const DEFAULT_INPUT_SELECTOR = 'textarea';

const DEFAULT_GROUP_ORDER = 0;

const SECTION_DIVIDER_CLASSES = [
  'gl-border-t-1',
  'gl-border-t-solid',
  'gl-border-t-dropdown-divider',
  'gl-pt-1',
  'gl-mt-2',
];

// Only `value` is validated, so a label is whatever the caller supplied. One rule
// for the whole component: a label is a non-blank string, and anything else is
// absent rather than rendered, searched, or treated as a section heading. The
// capability layer applies the same rule to plugin contributions.
const labelText = (label) => (typeof label === 'string' ? label.trim() : '');

const isCommand = (entry) => typeof entry?.value === 'string';

/**
 * The contract the panel can render: a bare command needs a value to insert, and
 * a group needs a heading to sit under plus commands that are themselves valid.
 * An empty `items` is allowed -- a provider with nothing to offer in the current
 * context is not a malformed one.
 *
 * @param {unknown} entry
 * @returns {boolean}
 */
const isRenderableEntry = (entry) =>
  isSlashCommandGroup(entry)
    ? Boolean(labelText(entry.label)) && entry.items.every(isCommand)
    : isCommand(entry);

/**
 * Lays the provided entries out as the sections the panel renders, in render
 * order: the commands belonging to no group first, as a headingless section,
 * then one section per group label, sorted by `order`. Groups left with no
 * matching command, and the headingless section when empty, are dropped rather
 * than rendered as a bare heading.
 *
 * @param {Object[]} entries - Commands and groups that survived the query.
 * @returns {{ key: string, label: ?string, commands: Object[] }[]}
 */
function toSections(entries) {
  const ungrouped = [];
  const byLabel = new Map();

  entries.forEach((entry) => {
    if (!isSlashCommandGroup(entry)) {
      ungrouped.push(entry);
      return;
    }

    // Not a section without a heading, so it is dropped whole -- the same
    // recovery the capability layer applies, where it can also name the plugin
    // responsible. The `commands` validator is what makes this loud in
    // development; this branch only keeps the render from breaking.
    const label = labelText(entry.label);
    if (!label) return;

    // Copied, so merging a second group into this section cannot write back
    // into the caller's array.
    const commands = [...entry.items];
    const section = byLabel.get(label);

    // The plugin that opens a section fixes where it sits; later ones only add
    // to it, so a plugin cannot drag an existing section around by its order.
    if (section) {
      section.commands.push(...commands);
    } else {
      byLabel.set(label, {
        // Namespaced so no heading text, which is prose a plugin chooses, can
        // collide with the ungrouped section's key.
        key: `group:${label}`,
        label,
        order: entry.order ?? DEFAULT_GROUP_ORDER,
        commands,
      });
    }
  });

  // Sort is stable, so groups given the same order keep the order the plugins
  // were asked in.
  const grouped = [...byLabel.values()].sort((a, b) => a.order - b.order);

  return ungrouped.length
    ? [{ key: 'ungrouped', label: null, commands: ungrouped }, ...grouped]
    : grouped;
}

/**
 * Attaches a slash-command suggestion menu to a slotted text input, in the style
 * of vue-mention's Mentionable.
 *
 * The input is supplied by the caller through the default slot, so this
 * component never owns that vnode and cannot bind to it in the template. It
 * finds the node and attaches native listeners instead. Reading text and caret
 * position goes through an adapter (see input_adapters.js), so this component
 * holds no assumptions about the element type; supporting a contenteditable
 * later means adding an adapter, not changing anything here.
 *
 * Everything it observes is read-only: it never writes the input's content, and
 * applying a command is the parent's job via the `select` event.
 */
export default {
  name: 'SlashCommandsMenu',
  components: { GlDisclosureDropdownItem },
  props: {
    /**
     * Commands and groups of commands, as the plugins provided them. See
     * `SlashCommandEntry` in services/plugin_capabilities/slash_commands.js.
     */
    commands: {
      type: Array,
      required: true,
      validator: (commands) => Array.isArray(commands) && commands.every(isRenderableEntry),
    },
    /**
     * The current prompt. Needed because the parent can change it through
     * v-model, which fires no native input event and would leave us stale.
     */
    value: {
      type: String,
      required: true,
    },
    /**
     * CSS selector locating the editable element inside the default slot.
     */
    inputSelector: {
      type: String,
      required: false,
      default: DEFAULT_INPUT_SELECTOR,
    },
    /**
     * Stops the menu offering anything at all. Set when the caller already holds what
     * picking a command would set, so a slash in what the user is writing is just text.
     */
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Keeps the menu open on an empty list while commands are still being fetched,
     * so a trigger does not look like it did nothing.
     */
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select'],
  data() {
    return {
      isOpen: false,
      activeIndex: 0,
      query: '',
      triggerIndex: 0,
      listboxId: uniqueId('slash-commands-listbox-'),
    };
  },
  computed: {
    allCommands() {
      return flattenSlashCommands(this.commands);
    },
    // What the query keeps, kept apart from the layout below: which commands
    // survive is a different question from where they end up.
    matchingEntries() {
      const query = this.query.toLowerCase();
      // The typed token carries the slash. Labels do not, so they are searched
      // with it stripped.
      const term = query.slice(1);
      // A `startOnly` command acts on the whole prompt, so offering it after
      // other text would produce something the parent cannot sensibly apply.
      const isPromptStart = this.triggerIndex === 0;

      const isOfferable = (command) => isPromptStart || !command.startOnly;
      // Labels are prose, so the term is matched against the start of any word
      // in them rather than the whole string. Matching mid-word instead would
      // let `/li` pull in a "Pipelines" section nobody asked for.
      const anyWordStartsWithTerm = (label) =>
        labelText(label)
          .toLowerCase()
          .split(/\s+/)
          .some((word) => word.startsWith(term));
      // The value is the token being completed, so it matches by prefix.
      const matchesCommand = (command) =>
        command.value.toLowerCase().startsWith(query) || anyWordStartsWithTerm(command.label);

      return this.commands.flatMap((entry) => {
        if (!isSlashCommandGroup(entry)) {
          return isOfferable(entry) && matchesCommand(entry) ? [entry] : [];
        }

        // Naming the section offers everything in it: the user has picked the
        // group, not a command inside it.
        const keepsEverything = anyWordStartsWithTerm(entry.label);
        const items = entry.items.filter(
          (command) => isOfferable(command) && (keepsEverything || matchesCommand(command)),
        );

        return items.length ? [{ ...entry, items }] : [];
      });
    },
    // Carries the index each section starts at in `filteredCommands`, so an
    // option can name its own flat index without the template counting rows.
    commandSections() {
      let startIndex = 0;

      return toSections(this.matchingEntries).map((section) => {
        const positioned = { ...section, startIndex };
        startIndex += section.commands.length;
        return positioned;
      });
    },
    // Render order, which is what arrow keys and aria-activedescendant follow.
    filteredCommands() {
      return this.commandSections.flatMap(({ commands }) => commands);
    },
    activeCommand() {
      return this.filteredCommands[this.activeIndex];
    },
  },
  watch: {
    // The commands can arrive after the user has typed the slash that needs them: the
    // keystroke found nothing to offer, and there is no later event to re-derive from.
    // Not conditional on the panel being open for that reason.
    commands() {
      this.evaluate();
    },
    value() {
      // The DOM has not patched yet, so the caret is still where it was.
      this.$nextTick(this.evaluate);
    },
    // Same reason as `commands`: the panel has to close once a fetch ends with
    // nothing to show, and open while one is still running.
    isLoading() {
      this.evaluate();
    },
    // Closes a panel that is already open when the caller takes its answer some other
    // way, which no input event would follow.
    disabled() {
      this.evaluate();
    },
    isOpen(isOpen) {
      this.syncAriaAttributes();
      if (isOpen) this.$nextTick(this.reposition);
    },
    // The index does not move when commands arrive into an open, empty list.
    activeCommand() {
      this.syncAriaAttributes();
    },
    activeIndex() {
      this.$nextTick(this.scrollActiveIntoView);
    },
  },
  mounted() {
    const inputEl = this.$el.querySelector(this.inputSelector);
    if (!inputEl) return;

    // Keystroke that should be consumed by the slash commands menu so the prompt composer doesn't react to it.
    this.swallowKeyup = null;

    this.adapter = createInputAdapter(inputEl);
    this.inputEl = inputEl;

    // Marks the input as the combobox that owns the suggestion list. Static
    // for the input's lifetime, unlike the state syncAriaAttributes tracks.
    this.inputEl.setAttribute('role', 'combobox');
    this.inputEl.setAttribute('aria-haspopup', 'listbox');

    // Watchers only fire on change, so without this the input carries no
    // aria-expanded until the menu first opens and assistive tech has no way to
    // know the field can expand a list at all.
    this.syncAriaAttributes();

    // Capture on the wrapper root, not the input: listeners on the event target
    // fire in registration order regardless of the capture flag, so an ancestor
    // is the only placement guaranteed to run before the composer's own
    // `.native` handlers.
    this.$el.addEventListener('keydown', this.onKeydown, true);
    this.$el.addEventListener('keyup', this.onKeyup, true);

    this.inputEl.addEventListener('input', this.evaluate);
    this.inputEl.addEventListener('keyup', this.evaluate);
    this.inputEl.addEventListener('click', this.evaluate);
    this.inputEl.addEventListener('scroll', this.onScroll);
    this.inputEl.addEventListener('focusout', this.onFocusout);
    this.inputEl.addEventListener('compositionstart', this.close);
  },
  beforeDestroy() {
    this.$el.removeEventListener('keydown', this.onKeydown, true);
    this.$el.removeEventListener('keyup', this.onKeyup, true);
    if (!this.inputEl) return;

    this.inputEl.removeEventListener('input', this.evaluate);
    this.inputEl.removeEventListener('keyup', this.evaluate);
    this.inputEl.removeEventListener('click', this.evaluate);
    this.inputEl.removeEventListener('scroll', this.onScroll);
    this.inputEl.removeEventListener('focusout', this.onFocusout);
    this.inputEl.removeEventListener('compositionstart', this.close);
  },
  methods: {
    optionId(index) {
      return `${this.listboxId}-option-${index}`;
    },
    // Indexed rather than derived from the heading: a label is prose, and a
    // space in it would break the id list `aria-labelledby` expects.
    sectionLabelId(sectionIndex) {
      return `${this.listboxId}-group-${sectionIndex}`;
    },
    sectionClasses(sectionIndex) {
      return sectionIndex === 0 ? null : SECTION_DIVIDER_CLASSES;
    },
    commandLabel(command) {
      return labelText(command.label) || command.value;
    },
    evaluate() {
      if (!this.adapter) return;

      if (this.disabled) {
        this.close();
        return;
      }

      // A non-collapsed selection is not a caret, so there is nothing to anchor to.
      if (this.adapter.hasTextSelection()) {
        this.close();
        return;
      }

      const caret = this.adapter.getCaretOffset();
      const text = this.adapter.getText();

      // The caret has to sit at the end of the token, not somewhere before it.
      const after = text.slice(caret);
      if (after && !/^\s/.test(after)) {
        this.close();
        return;
      }

      const match = TRIGGER_RE.exec(text.slice(0, caret));
      if (!match) {
        this.close();
        return;
      }

      const [, token] = match;

      // Once the token *is* a command there is nothing left to suggest, and
      // leaving the menu open would make Enter re-select instead of send.
      // Compared by equality, not prefix, so /resetall stays completable.
      if (this.allCommands.some((command) => command.value.toLowerCase() === token.toLowerCase())) {
        this.close();
        return;
      }

      this.query = token;
      this.triggerIndex = caret - token.length;

      // A fetch still running has nothing to show yet, but closing would make the
      // trigger look like it did nothing.
      if (!this.filteredCommands.length && !this.isLoading) {
        this.close();
        return;
      }

      if (!this.isOpen) {
        this.activeIndex = 0;
        this.isOpen = true;
      } else {
        this.activeIndex = Math.max(
          0,
          Math.min(this.activeIndex, this.filteredCommands.length - 1),
        );
        this.$nextTick(this.reposition);
      }
    },
    close() {
      if (this.isOpen) this.isOpen = false;
    },
    onFocusout(event) {
      if (!this.$el.contains(event.relatedTarget)) this.close();
    },
    onScroll() {
      if (this.isOpen) this.reposition();
    },
    async reposition() {
      const { panel } = this.$refs;
      if (!this.adapter || !panel) return;

      const { top, left, height } = this.adapter.getCaretRect(this.triggerIndex);

      // A virtual element: floating-ui only needs a rect, so there is no need
      // for a real anchor node sitting in the DOM at the caret.
      const reference = { getBoundingClientRect: () => new DOMRect(left, top, 1, height) };

      const { x, y } = await computePosition(reference, panel, {
        strategy: 'fixed',
        placement: 'top-start',
        middleware: [offset(4), flip(), shift({ padding: 8 })],
      });

      Object.assign(panel.style, { left: `${x}px`, top: `${y}px` });
    },
    onKeydown(event) {
      if (!this.isOpen || event.target !== this.inputEl) return;
      // keyCode 229 is what browsers report while an IME is composing.
      if (event.isComposing || event.keyCode === 229) return;
      if (event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return;

      const handler = {
        ArrowDown: () => this.moveActive(1),
        ArrowUp: () => this.moveActive(-1),
        Enter: () => this.selectActive(),
        Tab: () => this.selectActive(),
        Escape: () => this.close(),
      }[event.key];

      if (!handler) return;
      if (!this.filteredCommands.length && event.key !== 'Escape') return;

      event.preventDefault();
      event.stopPropagation();
      // The composer sends the message on Enter *keyup*, so consuming only the
      // keydown would still let the release through and submit. Mark the key so
      // its release is swallowed too.
      this.swallowKeyup = event.key;
      handler();
    },
    onKeyup(event) {
      // One-shot: any keyup clears the mark, so a stale one cannot swallow a
      // later, unrelated press.
      const swallowed = this.swallowKeyup;
      this.swallowKeyup = null;

      if (swallowed !== event.key) return;

      event.preventDefault();
      event.stopPropagation();
    },
    moveActive(delta) {
      const { length } = this.filteredCommands;
      if (!length) return;

      this.activeIndex = (this.activeIndex + delta + length) % length;
    },
    selectActive() {
      if (this.activeCommand) this.emitSelect(this.activeCommand);
    },
    emitSelect(command) {
      // The matched range travels with the event so the parent can splice the
      // token rather than replace the prompt, which would discard anything the
      // user had already written around it.
      this.$emit('select', command, { triggerIndex: this.triggerIndex, token: this.query });
      this.close();
    },
    scrollActiveIntoView() {
      document.getElementById(this.optionId(this.activeIndex))?.scrollIntoView({
        block: 'nearest',
      });
    },
    syncAriaAttributes() {
      if (!this.inputEl) return;

      if (!this.isOpen) {
        this.inputEl.removeAttribute('aria-activedescendant');
        this.inputEl.removeAttribute('aria-controls');
        this.inputEl.setAttribute('aria-expanded', 'false');
        return;
      }

      this.inputEl.setAttribute('aria-expanded', 'true');
      this.inputEl.setAttribute('aria-controls', this.listboxId);
      if (this.activeCommand) {
        this.inputEl.setAttribute('aria-activedescendant', this.optionId(this.activeIndex));
      } else {
        this.inputEl.removeAttribute('aria-activedescendant');
      }
    },
    // Keeps focus in the input for the whole click, so focusout never fires
    // and the follow-up click still reaches the option.
    onPanelMousedown(event) {
      event.preventDefault();
    },
  },
  i18n: {
    LISTBOX_LABEL: __('Slash commands'),
    LOADING: __('Loading…'),
  },
};
</script>

<template>
  <div>
    <slot></slot>
    <div data-testid="slash-commands-panel-container" class="gl-new-dropdown-container gl-relative">
      <div
        v-if="isOpen"
        ref="panel"
        class="gl-new-dropdown-panel gl-fixed gl-left-0 gl-top-0 !gl-block gl-w-33"
        data-testid="slash-commands-panel"
        @mousedown="onPanelMousedown"
      >
        <ul
          :id="listboxId"
          role="listbox"
          :aria-label="$options.i18n.LISTBOX_LABEL"
          class="gl-new-dropdown-inner gl-mb-0 gl-list-none gl-overflow-auto gl-py-1 gl-pl-0"
        >
          <!-- role="option" is not decorative: aria-activedescendant only
             announces the highlighted row if it is an option in a listbox.
             aria-selected is deliberately absent, since choosing a command runs
             it rather than selecting anything. -->
          <li
            v-if="isLoading && !filteredCommands.length"
            role="presentation"
            class="gl-px-4 gl-py-2 gl-text-sm gl-text-subtle"
            data-testid="slash-commands-loading"
          >
            {{ $options.i18n.LOADING }}
          </li>
          <!-- 
          TODO: Migrate this component to the Pajamas design system. Neither GlCollapsibleListbox or 
          GlDisclosureDropdown satisfy the semantics of a combobox component. Moreover, Pajamas Combobox
          component doesn't satisfy the requirements of the slash command menu. 

          https://gitlab.com/gitlab-org/gitlab/-/work_items/622389
          -->
          <ul
            v-for="(section, sectionIndex) in commandSections"
            :key="section.key"
            :role="section.label ? 'group' : 'presentation'"
            :aria-labelledby="section.label ? sectionLabelId(sectionIndex) : null"
            class="gl-mb-0 gl-list-none gl-pl-0"
            :class="sectionClasses(sectionIndex)"
          >
            <li
              v-if="section.label"
              :id="sectionLabelId(sectionIndex)"
              role="presentation"
              class="gl-pb-2 gl-pl-4 gl-pt-3 gl-text-sm gl-font-bold gl-text-strong"
            >
              {{ section.label }}
            </li>
            <!-- role="option" is not decorative: aria-activedescendant only
               announces the highlighted row if it is an option in a listbox.
               aria-selected is deliberately absent, since choosing a command
               runs it rather than selecting anything. -->
            <gl-disclosure-dropdown-item
              v-for="(command, index) in section.commands"
              :id="optionId(section.startIndex + index)"
              :key="command.value"
              role="option"
              tabindex="-1"
              :class="{
                'gl-new-dropdown-item-highlighted': section.startIndex + index === activeIndex,
              }"
              @action="emitSelect(command)"
            >
              <!-- The default slot rather than #list-item: that one renders the
                 content inside a <button>, and ARIA forbids an interactive
                 element inside role="option". These are the classes the library
                 would have supplied, kept so hover and highlight still apply. -->
              <span class="gl-new-dropdown-item-content">
                <span class="gl-new-dropdown-item-text-wrapper">
                  <span>{{ commandLabel(command) }}</span>
                  <p class="gl-mb-0 gl-truncate gl-text-sm gl-text-subtle">
                    {{ command.description }}
                  </p>
                </span>
              </span>
            </gl-disclosure-dropdown-item>
          </ul>
        </ul>
      </div>
    </div>
  </div>
</template>
