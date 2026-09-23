<script>
import { GlCollapsibleListbox } from '@gitlab/ui';
import { debounce, unionBy } from 'lodash-es';
import fuzzaldrinPlus from 'fuzzaldrin-plus';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import SidebarParticipant from '~/sidebar/components/assignees/sidebar_participant.vue';
import usersSearchQuery from '~/graphql_shared/queries/workspace_autocomplete_users.query.graphql';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { __, s__ } from '~/locale';

export default {
  name: 'DecisionLogDeciderSelect',
  components: {
    GlCollapsibleListbox,
    SidebarParticipant,
  },
  props: {
    value: {
      type: String,
      required: false,
      default: '',
    },
    fullPath: {
      type: String,
      required: false,
      default: '',
    },
    isGroup: {
      type: Boolean,
      required: false,
      default: false,
    },
    participants: {
      type: Array,
      required: false,
      default: () => [],
    },
    selectedUser: {
      type: Object,
      required: false,
      default: null,
    },
    isInvalid: {
      type: Boolean,
      required: false,
      default: false,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['input', 'select-user'],
  data() {
    return {
      searchKey: '',
      searchStarted: false,
      hasSearchFailed: false,
      users: [],
    };
  },
  apollo: {
    users: {
      query: usersSearchQuery,
      variables() {
        return {
          search: this.searchKey,
          fullPath: this.fullPath,
          isProject: !this.isGroup,
        };
      },
      skip() {
        return !this.searchStarted || !this.fullPath;
      },
      update(data) {
        return (this.isGroup ? data.groupNamespace?.users : data.namespace?.users) ?? [];
      },
      error(error) {
        this.hasSearchFailed = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    // Participants come before search results so the dropdown lists them first.
    knownUsers() {
      return unionBy(this.seededUsers, this.participants, this.users, 'id');
    },
    seededUsers() {
      return this.selectedUser ? [this.selectedUser] : [];
    },
    toggleText() {
      return (
        this.knownUsers.find((user) => user.id === this.value)?.name ??
        s__('WorkItemDecisionLog|Select a user')
      );
    },
    listedUsers() {
      if (this.searchKey === '') {
        return this.knownUsers;
      }

      return unionBy(this.matchedParticipants, this.users, 'id');
    },
    matchedParticipants() {
      return fuzzaldrinPlus.filter(
        this.participants.map((user) => ({ ...user, matcher: `${user.name} ${user.username}` })),
        this.searchKey,
        { key: 'matcher' },
      );
    },
    items() {
      return this.listedUsers.map((user) => ({ value: user.id, text: user.name, user }));
    },
    isSearching() {
      return this.$apollo.queries.users.loading;
    },
    noResultsText() {
      return this.hasSearchFailed
        ? s__('WorkItemDecisionLog|Could not load users. Refresh the page and try again.')
        : s__('WorkItem|No matching results');
    },
    toggleClass() {
      return this.isInvalid ? '!gl-border-red-500' : '';
    },
  },
  created() {
    this.debouncedSearch = debounce((search) => {
      this.hasSearchFailed = false;
      this.searchKey = search;
    }, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
  },
  beforeDestroy() {
    this.debouncedSearch.cancel();
  },
  methods: {
    // The list mixes participants with namespace search results, so only this component can turn
    // the chosen id back into a user.
    onSelect(id) {
      this.$emit('input', id);
      this.$emit('select-user', this.knownUsers.find((user) => user.id === id) ?? null);
    },
    onShown() {
      this.hasSearchFailed = false;
      this.searchStarted = true;
    },
  },
  i18n: {
    searchPlaceholder: __('Search users'),
  },
};
</script>

<template>
  <gl-collapsible-listbox
    block
    is-check-centered
    searchable
    :items="items"
    :disabled="disabled"
    :searching="isSearching"
    :selected="value"
    :toggle-text="toggleText"
    :toggle-class="toggleClass"
    :search-placeholder="$options.i18n.searchPlaceholder"
    :no-results-text="noResultsText"
    data-testid="decision-decided-by-select"
    @search="debouncedSearch"
    @shown="onShown"
    @select="onSelect"
  >
    <template #list-item="{ item }">
      <sidebar-participant :user="item.user" />
    </template>
  </gl-collapsible-listbox>
</template>
