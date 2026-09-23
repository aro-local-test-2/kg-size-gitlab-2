<script>
import { GlAvatarLabeled, GlButton, GlTab, GlTableLite } from '@gitlab/ui';
import { __ } from '~/locale';
import { ACCESS_LEVEL_OWNER_INTEGER, ACCESS_LEVEL_LABELS } from '~/access_level/constants';
import { localeDateFormat } from '~/lib/utils/datetime/locale_dateformat';
import {
  SCOPE_ORDER,
  SCOPE_LABELS,
  PERMISSION_CATEGORY_ROLE,
  PERMISSION_CATEGORY_USER,
} from '../constants';

export default {
  name: 'SecretsManagerPermissionsTable',
  components: {
    GlAvatarLabeled,
    GlButton,
    GlTab,
    GlTableLite,
  },
  props: {
    canDelete: {
      type: Boolean,
      required: true,
    },
    items: {
      type: Array,
      required: true,
    },
    permissionCategory: {
      type: String,
      required: true,
    },
  },
  emits: ['delete-permission'],
  data() {
    return {};
  },
  computed: {
    isCategoryRole() {
      return this.permissionCategory === PERMISSION_CATEGORY_ROLE;
    },
    isCategoryUser() {
      return this.permissionCategory === PERMISSION_CATEGORY_USER;
    },
    tableFields() {
      const thClass = this.canDelete ? 'gl-w-1/5' : 'gl-w-1/4';
      return [
        ...(this.isCategoryUser
          ? [
              {
                key: 'user',
                label: __('User'),
              },
              {
                key: 'role',
                label: __('Role'),
              },
            ]
          : []),
        ...(this.isCategoryRole
          ? [
              {
                key: 'role',
                label: __('Role'),
                thClass,
              },
            ]
          : []),
        {
          key: 'scope',
          label: __('Scope'),
          thClass,
        },
        {
          key: 'expiration',
          label: __('Expiration'),
          thClass,
        },
        {
          key: 'access-granted',
          label: __('Access granted'),
        },
        ...(this.canDelete
          ? [
              {
                key: 'actions',
                label: __('Actions'),
              },
            ]
          : []),
      ];
    },
    tableTitle() {
      if (this.permissionCategory === PERMISSION_CATEGORY_USER) {
        return __('Users');
      }

      return __('Roles');
    },
    tabElements() {
      return this.$options.tabElementsByCategory[this.permissionCategory];
    },
    tabLinkAttributes() {
      return { 'data-testid': this.tabElements.tab };
    },
  },
  methods: {
    formatExpiration(expiration) {
      if (expiration) {
        return localeDateFormat.asDate.format(new Date(expiration));
      }

      return __('Never');
    },
    formatActions(actions) {
      return [...actions]
        .sort((a, b) => SCOPE_ORDER.indexOf(a) - SCOPE_ORDER.indexOf(b))
        .map((a) => SCOPE_LABELS[a])
        .join(', ');
    },
    formatRoleName(id) {
      return ACCESS_LEVEL_LABELS[id] || '';
    },
    isOwner(accessLevel) {
      return Number(accessLevel) === ACCESS_LEVEL_OWNER_INTEGER;
    },
  },
  // The tab testid goes through title-link-attributes because gl-tabs, not
  // gl-tab, renders the clickable nav button the E2E spec needs to target.
  tabElementsByCategory: {
    [PERMISSION_CATEGORY_USER]: {
      tab: 'secrets-manager-users-tab',
      table: 'secrets-manager-users-content',
    },
    [PERMISSION_CATEGORY_ROLE]: {
      tab: 'secrets-manager-roles-tab',
      table: 'secrets-manager-roles-content',
    },
  },
};
</script>

<template>
  <gl-tab :title="tableTitle" :title-link-attributes="tabLinkAttributes">
    <gl-table-lite :items="items" :fields="tableFields" :data-testid="tabElements.table">
      <template
        v-if="isCategoryUser"
        #cell(user)="{
          item: {
            principal: { user },
          },
        }"
      >
        <gl-avatar-labeled
          :size="32"
          :src="user.avatarUrl"
          :label="user.username"
          :label-link="user.webUrl"
          :sub-label="user.name"
        />
      </template>
      <template #cell(role)="{ item: { principal } }">
        <span v-if="isCategoryUser">{{ formatRoleName(principal.userRoleId) }}</span>
        <span v-if="isCategoryRole">{{ formatRoleName(principal.id) }}</span>
      </template>
      <template #cell(scope)="{ item: { actions } }">
        {{ formatActions(actions) }}
      </template>
      <template #cell(expiration)="{ item: { expiredAt } }">
        <span>{{ formatExpiration(expiredAt) }}</span>
      </template>
      <template #cell(access-granted)="{ item: { grantedBy } }">
        <gl-avatar-labeled
          v-if="Boolean(grantedBy)"
          :size="32"
          :src="grantedBy.avatarUrl"
          :label="grantedBy.username"
          :label-link="grantedBy.webUrl"
          :sub-label="grantedBy.name"
        />
        <span v-else>{{ __('N/A') }}</span>
      </template>
      <template #cell(actions)="{ item: { principal } }">
        <gl-button
          v-if="!isOwner(principal.id)"
          icon="remove"
          :title="__('Delete')"
          :aria-label="__('Delete')"
          @click="$emit('delete-permission', principal)"
        />
      </template>
    </gl-table-lite>
  </gl-tab>
</template>
