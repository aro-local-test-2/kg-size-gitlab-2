<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem, GlIcon, GlToggle } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { s__ } from '~/locale';
import { isWebSearchAvailable } from '../utils/web_search_preference';
import { goalSlashCommand } from '../plugins/goal';

export default {
  name: 'PromptInputActions',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlIcon,
    GlToggle,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    // Defaults to false so a mount that does not provide it hides the control
    // rather than granting a capability no group opted into.
    webSearchAllowedForGroup: {
      default: false,
    },
  },
  props: {
    webSearchEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    // Answered by the composer, which is also what runs the action. Defaults to false
    // for the same reason `webSearchAllowedForGroup` does: a mount that does not supply
    // it hides the row rather than offering one that cannot work.
    goalAvailable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['update:web-search-enabled', 'attach-files', 'dispatch-action'],
  computed: {
    hasWebSearch() {
      return isWebSearchAvailable(this.glFeatures, this.webSearchAllowedForGroup);
    },
    hasFileAttachments() {
      return Boolean(this.glFeatures?.dapWebChatFileAttachments);
    },
    hasActions() {
      return this.hasWebSearch || this.hasFileAttachments || this.goalAvailable;
    },
  },
  methods: {
    toggleWebSearch() {
      this.$emit('update:web-search-enabled', !this.webSearchEnabled);
    },
    // The menu stays open on activation, which is what the web search toggle wants.
    // This item does not: closing it keeps it from sitting behind the file dialog.
    attachFiles() {
      this.$emit('attach-files');
      // Optional call: the dropdown is stubbed without its methods in some tests.
      this.$refs.dropdown?.close?.();
    },
    startGoalMode() {
      // Dispatches the `/goal` command itself, so this row and the suggestion menu reach
      // goal mode by one path rather than two.
      this.$emit('dispatch-action', goalSlashCommand.action, { command: goalSlashCommand });
      // A one-shot action like attaching files, so it closes the menu too.
      this.$refs.dropdown?.closeAndFocus?.();
    },
  },
  goalCommand: goalSlashCommand,
  i18n: {
    MORE_ACTIONS: s__('DuoAgenticChat|More actions'),
    WEB_SEARCH: s__('DuoAgenticChat|Web search'),
    ATTACH_IMAGE: s__('DuoAgenticChat|Attach image'),
  },
};
</script>
<template>
  <gl-disclosure-dropdown
    v-if="hasActions"
    ref="dropdown"
    icon="plus"
    category="tertiary"
    positioning-strategy="fixed"
    no-caret
    :auto-close="false"
    :disabled="disabled"
    :toggle-text="$options.i18n.MORE_ACTIONS"
    text-sr-only
  >
    <gl-disclosure-dropdown-item
      v-if="goalAvailable"
      data-testid="goal-item"
      @action="startGoalMode"
    >
      <template #list-item>
        <span class="gl-flex gl-items-center gl-gap-3">
          <gl-icon name="work-item-objective" variant="current" />
          {{ $options.goalCommand.label }}
        </span>
      </template>
    </gl-disclosure-dropdown-item>
    <gl-disclosure-dropdown-item
      v-if="hasFileAttachments"
      data-testid="attach-image-item"
      @action="attachFiles"
    >
      <template #list-item>
        <span class="gl-flex gl-items-center gl-gap-3">
          <gl-icon name="paperclip" variant="current" />
          {{ $options.i18n.ATTACH_IMAGE }}
        </span>
      </template>
    </gl-disclosure-dropdown-item>
    <gl-disclosure-dropdown-item
      v-if="hasWebSearch"
      data-testid="web-search-item"
      @action="toggleWebSearch"
    >
      <template #list-item>
        <gl-toggle
          :value="webSearchEnabled"
          :label="$options.i18n.WEB_SEARCH"
          label-position="left"
          class="gl-w-full gl-justify-between"
          data-testid="web-search-toggle"
        >
          <template #label>
            <!-- `.gl-toggle-label` styles the label as a form label (bold, text-strong).
                 In a menu it is just the item's name, so it matches the sibling item. -->
            <span class="gl-flex gl-items-center gl-gap-3 gl-font-normal gl-text-default">
              <gl-icon name="earth" variant="current" />
              {{ $options.i18n.WEB_SEARCH }}
            </span>
          </template>
        </gl-toggle>
      </template>
    </gl-disclosure-dropdown-item>
  </gl-disclosure-dropdown>
</template>
