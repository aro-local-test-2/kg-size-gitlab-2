<script>
import { GlAlert, GlAvatarLabeled, GlTokenSelector } from '@gitlab/ui';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import searchAllUsersQuery from '~/graphql_shared/queries/users_search_all.query.graphql';
import searchGroupUsersQuery from '~/graphql_shared/queries/group_users_search.query.graphql';
import { PAGE_SIZE } from '../../../usage_billing/constants';

const SEARCH_TERM_MIN_LENGTH = 3;

export default {
  name: 'CreditCapsUserOverrideSelect',
  components: {
    GlAlert,
    GlAvatarLabeled,
    GlTokenSelector,
  },
  inject: {
    namespacePath: {
      default: null,
    },
  },
  props: {
    value: {
      type: Array,
      required: true,
    },
    inputId: {
      type: String,
      required: false,
      default: null,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['input'],
  apollo: {
    users: {
      query() {
        return this.namespacePath ? searchGroupUsersQuery : searchAllUsersQuery;
      },
      variables() {
        return {
          search: this.search,
          first: PAGE_SIZE,
          fullPath: this.namespacePath,
        };
      },
      update(data) {
        if (this.namespacePath) {
          return data?.namespace?.users?.nodes?.map((member) => member.user) ?? [];
        }
        return data?.users?.nodes ?? [];
      },
      error(error) {
        this.users = [];
        this.hasError = true;
        logError(error);
        captureException(error);
      },
      skip() {
        return this.isSearchTermTooShort;
      },
      debounce: DEFAULT_DEBOUNCE_AND_THROTTLE_MS,
    },
  },
  data() {
    return {
      users: [],
      search: '',
      hasError: false,
    };
  },
  computed: {
    isSearching() {
      return this.$apollo.queries.users.loading;
    },
    isSearchTermTooShort() {
      return this.search.length > 0 && this.search.length < SEARCH_TERM_MIN_LENGTH;
    },
    noResultsMessage() {
      if (this.isSearchTermTooShort) {
        return s__('UsageBilling|Type at least 3 characters to search for users.');
      }
      return s__('UsageBilling|No users found.');
    },
    placeholderText() {
      return this.value.length ? '' : s__('UsageBilling|Search for a user');
    },
  },
  methods: {
    onSearch(term) {
      this.search = term;
      this.hasError = false;
      if (this.isSearchTermTooShort) {
        this.users = [];
      }
    },
  },
};
</script>

<template>
  <gl-token-selector
    :selected-tokens="value"
    :dropdown-items="users"
    :loading="isSearching"
    :placeholder="placeholderText"
    :disabled="disabled"
    :text-input-attrs="{
      id: inputId,
      'data-testid': 'user-override-select-input',
      'aria-label': s__('UsageBilling|Search for a user'),
    }"
    data-testid="user-override-select"
    @text-input="onSearch"
    @input="$emit('input', $event)"
    @keydown.enter.prevent
  >
    <template #dropdown-item-content="{ dropdownItem }">
      <gl-avatar-labeled
        :src="dropdownItem.avatarUrl"
        :size="32"
        :label="dropdownItem.name"
        :sub-label="`@${dropdownItem.username}`"
      />
    </template>
    <template #no-results-content>
      {{ noResultsMessage }}
    </template>
    <template #dropdown-footer>
      <gl-alert
        v-if="hasError"
        variant="danger"
        :dismissible="false"
        class="gl-m-3"
        data-testid="user-override-select-error-alert"
      >
        {{ s__('UsageBilling|Something went wrong while searching for users.') }}
      </gl-alert>
    </template>
  </gl-token-selector>
</template>
