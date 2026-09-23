<script>
import { GlBadge, GlButton, GlCollapsibleListbox, GlIcon, GlPopover, GlToggle } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import { GITLAB_DEFAULT_MODEL } from 'ee/ai/model_selection/constants';
import { MAX_RECENT_MODELS, RECENT_MODEL_VALUE_PREFIX } from '../../constants';

const RECENT_POPOVER_ID_SUFFIX = '-recent';
// eslint-disable-next-line @gitlab/require-i18n-strings -- KeyboardEvent.key names, not UI copy
const LIST_NAVIGATION_KEYS = ['ArrowDown', 'ArrowUp', 'Home', 'End'];
// The listbox scrolls the highlighted row into view with behavior: 'smooth',
// which keeps emitting scroll events after the key press (9 events over 75ms
// in Chrome). Hold the keyboard exemption for that long, so any later scroll
// of the user's own still closes the popover.
const KEYBOARD_SCROLL_GRACE_MS = 300;

export default {
  name: 'ChatModelSelectDropdown',
  components: {
    GlBadge,
    GlButton,
    GlCollapsibleListbox,
    GlIcon,
    GlPopover,
    GlToggle,
  },
  props: {
    items: {
      type: Array,
      required: true,
    },
    recentRefs: {
      type: Array,
      required: false,
      default: () => [],
    },
    selectedOption: {
      type: Object,
      required: false,
      default: null,
    },
    placeholderDropdownText: {
      type: String,
      required: false,
      default: '',
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    showClassicChatButton: {
      type: Boolean,
      required: false,
      default: false,
    },
    classicChatButtonDisabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    agenticModeEnabled: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['select', 'switch-to-classic'],
  data() {
    return {
      searchTerm: '',
      popoverIdPrefix: uniqueId('chat-model-item-'),
      activePopoverId: null,
      isPopoverKeyboardDriven: false,
      keyboardScrollTimer: null,
    };
  },
  computed: {
    selected() {
      return this.selectedOption?.value ?? GITLAB_DEFAULT_MODEL;
    },
    dropdownToggleText() {
      // Resolve by value rather than trusting selectedOption.text: a model
      // saved to localStorage before this UI carries a "<name> - Default" text.
      const selectedItem = this.items.find((item) => item.value === this.selected);

      if (selectedItem) {
        return this.compactModelName(selectedItem);
      }

      return this.selectedOption?.text || this.placeholderDropdownText;
    },
    // The visible toggle text is the bare model name, which announces without
    // saying what the button does. Keep that text inside the label so the
    // accessible name still contains the visible one.
    toggleAriaLabel() {
      if (this.dropdownToggleText === this.placeholderDropdownText) {
        return this.dropdownToggleText;
      }

      return sprintf(s__('DuoChat|Select a model. Current: %{modelName}'), {
        modelName: this.dropdownToggleText,
      });
    },
    decoratedItems() {
      const decorated = this.items.map((item, index) => {
        // The provider is the hosting platform (Bedrock, Vertex) rather than the
        // model vendor, so it is not part of the description. Trailing periods
        // are dropped so the join cannot produce "responses.. $$$".
        const metadataLabel = [item.description, item.costIndicator]
          .filter(Boolean)
          .map((part) => part.trim().replace(/\.$/, ''))
          .join('. ');

        return {
          ...item,
          hasMetadata: Boolean(metadataLabel),
          metadataLabel,
          popoverTargetId: `${this.popoverIdPrefix}-${index}`,
        };
      });

      // The default model leads the list; the rest keep the gateway's order.
      return [
        ...decorated.filter((item) => item.isDefault),
        ...decorated.filter((item) => !item.isDefault),
      ];
    },
    recentItems() {
      return this.recentRefs
        .map((ref) => this.decoratedItems.find((item) => item.ref === ref))
        .filter(Boolean)
        .slice(0, MAX_RECENT_MODELS)
        .map((item) => ({
          ...item,
          value: `${RECENT_MODEL_VALUE_PREFIX}${item.ref}`,
          popoverTargetId: `${item.popoverTargetId}${RECENT_POPOVER_ID_SUFFIX}`,
        }));
    },
    listItems() {
      const all = this.filterBySearch(this.decoratedItems);
      const groups = [];

      // Recent entries are duplicates of main-list models, so a search only
      // needs to match them once: hide the group while a search term is active.
      if (!this.searchTerm && this.recentItems.length) {
        groups.push({ text: s__('DuoChat|Recent'), options: this.recentItems });
      }

      if (all.length) {
        groups.push({
          text: s__('DuoChat|All models'),
          // While searching the results are a single flat list, so the header
          // is noise; keep it for screen readers only.
          textSrOnly: Boolean(this.searchTerm),
          options: all,
        });
      }

      return groups;
    },
  },
  beforeDestroy() {
    clearTimeout(this.keyboardScrollTimer);
  },
  methods: {
    // The gateway bakes the hosting provider into the name ("Claude Sonnet 4.5
    // - Bedrock"). The closed toggle is space-constrained, so strip the exact
    // provider suffix there only; list rows keep the full name until the
    // gateway exposes a clean display name.
    compactModelName({ text, provider }) {
      const suffix = ` - ${provider}`;

      if (provider && text.endsWith(suffix)) {
        return text.slice(0, -suffix.length);
      }

      return text;
    },
    filterBySearch(items) {
      if (!this.searchTerm) {
        return items;
      }

      return items.filter((item) => item.text.toLowerCase().includes(this.searchTerm));
    },
    onSearch(term) {
      this.searchTerm = (term || '').trim().toLowerCase();
    },
    popoverTarget(targetId) {
      // Anchor the popover to the full listbox row (the li that GlListboxItem
      // renders around this slot content), so placement="left" lands outside
      // the dropdown panel instead of at the label's left edge.
      return () => document.getElementById(targetId)?.closest('li');
    },
    showPopover(popoverId, { keyboardDriven = false } = {}) {
      clearTimeout(this.keyboardScrollTimer);
      this.activePopoverId = popoverId;
      this.isPopoverKeyboardDriven = keyboardDriven;

      if (keyboardDriven) {
        this.keyboardScrollTimer = setTimeout(() => {
          this.isPopoverKeyboardDriven = false;
        }, KEYBOARD_SCROLL_GRACE_MS);
      }
    },
    hidePopover() {
      clearTimeout(this.keyboardScrollTimer);
      this.activePopoverId = null;
      this.isPopoverKeyboardDriven = false;
    },
    // A hovered row slides out from under the pointer as the list scrolls, and
    // its popover follows the row past the edges of the panel, briefly growing
    // the document and flashing the page scrollbar. Arrow-key navigation
    // scrolls its own row back into view, so that popover stays anchored and
    // should survive the scroll it just caused.
    onListScroll() {
      if (!this.isPopoverKeyboardDriven) {
        this.hidePopover();
      }
    },
    // A searchable listbox uses virtual focus: real DOM focus stays in the
    // search input and arrow keys only mark an option as highlighted. Sync the
    // popover to the highlighted row after navigation keys, matching hover.
    onListKeydown(event) {
      if (!LIST_NAVIGATION_KEYS.includes(event.key)) {
        return;
      }

      // This handler runs in the capture phase, before the listbox has
      // processed the key. A macrotask is guaranteed to run after the
      // listbox's state update and re-render in both Vue 2 and Vue 3,
      // unlike chained $nextTick whose ordering differs between them.
      setTimeout(() => {
        const highlighted = this.$el?.querySelector('.gl-new-dropdown-item-highlighted');
        const rowContent = highlighted?.querySelector(`[id^="${this.popoverIdPrefix}"]`);

        this.showPopover(rowContent?.id ?? null, { keyboardDriven: true });
      });
    },
    onSelect(value) {
      if (value.startsWith(RECENT_MODEL_VALUE_PREFIX)) {
        const ref = value.slice(RECENT_MODEL_VALUE_PREFIX.length);
        const item = this.items.find((model) => model.ref === ref);

        this.$emit('select', item ? item.value : ref);
        return;
      }

      this.$emit('select', value);
    },
  },
};
</script>
<template>
  <!-- capture: the listbox stops propagation of handled navigation keys, and
       scroll events do not bubble at all -->
  <div @keydown.capture="onListKeydown" @scroll.capture="onListScroll">
    <gl-collapsible-listbox
      :selected="selected"
      data-testid="model-dropdown-selector"
      :items="listItems"
      :no-results-text="__('No results found')"
      :search-placeholder="s__('DuoChat|Search models')"
      searchable
      fluid-width
      placement="bottom-end"
      @search="onSearch"
      @select="onSelect"
      @hidden="hidePopover"
    >
      <template #toggle>
        <gl-button
          data-testid="toggle-button"
          category="tertiary"
          :disabled="disabled"
          :loading="isLoading"
          :aria-label="toggleAriaLabel"
          button-text-classes="gl-flex"
        >
          <div class="gl-flex gl-items-center gl-gap-2">
            <span
              data-testid="dropdown-toggle-text"
              class="gl-max-w-26 gl-overflow-hidden gl-text-ellipsis gl-whitespace-nowrap"
              >{{ dropdownToggleText }}</span
            >
            <gl-icon name="chevron-down" />
          </div>
        </gl-button>
      </template>

      <template #list-item="{ item }">
        <div
          :id="item.popoverTargetId"
          class="gl-flex gl-max-w-34 gl-items-center gl-justify-between gl-gap-3"
          data-testid="model-list-item"
          @mousemove="showPopover(item.popoverTargetId)"
          @mouseleave="hidePopover"
        >
          <span
            class="gl-overflow-hidden gl-text-ellipsis gl-whitespace-nowrap"
            data-testid="model-name"
            >{{ item.text }}</span
          >
          <gl-badge v-if="item.isDefault" variant="neutral" data-testid="default-model-badge">
            {{ s__('DuoChat|Default') }}
          </gl-badge>
          <!-- The popover is unreachable under the listbox's virtual focus, so
               repeat its content in the option's accessible name. -->
          <span v-if="item.hasMetadata" class="gl-sr-only" data-testid="model-metadata-sr-only">{{
            item.metadataLabel
          }}</span>
          <gl-popover
            v-if="item.hasMetadata"
            :show="activePopoverId === item.popoverTargetId"
            :target="popoverTarget(item.popoverTargetId)"
            boundary="viewport"
            placement="left"
            triggers="manual"
            :title="item.text"
            data-testid="model-popover"
          >
            <p v-if="item.description" class="gl-mb-2">{{ item.description }}</p>
            <span
              v-if="item.costIndicator"
              class="gl-text-subtle"
              data-testid="model-cost-indicator"
              >{{ item.costIndicator }}</span
            >
          </gl-popover>
        </div>
      </template>

      <template #footer>
        <div
          v-if="showClassicChatButton"
          class="gl-border-t-1 gl-border-t-dropdown-divider gl-px-4 gl-py-3 gl-border-t-solid"
        >
          <gl-toggle
            :value="agenticModeEnabled"
            :label="s__('DuoChat|Agentic chat')"
            :disabled="classicChatButtonDisabled"
            label-position="left"
            class="gl-w-full gl-justify-between"
            data-testid="agentic-chat-toggle"
            @change="$emit('switch-to-classic', $event)"
          >
            <template #label>
              <span class="gl-font-normal">{{ s__('DuoChat|Agentic chat') }}</span>
            </template>
          </gl-toggle>
        </div>
      </template>
    </gl-collapsible-listbox>
  </div>
</template>
