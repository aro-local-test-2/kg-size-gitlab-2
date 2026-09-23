<script>
import {
  GlAlert,
  GlFormGroup,
  GlFormInputGroup,
  GlInputGroupText,
  GlModal,
  GlToggle,
} from '@gitlab/ui';
import { s__ } from '~/locale';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import upsertUserOverridesMutation from '../graphql/upsert_user_overrides.mutation.graphql';
import UserOverrideSelect from './user_override_select.vue';

export default {
  name: 'CreditCapsAddUserOverrideModal',
  components: {
    GlAlert,
    GlFormGroup,
    GlFormInputGroup,
    GlInputGroupText,
    GlModal,
    GlToggle,
    UserOverrideSelect,
  },
  inject: {
    namespacePath: {
      default: null,
    },
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['hidden', 'saved'],
  data() {
    return this.defaultData();
  },
  computed: {
    selectedUserIds() {
      return this.selectedUsers.map((u) => u.id);
    },
    actionPrimary() {
      return {
        text: s__('UsageBilling|Save override'),
        attributes: {
          type: 'submit',
          form: 'add-user-cap-override-form',
          variant: 'confirm',
          loading: this.isSaving,
          disabled: !this.selectedUserIds.length,
          'data-testid': 'add-cap-override-submit-button',
        },
      };
    },
    actionCancel() {
      return {
        text: s__('UsageBilling|Cancel'),
        attributes: {
          form: 'add-user-cap-override-form',
          disabled: this.isSaving,
          'data-testid': 'add-cap-override-cancel-button',
        },
      };
    },
  },
  mounted() {
    this.reset();
  },
  methods: {
    defaultData() {
      return {
        selectedUsers: [],
        cap: 0,
        capEnabled: true,
        isSaving: false,
        errorMessage: null,
      };
    },
    onHidden() {
      if (this.isSaving) {
        toast(s__('UsageBilling|Saving in the background.'));
      } else {
        this.reset();
      }
      this.$emit('hidden');
    },
    reset() {
      Object.assign(this, this.defaultData());
    },
    async onSubmit() {
      if (this.isSaving) return;
      this.errorMessage = null;
      if (!this.selectedUserIds.length) return;

      try {
        this.isSaving = true;

        const overrides = this.selectedUserIds.map((userId) => ({
          userId,
          cap: Number(this.cap),
          enabled: this.capEnabled,
        }));

        const { data } = await this.$apollo.mutate({
          mutation: upsertUserOverridesMutation,
          variables: { namespacePath: this.namespacePath, overrides },
        });

        if (data?.upsertUserBudgetCapOverrides?.errors) {
          const errorMessages = data.upsertUserBudgetCapOverrides.errors;
          const errors = errorMessages.map((msg) => new Error(msg));

          if (errors.length === 1) throw errors[0];
          if (errors.length) {
            throw new AggregateError(
              errors,
              s__('UsageBilling|An error occurred while saving user cap override.'),
            );
          }
        }

        toast(s__('UsageBilling|Override saved.'));
        this.$emit('saved');
        this.reset();
        this.$emit('hidden');
      } catch (error) {
        this.errorMessage = error.message;
        logError(error);
        captureException(error);
      } finally {
        this.isSaving = false;
      }
    },
  },
};
</script>

<template>
  <gl-modal
    modal-id="add-user-cap-override-modal"
    :visible="visible"
    :title="s__('UsageBilling|Add override')"
    :action-primary="actionPrimary"
    :action-cancel="actionCancel"
    size="md"
    data-testid="add-user-cap-override-modal"
    @primary.prevent
    @hidden="onHidden"
  >
    <form id="add-user-cap-override-form" @submit.prevent="onSubmit">
      <gl-alert
        v-if="errorMessage"
        variant="danger"
        :dismissible="false"
        class="gl-mb-4"
        data-testid="add-cap-override-error-alert"
      >
        {{ errorMessage }}
      </gl-alert>

      <div class="gl-grid gl-grid-cols-3 gl-items-start gl-gap-4">
        <gl-form-group
          :label="s__('UsageBilling|Users')"
          label-for="user-override-select"
          class="gl-mb-0"
        >
          <user-override-select
            v-model="selectedUsers"
            input-id="user-override-select"
            :disabled="isSaving"
            data-testid="add-cap-override-user-select"
          />
        </gl-form-group>

        <gl-form-group :label="s__('UsageBilling|Override cap')" class="gl-mb-0 gl-shrink-0">
          <label for="add-cap-override-cap-input" class="gl-sr-only">
            {{ s__('UsageBilling|Override cap amount in credits') }}
          </label>
          <gl-form-input-group
            id="add-cap-override-cap-input"
            v-model.number="cap"
            type="number"
            min="0"
            step="1"
            required
            :disabled="isSaving"
            data-testid="add-cap-override-cap-input"
            class="gl-w-16"
          >
            <template #append>
              <gl-input-group-text>{{ s__('UsageBilling|credits') }}</gl-input-group-text>
            </template>
          </gl-form-input-group>
        </gl-form-group>

        <gl-form-group :label="s__('UsageBilling|Status')" class="gl-mb-0 gl-shrink-0">
          <div class="gl-flex gl-h-7 gl-items-center gl-gap-3">
            <gl-toggle
              id="add-cap-override-enabled"
              v-model="capEnabled"
              class="gl-h-7"
              :label="s__('UsageBilling|Enabled')"
              label-position="left"
              :disabled="isSaving"
              data-testid="add-cap-override-enabled-toggle"
            />
          </div>
        </gl-form-group>
      </div>
    </form>
  </gl-modal>
</template>
