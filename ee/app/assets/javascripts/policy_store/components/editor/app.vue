<script>
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__, sprintf } from '~/locale';
import { joinPaths, visitUrl, visitUrlWithAlerts } from '~/lib/utils/url_utility';
import { createAlert } from '~/alert';
import { fetchPolicy, createPolicy, updatePolicy, NAMESPACE_TYPE_GROUP } from '../../policies';
import { apiErrorMessage, isDuplicateNameError, isRuleRegoParseError } from '../../utils';
import { serializePolicyParams } from './serializer';
import StepWizard from './step_wizard.vue';

export default {
  name: 'PolicyStoreEditorRoot',
  components: {
    GlAlert,
    GlLoadingIcon,
    StepWizard,
  },
  i18n: {
    policyError: s__(
      'PolicyStore|The policy could not be loaded from the Policy Store API. Refresh the page to try again.',
    ),
    saveError: s__('PolicyStore|The policy could not be saved. Try again.'),
    policyCreated: s__('PolicyStore|Policy %{name} was created.'),
    policyUpdated: s__('PolicyStore|Policy %{name} was updated.'),
    duplicateNameError: s__(
      'PolicyStore|A policy with this name already exists. Choose a different name.',
    ),
  },
  inject: {
    organizationId: {},
    namespacePath: { default: '' },
    namespaceType: {},
    policyId: { default: '' },
    listPath: { default: '' },
  },
  data() {
    return {
      editingPolicy: null,
      policyLoading: false,
      policyError: false,
      saving: false,
      nameError: '',
    };
  },
  computed: {
    detailPath() {
      return this.listPath && this.policyId ? joinPaths(this.listPath, this.policyId) : '';
    },
    isGroupContext() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP;
    },
    namespaceIdentifier() {
      return this.isGroupContext ? this.namespacePath : this.organizationId;
    },
  },
  created() {
    // The blank "new" page has no policy to resolve, so only edit fetches one.
    if (this.policyId) this.loadPolicy();
  },
  methods: {
    // The wizard reads its policy prop once, on mount, so the editor renders
    // only after this settles rather than mounting empty and never refilling.
    async loadPolicy() {
      this.policyLoading = true;

      try {
        this.editingPolicy = await fetchPolicy(
          this.namespaceType,
          this.namespaceIdentifier,
          this.policyId,
        );
      } catch (error) {
        Sentry.captureException(error);
        this.policyError = true;
      } finally {
        this.policyLoading = false;
      }
    },
    async onSave(wizardState) {
      this.saving = true;
      this.nameError = '';

      const params = serializePolicyParams(wizardState);

      // An untouched Scope step is not sent on update, so a scope authored
      // through the API (hand-written Rego, groups, frameworks) is not
      // overwritten by the wizard's project-only view of it.
      if (this.policyId && !wizardState.scopeChanged) delete params.policy_scope;

      try {
        if (this.policyId) {
          await updatePolicy({
            namespaceType: this.namespaceType,
            namespaceIdentifier: this.namespaceIdentifier,
            policyId: this.policyId,
            params,
          });
          // An edit returns to the detail view it came from, so the updated
          // configuration is what the user lands on.
          this.leaveWithConfirmation(this.detailPath, {
            id: 'policy-store-policy-updated',
            message: sprintf(this.$options.i18n.policyUpdated, { name: params.name }),
          });
        } else {
          await createPolicy(this.namespaceType, this.namespaceIdentifier, params);
          this.leaveWithConfirmation(this.listPath, {
            id: 'policy-store-policy-created',
            message: sprintf(this.$options.i18n.policyCreated, { name: params.name }),
          });
        }
      } catch (error) {
        const message = apiErrorMessage(error);

        // A duplicate name is ordinary user input: it belongs on the name
        // field, not in a page alert, and is not worth tracking as a failure.
        if (isDuplicateNameError(message)) {
          this.nameError = this.$options.i18n.duplicateNameError;
        } else {
          // A parse failure is author input, not a bug. Where it belongs in the
          // editor is still open: https://gitlab.com/gitlab-org/gitlab/-/work_items/629577
          if (!isRuleRegoParseError(message)) Sentry.captureException(error);

          createAlert({ message: message || this.$options.i18n.saveError });
        }

        this.saving = false;
      }
    },
    // Cancel mirrors save: an edit returns to the detail view it came from,
    // a new policy returns to the list.
    onCancel() {
      const path = this.policyId ? this.detailPath : this.listPath;

      if (path) visitUrl(path);
    },
    leaveWithConfirmation(path, alert) {
      if (path) visitUrlWithAlerts(path, [{ ...alert, variant: 'success' }]);
    },
  },
};
</script>

<template>
  <gl-loading-icon v-if="policyLoading" size="lg" class="gl-mt-6" data-testid="policy-loading" />
  <gl-alert
    v-else-if="policyError"
    variant="danger"
    :dismissible="false"
    class="gl-mt-4"
    data-testid="policy-error"
  >
    {{ $options.i18n.policyError }}
  </gl-alert>
  <step-wizard
    v-else
    :policy="editingPolicy"
    :saving="saving"
    :name-error="nameError"
    @cancel="onCancel"
    @save="onSave"
    @name-update="nameError = ''"
  />
</template>
