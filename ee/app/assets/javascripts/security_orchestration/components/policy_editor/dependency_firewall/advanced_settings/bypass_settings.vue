<script>
import { s__ } from '~/locale';
import UsersSelector from '../../scan_result/advanced_settings/policy_exceptions/users_selector.vue';
import TokensSelector from '../../scan_result/advanced_settings/policy_exceptions/tokens_selector.vue';

export default {
  name: 'BypassSettings',
  components: { UsersSelector, TokensSelector },
  i18n: {
    title: s__('SecurityOrchestration|Bypass settings'),
  },
  props: {
    bypassSettings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['changed'],
  computed: {
    selectedUsers() {
      return this.bypassSettings.users || [];
    },
    selectedTokens() {
      return this.bypassSettings.access_tokens || [];
    },
  },
  methods: {
    emitChanges(users, accessTokens) {
      const changes = {};

      if (users.length) changes.users = users;
      if (accessTokens.length) changes.access_tokens = accessTokens;

      this.$emit('changed', 'bypass_settings', changes);
    },
    updateUsers(users) {
      this.emitChanges(users, this.selectedTokens);
    },
    updateTokens(accessTokens) {
      this.emitChanges(this.selectedUsers, accessTokens);
    },
  },
};
</script>

<template>
  <div>
    <h4>{{ $options.i18n.title }}</h4>
    <users-selector :selected-users="selectedUsers" @set-users="updateUsers" />
    <tokens-selector :selected-tokens="selectedTokens" @set-access-tokens="updateTokens" />
  </div>
</template>
