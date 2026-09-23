<script>
import {
  GlAlert,
  GlAvatar,
  GlButton,
  GlCard,
  GlFormInputGroup,
  GlIcon,
  GlInputGroupText,
  GlKeysetPagination,
  GlLoadingIcon,
  GlTableLite,
  GlToggle,
} from '@gitlab/ui';
import { s__ } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import getUserOverridesQuery from '../graphql/get_user_overrides.query.graphql';
import upsertUserOverridesMutation from '../graphql/upsert_user_overrides.mutation.graphql';
import { PAGE_SIZE } from '../../../usage_billing/constants';
import AddUserOverrideModal from './add_user_override_modal.vue';

export default {
  name: 'CreditCapsUserOverridesList',
  components: {
    AddUserOverrideModal,
    GlAlert,
    GlAvatar,
    GlButton,
    GlCard,
    GlFormInputGroup,
    GlIcon,
    GlInputGroupText,
    GlKeysetPagination,
    GlLoadingIcon,
    GlTableLite,
    GlToggle,
  },
  inject: {
    namespacePath: {
      default: null,
    },
  },
  data() {
    return {
      userOverrides: null,
      userOverridesDrafts: [],
      savingUserIds: {},
      saveErrors: {},
      hasError: false,
      isAddModalVisible: false,
      pageInfo: {
        first: PAGE_SIZE,
        after: null,
        last: null,
        before: null,
      },
    };
  },
  apollo: {
    userOverrides: {
      query: getUserOverridesQuery,
      variables() {
        return { namespacePath: this.namespacePath, ...this.pageInfo };
      },
      fetchPolicy: 'network-only',
      update({ subscriptionUsage }) {
        const { nodes = [], pageInfo = {} } = subscriptionUsage?.budgetCaps?.userOverrides ?? {};

        // Drop overrides without a user: the CDot record may lack an entity_id,
        // or the GitLab user may have been hard-deleted.
        return {
          nodes: nodes.filter((node) => node.user?.id),
          pageInfo,
        };
      },
      result({ data, error }) {
        const userOverrides = data?.subscriptionUsage?.budgetCaps?.userOverrides;
        if (error) return;
        if (!userOverrides) {
          // eslint-disable-next-line @gitlab/require-i18n-strings
          const nullDataError = new Error('User overrides data unavailable');
          this.hasError = true;
          logError(nullDataError);
          captureException(nullDataError);
          return;
        }
        this.hasError = false;

        // userOverridesDrafts decouples v-model bindings from the Apollo cache.
        this.userOverridesDrafts = this.userOverrides.nodes.map((node) => ({
          cap: node.cap,
          enabled: node.capEnabled,
          user: node.user,
          _showDetails: false,
        }));
      },
      error(error) {
        this.hasError = true;
        logError(error);
        captureException(error);
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.userOverrides.loading;
    },
    hasPagination() {
      return this.currentPageInfo.hasNextPage || this.currentPageInfo.hasPreviousPage;
    },
    currentPageInfo() {
      if (this.userOverrides.pageInfo) return this.userOverrides.pageInfo;

      return {
        hasNextPage: false,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: null,
      };
    },
    tableFields() {
      // Remove bottom border on rows that have on-save error
      const tdClass = (value, key, item) =>
        this.saveErrors[item.user?.id] ? '!gl-border-b-0' : '';

      return [
        { key: 'user', label: s__('UsageBilling|User'), thClass: '!gl-border-t-0', tdClass },
        {
          key: 'cap',
          label: s__('UsageBilling|Override cap'),
          thClass: '!gl-border-t-0',
          tdClass,
        },
        {
          key: 'capEnabled',
          label: s__('UsageBilling|Status'),
          thClass: '!gl-border-t-0',
          tdClass,
        },
        {
          key: 'actions',
          label: s__('UsageBilling|Actions'),
          thClass: '!gl-border-t-0 gl-sr-only',
          tdClass,
        },
      ];
    },
  },
  methods: {
    getIdFromGraphQLId,
    openAddModal() {
      this.isAddModalVisible = true;
    },
    closeAddModal() {
      this.isAddModalVisible = false;
    },
    onOverrideSaved() {
      this.closeAddModal();
      this.pageInfo = { first: PAGE_SIZE, after: null, last: null, before: null };
      this.$apollo.queries.userOverrides.refetch();
    },
    onNextPage(cursor) {
      this.userOverridesDrafts = [];
      this.savingUserIds = {};
      this.saveErrors = {};
      this.pageInfo = { first: PAGE_SIZE, after: cursor, last: null, before: null };
    },
    onPrevPage(cursor) {
      this.userOverridesDrafts = [];
      this.savingUserIds = {};
      this.saveErrors = {};
      this.pageInfo = { first: null, after: null, last: PAGE_SIZE, before: cursor };
    },
    async saveUserOverride(draft) {
      const userId = draft.user?.id;
      if (!userId) return;

      this.savingUserIds = { ...this.savingUserIds, [userId]: true };
      const { [userId]: _, ...restErrors } = this.saveErrors;
      this.saveErrors = restErrors;
      // `_showDetails` is a built-in <gl-table> property to display details row.
      // We utilize details row to display row edits errors in-line
      // eslint-disable-next-line no-underscore-dangle
      draft._showDetails = false;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: upsertUserOverridesMutation,
          variables: {
            namespacePath: this.namespacePath,
            overrides: [
              {
                userId,
                cap: Number(draft.cap),
                enabled: draft.enabled,
              },
            ],
          },
        });

        const errorMessages = data?.upsertUserBudgetCapOverrides?.errors ?? [];
        const errors = errorMessages.map((msg) => new Error(msg));
        if (errors.length === 1) throw errors[0];
        if (errors.length) {
          throw new AggregateError(
            errors,
            s__('UsageBilling|An error occurred while saving user cap override.'),
          );
        }

        const [saved] = data?.upsertUserBudgetCapOverrides?.userOverrides ?? [];
        if (saved) {
          draft.cap = saved.cap;
          draft.enabled = saved.capEnabled;
        }

        toast(s__('UsageBilling|Override saved.'));
      } catch (error) {
        this.saveErrors = { ...this.saveErrors, [userId]: error.message };
        // eslint-disable-next-line no-underscore-dangle
        draft._showDetails = true;
        logError(error);
        captureException(error);
      } finally {
        const { [userId]: _done, ...restSaving } = this.savingUserIds;
        this.savingUserIds = restSaving;
      }
    },
  },
};
</script>

<template>
  <gl-card data-testid="user-credit-caps-overrides-card">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between">
        <div>
          <h3 class="gl-heading-scale-500 gl-mb-1">
            {{ s__('UsageBilling|Per-user cap overrides') }}
          </h3>
          <p class="gl-mb-0 gl-text-subtle">
            {{ s__('UsageBilling|Individual overrides take precedence over the flat cap.') }}
          </p>
        </div>
        <gl-button
          variant="confirm"
          data-testid="user-credit-caps-add-override-button"
          @click="openAddModal"
        >
          <gl-icon name="plus" :size="12" />
          {{ s__('UsageBilling|Add override') }}
        </gl-button>
      </div>
    </template>

    <template #default>
      <gl-loading-icon
        v-if="isLoading"
        size="lg"
        data-testid="user-credit-caps-overrides-loading-icon"
      />

      <gl-alert
        v-else-if="hasError"
        variant="danger"
        :dismissible="false"
        data-testid="user-credit-caps-overrides-error-alert"
      >
        {{ s__('UsageBilling|An error occurred while fetching user overrides.') }}
      </gl-alert>

      <template v-else>
        <p
          v-if="!userOverridesDrafts.length"
          class="gl-text-subtle"
          data-testid="user-credit-caps-overrides-empty-state"
        >
          {{ s__('UsageBilling|No per-user overrides set.') }}
        </p>

        <template v-else>
          <!-- Forms are rendered outside GlTableLite because the HTML spec forbids
               <form> elements inside <table>. Each input and button references its
               form via the form= attribute using the user's ID as a key. -->
          <form
            v-for="draft in userOverridesDrafts"
            :id="`override-form-${draft.user.id}`"
            :key="draft.user.id"
            data-testid="user-credit-caps-overrides-form"
            @submit.prevent="saveUserOverride(draft)"
          ></form>

          <gl-table-lite
            :items="userOverridesDrafts"
            :fields="tableFields"
            stacked="sm"
            data-testid="user-credit-caps-overrides-table"
          >
            <template #cell(user)="{ item: { user } }">
              <div class="gl-flex gl-items-center gl-gap-2">
                <gl-avatar
                  :src="user.avatarUrl"
                  :alt="user.name"
                  :entity-name="user.name"
                  :entity-id="getIdFromGraphQLId(user.id)"
                  :size="24"
                />
                <div>
                  <div>{{ user.name }}</div>
                  <div class="gl-text-sm gl-text-subtle">@{{ user.username }}</div>
                </div>
              </div>
            </template>

            <template #cell(cap)="{ item }">
              <label :for="`cap-input-${item.user.id}`" class="gl-sr-only">{{
                s__('UsageBilling|Override cap')
              }}</label>
              <gl-form-input-group
                :id="`cap-input-${item.user.id}`"
                v-model.number="item.cap"
                :form="`override-form-${item.user.id}`"
                type="number"
                min="0"
                step="1"
                :disabled="savingUserIds[item.user.id]"
                data-testid="user-credit-caps-overrides-cap-input"
                class="gl-w-36"
              >
                <template #append>
                  <gl-input-group-text>{{ s__('UsageBilling|credits') }}</gl-input-group-text>
                </template>
              </gl-form-input-group>
            </template>

            <template #cell(capEnabled)="{ item }">
              <gl-toggle
                v-model="item.enabled"
                :label="s__('UsageBilling|Enabled')"
                label-position="left"
                :disabled="savingUserIds[item.user.id]"
                data-testid="user-credit-caps-overrides-enabled-toggle"
              />
            </template>

            <template #cell(actions)="{ item }">
              <gl-button
                type="submit"
                size="small"
                variant="confirm"
                :form="`override-form-${item.user.id}`"
                :loading="savingUserIds[item.user.id]"
                data-testid="user-credit-caps-overrides-save-button"
              >
                {{ s__('UsageBilling|Save') }}
              </gl-button>
            </template>

            <template #row-details="{ item }">
              <gl-alert
                variant="danger"
                :dismissible="false"
                data-testid="user-credit-caps-overrides-save-error-alert"
              >
                {{ saveErrors[item.user.id] }}
              </gl-alert>
            </template>
          </gl-table-lite>
        </template>

        <div v-if="hasPagination" class="gl-mt-4 gl-flex gl-justify-center">
          <gl-keyset-pagination
            v-bind="currentPageInfo"
            data-testid="user-credit-caps-overrides-pagination"
            @prev="onPrevPage"
            @next="onNextPage"
          />
        </div>
      </template>

      <add-user-override-modal
        :visible="isAddModalVisible"
        @hidden="closeAddModal"
        @saved="onOverrideSaved"
      />
    </template>
  </gl-card>
</template>
