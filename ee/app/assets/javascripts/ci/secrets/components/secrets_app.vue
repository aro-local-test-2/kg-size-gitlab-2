<script>
import { NetworkStatus } from '@apollo/client/core';
import { computed } from 'vue';
import { GlAlert, GlLink, GlLoadingIcon, GlSprintf, GlToastMixin } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { s__, sprintf } from '~/locale';
import { createAlert, VARIANT_SUCCESS } from '~/alert';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { fetchPolicies } from '~/lib/graphql';
import { getDayDifference } from '~/lib/utils/datetime_utility';
import { formatGraphQLError } from 'ee/ci/secrets/utils';
import enrollNamespaceMutation from 'ee/ci/secrets/graphql/mutations/enroll_namespace_secrets_manager.mutation.graphql';
import RouterViewWithSlot from '~/vue_shared/spa/components/router_view_with_slot';
import {
  BENIGN_ENROLL_ERRORS,
  BENIGN_PROVISION_ERRORS,
  BENIGN_TRIAL_ERRORS,
  ENTITLEMENT_STATE_BLOCKED,
  ENTITLEMENT_STATE_TRIAL,
  ENTITLEMENT_STATE_TRIAL_ELIGIBLE,
  ENTITY_GROUP,
  I18N_ADD_ON_ENABLED_ALERT,
  I18N_TRIAL_STARTED_ALERT,
  INDEX_ROUTE_NAME,
  NEW_ROUTE_NAME,
  POLL_INTERVAL,
  SECRET_MANAGER_STATUS_ACTIVE,
  SECRET_MANAGER_STATUS_ERROR,
  SECRET_MANAGER_STATUS_PROVISIONING,
  TRIAL_CREDITS_LOW_PERCENTAGE,
  TRIAL_EXPIRING_SOON_DAYS,
  TRIAL_ALERT_OPTIONS_BLOCKED,
  TRIAL_ALERT_OPTIONS_CREDITS_EXHAUSTED,
  TRIAL_ALERT_OPTIONS_CREDITS_LOW,
  TRIAL_ALERT_OPTIONS_TRIAL_EXPIRING,
} from '../constants';
import getEntitlementQuery from '../graphql/queries/get_secrets_manager_entitlement.graphql';
import getOpenbaoHealthQuery from '../graphql/queries/get_openbao_health.query.graphql';
import startTrialMutation from '../graphql/mutations/start_secrets_manager_trial.mutation.graphql';
import enableAddOnMutation from '../graphql/mutations/enable_secrets_manager_add_on.mutation.graphql';
import SecretsBetaTransitionAlert from './secrets_beta_transition_alert.vue';
import EnableAddOnModal from './enable_add_on_modal.vue';

export default {
  name: 'SecretsApp',
  SECRETS_MANAGER_BILLING_DOCS_LINK: helpPagePath('ci/secrets/secrets_manager/credit_usage'),
  components: {
    GlAlert,
    GlLink,
    GlLoadingIcon,
    GlSprintf,
    RouterViewWithSlot,
    SecretsBetaTransitionAlert,
    EnableAddOnModal,
  },
  mixins: [glFeatureFlagsMixin(), GlToastMixin],
  inject: ['contextConfig', 'fullPath', 'managePermissionsPath', 'topLevelGroupFullPath'],
  provide() {
    return {
      canDeleteSecrets: computed(() => this.canDeleteSecrets),
      entitlement: computed(() => this.entitlement),
      isBetaReadOnly: computed(() => this.isBetaReadOnly),
      isBetaUser: computed(() => this.isBetaUser),
      isEnablingAddOn: computed(() => this.isEnablingAddOn),
      isOpenbaoHealthy: computed(() => this.isOpenbaoHealthy),
      isProvisioning: computed(() => this.isProvisioning),
      isReadOnly: computed(() => this.isReadOnly),
      isTrialOnboarding: computed(() => this.isTrialOnboarding),
      secretManagerStatus: computed(() => this.secretManagerStatus),
      showTrialStartFlow: computed(() => this.showTrialStartFlow),
    };
  },
  data() {
    return {
      entitlement: null,
      entitlementNetworkStatus: NetworkStatus.loading,
      secretManagerStatus: undefined,
      isEntityBlocked: false,
      isStrictReadOnly: false,
      isOpenbaoHealthy: true,
      isProvisioning: false,
      isTrialOnboarding: false,
      isEnablingAddOn: false,
      showEnableAddOnModal: false,
      // Owner opt-in to the trial-start flow. Beta cohort users see a
      // read-only view once the beta program ends; the alert CTA (visible
      // to TLG Owners on the TLG page) flips this flag so the trial empty
      // state renders instead. Not persisted -- resets on remount.
      showTrialStartFlow: false,
    };
  },
  apollo: {
    entitlement: {
      query: getEntitlementQuery,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      notifyOnNetworkStatusChange: true,
      skip() {
        return !this.isPaidExperienceEnabled || !this.topLevelGroupFullPath;
      },
      variables() {
        return {
          fullPath: this.topLevelGroupFullPath,
        };
      },
      update(data) {
        return data.group?.secretsManagerEntitlement;
      },
      result({ networkStatus }) {
        this.entitlementNetworkStatus = networkStatus;
      },
      error(e) {
        createAlert({
          message: formatGraphQLError(e.message),
          captureError: true,
          error: e,
        });
      },
    },
    isOpenbaoHealthy: {
      query: getOpenbaoHealthQuery,
      update(data) {
        if (!data.openbaoHealth) {
          this.showOpenbaoUnhealthyAlert();
          this.redirectToIndex();
        }
        return data.openbaoHealth;
      },
      error() {
        this.isOpenbaoHealthy = false;
        this.showOpenbaoUnhealthyAlert();
        this.redirectToIndex();
      },
    },
    secretManagerStatus: {
      query() {
        return this.contextConfig.getStatus.query;
      },

      // need Boolean wrapper here because isPaidExperienceEnabled can be undefined
      // and Apollo treats non-boolean falsy values differently from false
      skip() {
        if (!this.isPaidExperienceEnabled) {
          return false;
        }

        // Beta cohort users keep read access during trial_eligible, so we
        // still need the status to render their secrets table (or the
        // trial empty state once they opt into the trial-start flow, which
        // is only reachable for beta users). Non-beta users skip the status
        // until the trial starts or they enable the add-on -- both need the
        // status to poll provisioning through to ACTIVE.
        const isSettingUpTrial =
          this.isTrialEligible &&
          !this.isTrialOnboarding &&
          !this.isEnablingAddOn &&
          !this.isBetaUser;
        return this.isEntitlementLoading || isSettingUpTrial;
      },
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        // when not provisioned, secretsManagerStatus will return null
        if (data.secretsManager == null) {
          this.$apollo.queries.secretManagerStatus.stopPolling();
          return null;
        }

        const {
          readOnly,
          status,
          entity: { archived, markedForDeletion },
        } = data.secretsManager;

        this.isEntityBlocked = archived || markedForDeletion;
        this.isStrictReadOnly = readOnly;

        // if the user visits the page while provisioning is already
        // in-progress, make sure we poll the status for changes
        if (status === SECRET_MANAGER_STATUS_PROVISIONING) {
          this.isProvisioning = true;
          this.$apollo.queries.secretManagerStatus.startPolling(POLL_INTERVAL);
        } else {
          this.$apollo.queries.secretManagerStatus.stopPolling();
        }

        return status;
      },
      error(e) {
        this.$apollo.queries.secretManagerStatus.stopPolling();
        this.secretManagerStatus = SECRET_MANAGER_STATUS_ERROR;
        createAlert({
          message: formatGraphQLError(e.message),
          captureError: true,
          error: e,
        });
      },
      pollInterval: POLL_INTERVAL,
    },
  },
  computed: {
    creditsRemainingPercentage() {
      const { creditsRemaining, creditsTotal } = this.entitlement;
      if (creditsRemaining == null) {
        return 0;
      }

      return (creditsRemaining / creditsTotal) * 100;
    },
    creditsRemainingPercentageText() {
      const percentage = this.creditsRemainingPercentage;

      // clamp sub-1% values to 1% so we never show a misleading 0% while credits
      // remain; exactly 0 is a real state when on-demand billing keeps the trial active
      return percentage > 0 && percentage < 1 ? 1 : Math.floor(percentage);
    },
    hasStatusError() {
      return this.secretManagerStatus && this.secretManagerStatus === SECRET_MANAGER_STATUS_ERROR;
    },
    isEntitlementLoading() {
      return this.$apollo.queries.entitlement.loading;
    },
    isEntitlementInitialLoading() {
      return this.isEntitlementLoading && this.entitlementNetworkStatus === NetworkStatus.loading;
    },
    // Whether this namespace opted in during the free-beta program. The
    // backend records it per realm (namespace enrollment `beta` on SaaS,
    // instance enrollment on self-managed), so the entitlement is the single
    // source of truth here. Beta users keep their secrets visible and
    // writable while `trial_eligible`; the transition banner itself stays
    // GitLab.com-only (see SecretsBetaTransitionAlert).
    isBetaUser() {
      return Boolean(this.entitlement?.betaWindowEligible);
    },
    isBetaProgramEnded() {
      return Boolean(this.entitlement?.betaProgramEnded);
    },
    // Beta users stay writable while trial_eligible until the entitlement
    // reports betaProgramEnded; only then does the view drop to read-only.
    // Opting into the trial-start flow also exits read-only.
    isBetaReadOnly() {
      return (
        this.isBetaUser &&
        this.isTrialEligible &&
        this.isBetaProgramEnded &&
        !this.showTrialStartFlow
      );
    },
    isReadOnly() {
      return (
        this.isEntityBlocked ||
        this.isStrictReadOnly ||
        this.entitlement?.state === ENTITLEMENT_STATE_BLOCKED ||
        this.isBetaReadOnly
      );
    },
    // Entitlement read-only states still permit deletes; only archived /
    // pending-deletion namespaces and a strict read-only instance refuse them.
    canDeleteSecrets() {
      return !this.isEntityBlocked && !this.isStrictReadOnly;
    },
    isPaidExperienceEnabled() {
      return this.glFeatures.secretsManagerPaidExperience;
    },
    isTrialEligible() {
      return this.entitlement?.state === ENTITLEMENT_STATE_TRIAL_ELIGIBLE;
    },
    isTrialExpiringSoon() {
      return (
        this.entitlement.state === ENTITLEMENT_STATE_TRIAL &&
        this.trialDaysRemaining !== null &&
        this.trialDaysRemaining <= TRIAL_EXPIRING_SOON_DAYS
      );
    },
    // "Initial" here means "we've never had a resolved value" -- distinct
    // from `isEntitlementLoading` which stays true across refetches and
    // background polls. In the paid experience we need entitlement first
    // (to know if the user is trial-eligible), and only wait on status if
    // the entitlement says we're past trial-eligible (trial-eligible users
    // skip the status query entirely, so `undefined` there is expected,
    // not "still loading").
    isLoadingInitialQueries() {
      if (this.isPaidExperienceEnabled) {
        return (
          this.isEntitlementInitialLoading ||
          (!this.isTrialEligible && this.secretManagerStatus === undefined)
        );
      }

      return this.secretManagerStatus === undefined;
    },
    trialAlertOptions() {
      if (!this.isPaidExperienceEnabled || !this.entitlement) {
        return null;
      }

      const { state, onDemandEnabled, blockedReason, creditsRemaining } = this.entitlement;

      if (state === ENTITLEMENT_STATE_BLOCKED) {
        return TRIAL_ALERT_OPTIONS_BLOCKED[blockedReason];
      }

      if (state === ENTITLEMENT_STATE_TRIAL) {
        // with on-demand billing on, the trial stays active at 0 credits and
        // overage charges start immediately, so this state needs its own copy
        if (onDemandEnabled && creditsRemaining === 0) {
          return TRIAL_ALERT_OPTIONS_CREDITS_EXHAUSTED;
        }
        if (this.creditsRemainingPercentage <= TRIAL_CREDITS_LOW_PERCENTAGE) {
          return onDemandEnabled
            ? TRIAL_ALERT_OPTIONS_CREDITS_LOW.onDemandEnabled
            : TRIAL_ALERT_OPTIONS_CREDITS_LOW.onDemandDisabled;
        }
        if (this.isTrialExpiringSoon) {
          return onDemandEnabled
            ? TRIAL_ALERT_OPTIONS_TRIAL_EXPIRING.onDemandEnabled
            : TRIAL_ALERT_OPTIONS_TRIAL_EXPIRING.onDemandDisabled;
        }
      }

      return null;
    },
    trialAlertTitle() {
      if (!this.trialAlertOptions) {
        return '';
      }
      return sprintf(this.trialAlertOptions.title, {
        creditsRemaining: this.creditsRemainingPercentageText,
        trialDaysRemaining: this.trialDaysRemaining,
      });
    },
    trialDaysRemaining() {
      if (!this.entitlement.trialExpiresAt) {
        return null;
      }

      return getDayDifference(new Date(), new Date(this.entitlement.trialExpiresAt));
    },
    provisioningSuccessMessage() {
      return this.contextConfig.type === ENTITY_GROUP
        ? s__(
            'SecretsManager|GitLab Secrets Manager has been enabled for this group. %{linkStart}Manage permissions.%{linkEnd}',
          )
        : s__(
            'SecretsManager|GitLab Secrets Manager has been enabled for this project. %{linkStart}Manage permissions.%{linkEnd}',
          );
    },
  },
  watch: {
    // Finalizes both provisioning flows:
    //   - Subgroup/project "New secret" button: routes to the new-secret
    //     form and shows a scope-specific success alert.
    //   - TLG trial chain (`startTrial`): refetches the entitlement so the
    //     UI moves out of the trial empty state, then shows the trial-
    //     started alert.
    // On ERROR, both flows surface a failure alert and let the user retry.
    secretManagerStatus(newStatus) {
      if (!this.isProvisioning) return;

      if (newStatus === SECRET_MANAGER_STATUS_ERROR) {
        this.isProvisioning = false;

        if (this.isTrialOnboarding) {
          this.isTrialOnboarding = false;
        }

        if (this.isEnablingAddOn) {
          this.isEnablingAddOn = false;
        }

        createAlert({
          message: s__(
            'SecretsManager|Something went wrong while setting up the secrets manager. Please try again.',
          ),
          captureError: true,
        });
        return;
      }

      if (newStatus !== SECRET_MANAGER_STATUS_ACTIVE) return;

      this.isProvisioning = false;

      if (this.isTrialOnboarding) {
        this.isTrialOnboarding = false;
        this.$apollo.queries.entitlement.refetch();
        createAlert({
          message: I18N_TRIAL_STARTED_ALERT,
          messageLinks: { link: this.managePermissionsPath },
          variant: VARIANT_SUCCESS,
        });
        return;
      }

      if (this.isEnablingAddOn) {
        this.finalizeAddOnEnable();
        return;
      }

      this.$router.push({ name: NEW_ROUTE_NAME });
      createAlert({
        message: this.provisioningSuccessMessage,
        messageLinks: { link: this.managePermissionsPath },
        variant: VARIANT_SUCCESS,
      });
    },
  },
  methods: {
    showOpenbaoUnhealthyAlert() {
      createAlert({
        title: s__('SecretsManager|Cannot connect to OpenBao'),
        message: s__(
          'SecretsManager|Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
        ),
      });
    },
    redirectToIndex() {
      if (this.$route?.name !== INDEX_ROUTE_NAME) {
        this.$router.push({ name: INDEX_ROUTE_NAME });
      }
    },
    // Fires the initialize mutation and refetches the status query so
    // polling picks up (PROVISIONING → ACTIVE). Errors listed in
    // benignErrors are swallowed so callers chaining retries after partial
    // progress see a no-op instead of a failure.
    async runProvisioningMutation({ benignErrors = [] } = {}) {
      this.isProvisioning = true;

      const { data } = await this.$apollo.mutate({
        mutation: this.contextConfig.enableSecretsManager.mutation,
        variables: { fullPath: this.fullPath },
      });

      const { errors } = this.contextConfig.enableSecretsManager.lookup(data) || {};

      if (errors?.length && !benignErrors.includes(errors[0])) {
        throw new Error(errors[0]);
      }

      await this.$apollo.queries.secretManagerStatus.refetch();
    },
    async provisionSecretsManager() {
      try {
        await this.runProvisioningMutation();
      } catch (error) {
        this.isProvisioning = false;
        createAlert({
          message: s__(
            'SecretsManager|There was a problem enabling the GitLab Secrets Manager. Try again later.',
          ),
          captureError: true,
          error,
        });
      }
    },
    showSecretsToast(message) {
      this.$toast.show(message);
    },
    // Beta cohort's alert CTA opts a TLG Owner into the trial-start flow.
    // Flips the app out of the beta read-only view and into the standard
    // trial empty state where the trial mutation chain can run.
    handleStartTrialFlow() {
      this.showTrialStartFlow = true;
    },
    // Runs one step of the trial-button onboarding chain. Treats any error
    // in benignErrors (backend messages like "already enrolled" / "trial
    // already active") as success so the chain can proceed to the next step.
    // Non-benign errors throw so the caller can short-circuit the rest of
    // the chain.
    async runOnboardingMutation({ mutation, variables, payloadKey, benignErrors = [] }) {
      const { data } = await this.$apollo.mutate({ mutation, variables });
      const { errors } = data[payloadKey] || {};

      if (!errors?.length) return;
      if (benignErrors.includes(errors[0])) return;

      throw new Error(errors[0]);
    },
    // TLG one-click onboarding: enroll → start trial → provision. This
    // method only fires the three mutations; the `secretManagerStatus`
    // watcher above finalizes the chain (refetches the entitlement, shows
    // the success alert) once polling reaches ACTIVE. Each mutation step
    // swallows its benign "already done" error so retries after partial
    // progress no-op. On failure at any step we reset the onboarding flag
    // so the trial empty state stays visible for retry.
    async startTrial() {
      if (this.isTrialOnboarding || this.isEnablingAddOn) return;

      this.isTrialOnboarding = true;

      try {
        await this.runOnboardingMutation({
          mutation: enrollNamespaceMutation,
          variables: { fullPath: this.topLevelGroupFullPath },
          payloadKey: 'namespaceSecretsManagerEnroll',
          benignErrors: BENIGN_ENROLL_ERRORS,
        });

        await this.runOnboardingMutation({
          mutation: startTrialMutation,
          variables: { groupPath: this.topLevelGroupFullPath },
          payloadKey: 'secretsManagerStartTrial',
          benignErrors: BENIGN_TRIAL_ERRORS,
        });

        await this.runProvisioningMutation({ benignErrors: BENIGN_PROVISION_ERRORS });
      } catch (error) {
        this.isTrialOnboarding = false;
        this.isProvisioning = false;
        createAlert({
          message:
            error.message || s__('SecretsManager|An error occurred while starting the trial.'),
          captureError: true,
          error,
        });
      }
    },
    finalizeAddOnEnable() {
      this.isEnablingAddOn = false;
      this.isProvisioning = false;
      this.$apollo.queries.entitlement.refetch();
      createAlert({
        message: I18N_ADD_ON_ENABLED_ALERT,
        messageLinks: { link: this.managePermissionsPath },
        variant: VARIANT_SUCCESS,
      });
    },
    async enableAddOn() {
      if (this.isEnablingAddOn || this.isTrialOnboarding) return;

      this.showEnableAddOnModal = false;
      this.isEnablingAddOn = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: enableAddOnMutation,
          variables: { groupPath: this.topLevelGroupFullPath },
        });

        const { errors } = data.secretsManagerEnableAddOn || {};
        if (errors?.length) {
          throw new Error(errors[0]);
        }

        await this.$apollo.queries.secretManagerStatus.refetch();

        if (this.secretManagerStatus === SECRET_MANAGER_STATUS_ACTIVE) {
          this.finalizeAddOnEnable();
        } else {
          this.isProvisioning = true;
        }
      } catch (error) {
        this.isEnablingAddOn = false;
        this.isProvisioning = false;
        createAlert({
          message:
            error.message ||
            s__('SecretsManager|An error occurred while enabling GitLab Secrets Manager.'),
          captureError: true,
          error,
        });
      }
    },
  },
};
</script>
<template>
  <!-- Only show loading icon on initial fetch. Subsequent refetches and polls should not unmount the router view, which would reset local component state (e.g. the empty state's provisioning button spinner). -->
  <gl-loading-icon
    v-if="isLoadingInitialQueries"
    data-testid="secrets-manager-loading-status"
    class="gl-mt-5"
  />
  <div v-else-if="!hasStatusError">
    <gl-alert
      v-if="isPaidExperienceEnabled && trialAlertOptions"
      :variant="trialAlertOptions.variant"
      :title="trialAlertTitle"
      :dismissible="false"
      class="gl-my-5"
      data-testid="secrets-trial-alert"
    >
      <gl-sprintf :message="trialAlertOptions.description">
        <template #link="{ content }">
          <gl-link :href="$options.SECRETS_MANAGER_BILLING_DOCS_LINK" target="_blank">{{
            content
          }}</gl-link>
        </template>
      </gl-sprintf>
    </gl-alert>
    <secrets-beta-transition-alert
      :is-beta="isBetaUser"
      :is-trial-eligible="isTrialEligible"
      :beta-program-ended="isBetaProgramEnded"
      :is-enabling-add-on="isEnablingAddOn"
      :is-trial-onboarding="isTrialOnboarding"
      @start-trial="handleStartTrialFlow"
      @enable-add-on="showEnableAddOnModal = true"
    />
    <enable-add-on-modal
      :visible="showEnableAddOnModal"
      :on-demand-enabled="Boolean(entitlement && entitlement.onDemandEnabled)"
      @enable="enableAddOn"
      @hide="showEnableAddOnModal = false"
    />
    <router-view-with-slot #default="{ Component }">
      <component
        :is="Component"
        ref="router-view"
        @provision-secrets-manager="provisionSecretsManager"
        @show-secrets-toast="showSecretsToast"
        @start-trial="startTrial"
        @enable-add-on="showEnableAddOnModal = true"
      />
    </router-view-with-slot>
  </div>
</template>
