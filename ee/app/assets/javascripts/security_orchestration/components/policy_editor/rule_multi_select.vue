<script>
import { GlCollapsibleListbox, GlTruncate } from '@gitlab/ui';
import { debounce } from 'lodash-es';

import { s__, sprintf } from '~/locale';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { searchInItemsProperties } from '~/lib/utils/search_utils';
import { renderMultiSelectText } from './utils';

export default {
  name: 'RuleMultiSelect',
  components: {
    GlCollapsibleListbox,
    GlTruncate,
  },
  props: {
    itemTypeName: {
      type: String,
      required: true,
    },
    items: {
      type: Object,
      required: true,
    },
    value: {
      type: Array,
      required: false,
      default: () => [],
    },
    /**
     * When a non-empty string is provided, the dropdown toggle displays
     * this text verbatim instead of the computed multi-select text.
     * This intentionally bypasses the `lowercase` prop — callers are
     * responsible for casing when using the override.
     */
    toggleTextOverride: {
      type: String,
      required: false,
      default: '',
    },
    includeSelectAll: {
      type: Boolean,
      required: false,
      default: () => true,
    },
    lowercase: {
      type: Boolean,
      required: false,
      default: false,
    },
    showResetButton: {
      type: Boolean,
      required: false,
      default: true,
    },
    searchable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['input'],
  data() {
    return {
      selected: [...this.value],
      searchTerm: '',
    };
  },
  computed: {
    listBoxItems() {
      return Object.entries(this.items).map(([value, text]) => ({ value, text }));
    },
    filteredListBoxItems() {
      if (!this.searchable) return this.listBoxItems;

      return searchInItemsProperties({
        items: this.listBoxItems,
        properties: ['text'],
        searchQuery: this.searchTerm,
      });
    },
    listBoxHeader() {
      return sprintf(this.$options.i18n.selectPolicyListboxHeader, {
        itemTypeName: this.itemTypeName,
      });
    },
    resetButtonLabel() {
      return this.showResetButton ? this.$options.i18n.clearAllLabel : '';
    },
    selectAllLabel() {
      return this.includeSelectAll ? this.$options.i18n.selectAllLabel : '';
    },
    text() {
      if (this.toggleTextOverride?.trim()) return this.toggleTextOverride;

      const text = renderMultiSelectText({
        selected: this.selected,
        items: this.items,
        itemTypeName: this.itemTypeName,
      });

      if (this.lowercase) return text.toLowerCase();

      return text;
    },
    filteredItemsKeys() {
      return this.filteredListBoxItems.map(({ value }) => value);
    },
  },
  watch: {
    value(newValue) {
      this.selected = newValue;
    },
  },
  created() {
    this.debouncedSetSearchTerm = debounce(this.setSearchTerm, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
  },
  destroyed() {
    this.debouncedSetSearchTerm.cancel();
  },
  methods: {
    setSelected(items) {
      this.selected = [...items];
      this.$emit('input', this.selected);
    },
    setSearchTerm(searchTerm = '') {
      this.searchTerm = searchTerm.trim();
    },
  },
  i18n: {
    multipleSelectedLabel: s__(
      'PolicyRuleMultiSelect|%{firstLabel} +%{numberOfAdditionalLabels} more',
    ),
    clearAllLabel: s__('PolicyRuleMultiSelect|Clear all'),
    selectAllLabel: s__('PolicyRuleMultiSelect|Select all'),
    selectedItemsLabel: s__('PolicyRuleMultiSelect|Select %{itemTypeName}'),
    selectPolicyListboxHeader: s__('PolicyRuleMultiSelect|Select %{itemTypeName}'),
    allSelectedLabel: s__('PolicyRuleMultiSelect|All %{itemTypeName}'),
  },
};
</script>

<template>
  <gl-collapsible-listbox
    multiple
    :header-text="listBoxHeader"
    :items="filteredListBoxItems"
    :selected="selected"
    :searchable="searchable"
    :show-select-all-button-label="selectAllLabel"
    :reset-button-label="resetButtonLabel"
    :toggle-text="text"
    @reset="setSelected([])"
    @search="debouncedSetSearchTerm"
    @select="setSelected"
    @select-all="setSelected(filteredItemsKeys)"
  >
    <template #list-item="{ item }">
      <gl-truncate :text="item.text" />
    </template>
  </gl-collapsible-listbox>
</template>
