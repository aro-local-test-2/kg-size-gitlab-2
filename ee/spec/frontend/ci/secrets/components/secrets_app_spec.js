import { GlLink, GlSprintf } from '@gitlab/ui';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import Vue, { nextTick } from 'vue';
import { createAlert, VARIANT_SUCCESS } from '~/alert';
import { helpPagePath } from '~/helpers/help_page_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createRouter from 'ee/ci/secrets/router';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import SecretsApp from 'ee/ci/secrets/components/secrets_app.vue';
import SecretsBetaTransitionAlert from 'ee/ci/secrets/components/secrets_beta_transition_alert.vue';
import SecretsEmptyState from 'ee/ci/secrets/components/secrets_empty_state.vue';
import SecretsTrialEmptyState from 'ee/ci/secrets/components/secrets_table/secrets_trial_empty_state.vue';
import SecretActionsCell from 'ee/ci/secrets/components/secrets_table/secret_actions_cell.vue';
import { SECRETS_MANAGER_CONTEXT_CONFIG } from 'ee/ci/secrets/context_config';
import enrollNamespaceMutation from 'ee/ci/secrets/graphql/mutations/enroll_namespace_secrets_manager.mutation.graphql';
import getOpenbaoHealthQuery from 'ee/ci/secrets/graphql/queries/get_openbao_health.query.graphql';
import getEntitlementQuery from 'ee/ci/secrets/graphql/queries/get_secrets_manager_entitlement.graphql';
import startTrialMutation from 'ee/ci/secrets/graphql/mutations/start_secrets_manager_trial.mutation.graphql';
import enableAddOnMutation from 'ee/ci/secrets/graphql/mutations/enable_secrets_manager_add_on.mutation.graphql';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';
import {
  BLOCKED_REASON_CREDITS_EXHAUSTED,
  BLOCKED_REASON_GRACE,
  BLOCKED_REASON_ON_DEMAND_DISABLED,
  BLOCKED_REASON_SUBSCRIPTION_GRACE_PERIOD_EXPIRED,
  BLOCKED_REASON_TRIAL_EXPIRED,
  POLL_INTERVAL,
  ENTITY_GROUP,
  ENTITY_PROJECT,
  SECRET_MANAGER_STATUS_ACTIVE,
  SECRET_MANAGER_STATUS_PROVISIONING,
} from 'ee/ci/secrets/constants';
import {
  enableSecretManagerResponse,
  enrollNamespaceAlreadyEnrolledResponse,
  enrollNamespaceErrorResponse,
  enrollNamespaceSuccessResponse,
  entitlementResponse,
  mockGroupSecretsResponse,
  mockProjectSecretsResponse,
  openbaoHealthResponse,
  secretManagerStatusResponse,
  startTrialSuccessResponse,
  startTrialErrorResponse,
  enableAddOnSuccessResponse,
  enableAddOnErrorResponse,
} from '../mock_data';

jest.mock('~/alert');

describe('SecretsApp', () => {
  let wrapper;
  let apolloProvider;
  let mockSecretManagerStatus;
  let mockOpenbaoHealth;
  let mockEntitlementQuery;
  let mockEnableSecretsManager;
  let mockEnrollNamespace;
  let mockStartTrial;
  let mockEnableAddOn;

  Vue.use(VueRouter);
  Vue.use(VueApollo);
  const mockToastShow = jest.fn();

  const findRouterView = () => wrapper.findComponent({ ref: 'router-view' });

  const managePermissionsPath = '/path/to/edit#js-shared-permissions';

  const defaultProvide = {
    canStartTrial: false,
    fullPath: '/path/to/entity',
    managePermissionsPath,
    subscriptionsUrl: 'https://customers.example.com',
    topLevelGroupFullPath: '',
    isSaas: false,
  };

  const createRouterForTest = () => createRouter('/-/secrets');

  const createComponent = async ({
    stubs,
    router,
    provide,
    isLoading = false,
    context = ENTITY_PROJECT,
    secretsListResponse = { data: { secretsList: { edges: [] } } },
  } = {}) => {
    const contextConfig = SECRETS_MANAGER_CONTEXT_CONFIG[context];
    const handlers = [
      [contextConfig.getStatus.query, mockSecretManagerStatus],
      [getOpenbaoHealthQuery, mockOpenbaoHealth],
      [getEntitlementQuery, mockEntitlementQuery],
      [contextConfig.enableSecretsManager.mutation, mockEnableSecretsManager],
      [enrollNamespaceMutation, mockEnrollNamespace],
      [startTrialMutation, mockStartTrial],
      [enableAddOnMutation, mockEnableAddOn],
      [contextConfig.getSecrets.query, jest.fn().mockResolvedValue(secretsListResponse)],
      [
        contextConfig.getSecretsNeedingRotation.query,
        jest.fn().mockResolvedValue({ data: { secretsNeedingRotation: { nodes: [] } } }),
      ],
    ];

    apolloProvider = createMockApollo(handlers);

    wrapper = mountExtended(SecretsApp, {
      router: router || createRouterForTest(),
      provide: {
        contextConfig,
        ...defaultProvide,
        ...provide,
      },
      stubs,
      apolloProvider,
      mocks: {
        $toast: { show: mockToastShow },
      },
    });

    if (!isLoading) {
      await waitForPromises();
      await nextTick();
    }
  };

  const createPaidExperienceComponent = async (provide = {}) => {
    await createComponent({
      provide: {
        glFeatures: {
          secretsManagerPaidExperience: true,
        },
        isSaas: true,
        topLevelGroupFullPath: 'top-level-group',
        ...provide,
      },
      stubs: {
        GlSprintf,
      },
    });
  };

  const findEmptyState = () => wrapper.findComponent(SecretsEmptyState);
  const findSecretActionsCell = () => wrapper.findComponent(SecretActionsCell);
  const findNewSecretButton = () => wrapper.findComponentByTestId('new-secret-button');
  const findTrialEmptyState = () => wrapper.findComponent(SecretsTrialEmptyState);
  const findEmptyStateNewSecretBtn = () =>
    wrapper.findComponentByTestId('empty-state-new-secret-button');
  const findLoadingIcon = () => wrapper.findByTestId('secrets-manager-loading-status');
  const findTrialAlert = () => wrapper.findComponentByTestId('secrets-trial-alert');
  const findTrialAlertLink = () => findTrialAlert().findComponent(GlLink);
  const findBetaTransitionAlert = () => wrapper.findComponent(SecretsBetaTransitionAlert);
  const findEnableAddOnModal = () => wrapper.findComponent(EnableAddOnModal);

  const advanceToNextFetch = (milliseconds) => {
    jest.advanceTimersByTime(milliseconds);
  };

  const pollNextStatus = async (status, context = 'project') => {
    mockSecretManagerStatus.mockResolvedValue(secretManagerStatusResponse(status, context));
    advanceToNextFetch(POLL_INTERVAL);

    await waitForPromises();
    await nextTick();
  };

  beforeEach(() => {
    mockSecretManagerStatus = jest.fn();
    mockOpenbaoHealth = jest.fn();
    mockEntitlementQuery = jest.fn().mockResolvedValue(entitlementResponse({ state: 'TRIAL' }));
    mockEnableSecretsManager = jest.fn();
    mockEnrollNamespace = jest.fn().mockResolvedValue(enrollNamespaceSuccessResponse());
    mockStartTrial = jest.fn().mockResolvedValue(startTrialSuccessResponse());
    mockEnableAddOn = jest.fn().mockResolvedValue(enableAddOnSuccessResponse());

    mockSecretManagerStatus.mockResolvedValue(
      secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE),
    );
    mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(true));
  });

  describe.each`
    context
    ${ENTITY_PROJECT}
    ${ENTITY_GROUP}
  `('SecretsApp in $context context', ({ context }) => {
    beforeEach(() => {
      mockSecretManagerStatus.mockClear();
      mockSecretManagerStatus.mockResolvedValue(
        secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context),
      );
    });

    describe('skipping secrets manager status query', () => {
      it('skips status query while entitlement is loading', async () => {
        mockEntitlementQuery.mockReturnValue(new Promise(() => {}));
        await createComponent({
          provide: {
            glFeatures: { secretsManagerPaidExperience: true },
            topLevelGroupFullPath: 'top-level-group',
          },
          isLoading: true,
        });

        expect(mockSecretManagerStatus).not.toHaveBeenCalled();
        expect(findLoadingIcon().exists()).toBe(true);
      });

      it('skips status query when trial eligible', async () => {
        mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL_ELIGIBLE' }));
        await createComponent({
          provide: {
            glFeatures: { secretsManagerPaidExperience: true },
            topLevelGroupFullPath: 'top-level-group',
          },
          stubs: { GlSprintf },
        });

        expect(mockSecretManagerStatus).not.toHaveBeenCalled();
        expect(findLoadingIcon().exists()).toBe(false);
      });

      it('runs status query after entitlement resolves as non-trial-eligible', async () => {
        mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL' }));
        await createComponent({
          provide: {
            glFeatures: { secretsManagerPaidExperience: true },
            topLevelGroupFullPath: 'top-level-group',
          },
        });

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
        expect(findLoadingIcon().exists()).toBe(false);
        expect(findRouterView().exists()).toBe(true);
      });

      it('does not show loading icon when status query returns null', async () => {
        mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL' }));
        mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
        await createComponent({
          provide: {
            glFeatures: { secretsManagerPaidExperience: true },
            topLevelGroupFullPath: 'top-level-group',
          },
        });

        expect(findLoadingIcon().exists()).toBe(false);
        expect(findRouterView().exists()).toBe(true);
      });
    });

    describe('when secrets manager status is being fetched', () => {
      beforeEach(() => {
        createComponent({ isLoading: true, context });
      });

      it('renders the loading state', () => {
        expect(findLoadingIcon().exists()).toBe(true);
      });

      it('does not render the router view', () => {
        expect(findRouterView().exists()).toBe(false);
      });
    });

    describe('when secrets manager is being provisioned', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, context),
        );
        await createComponent({ context });
      });

      // empty state owns the provisioning UI
      it('renders the router view', () => {
        expect(findRouterView().exists()).toBe(true);
      });

      it('does not render the loading state', () => {
        expect(findLoadingIcon().exists()).toBe(false);
      });

      it('polls for updated status while provisioning', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        await pollNextStatus(SECRET_MANAGER_STATUS_PROVISIONING, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);
      });

      it('stops polling when provisioned', async () => {
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);

        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);
      });
    });

    // e.g. provisioning was started in another tab and the user
    // opened/refreshed this page mid-provisioning.
    describe('when the page loads while provisioning is already in-progress', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, context),
        );
        await createComponent({ context, router: createRouterForTest(context) });
      });

      it('shows the loading button in the empty state', () => {
        expect(findEmptyStateNewSecretBtn().props('loading')).toBe(true);
      });

      it('fires the success flow when status flips to ACTIVE', async () => {
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(createAlert).toHaveBeenCalled();
      });
    });

    describe('when secrets manager has been provisioned', () => {
      beforeEach(async () => {
        await createComponent({ context });
      });

      it('renders the router view', () => {
        expect(findRouterView().exists()).toBe(true);
      });

      it('stops polling for status', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
      });
    });

    describe('when secrets manager is not provisioned', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
        await createComponent({ context });
      });

      it('stops polling', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        await pollNextStatus(null, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
      });
    });

    describe('when there is an error with fetching the secrets manager status', () => {
      const error = new Error('GraphQL error: API error');

      beforeEach(async () => {
        mockSecretManagerStatus.mockRejectedValue(error);
        await createComponent({ context });
      });

      it('renders an error message', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'API error',
          captureError: true,
          error,
        });
      });

      it('stops polling', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        advanceToNextFetch(POLL_INTERVAL);

        await waitForPromises();
        await nextTick();

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
      });

      it('does not render the loading state or router view', () => {
        expect(findLoadingIcon().exists()).toBe(false);
        expect(findRouterView().exists()).toBe(false);
      });
    });

    describe('when entity is not archived or marked for deletion', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, {
            entity: { archived: false, markedForDeletion: false },
          }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
        });
      });

      it('shows action buttons', () => {
        expect(findEmptyStateNewSecretBtn().exists()).toBe(true);
      });
    });

    describe('when entity is archived', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, {
            entity: { archived: true, markedForDeletion: false },
          }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
        });
      });

      it('sets secrets manager to read-only mode by hiding action buttons', () => {
        expect(findEmptyStateNewSecretBtn().exists()).toBe(false);
      });
    });

    describe('when entity is marked for deletion', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, {
            entity: { archived: false, markedForDeletion: true },
          }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
        });
      });

      it('sets secrets manager to read-only mode by hiding action buttons', () => {
        expect(findEmptyStateNewSecretBtn().exists()).toBe(false);
      });
    });

    describe('when the instance is in strict read-only mode', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, { readOnly: true }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
          secretsListResponse:
            context === ENTITY_GROUP ? mockGroupSecretsResponse() : mockProjectSecretsResponse(),
        });
      });

      it('hides all actions, including delete', () => {
        expect(findNewSecretButton().exists()).toBe(false);
        expect(findSecretActionsCell().exists()).toBe(false);
      });
    });
  });

  describe('toast message', () => {
    beforeEach(async () => {
      await createComponent({
        router: createRouterForTest(ENTITY_PROJECT),
      });
    });

    it('renders toast message when show-secrets-toast is emitted', async () => {
      findRouterView().vm.$emit('show-secrets-toast', 'This is a toast message.');
      await nextTick();

      expect(mockToastShow).toHaveBeenCalledWith('This is a toast message.');
    });
  });

  describe('when OpenBao is unhealthy', () => {
    beforeEach(async () => {
      mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(false));
      await createComponent({
        router: createRouterForTest(ENTITY_PROJECT),
      });
    });

    it('shows an alert with unhealthy message', () => {
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Cannot connect to OpenBao',
        message:
          'Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
      });
    });

    it('renders the router view', () => {
      expect(findRouterView().exists()).toBe(true);
    });

    it('redirects to index route when on a different route', async () => {
      const router = createRouterForTest(ENTITY_PROJECT);
      await router.push({ name: 'new' }).catch(() => {});

      mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(false));
      await createComponent({ router });

      expect(router.currentRoute.name).toBe('index');
    });
  });

  describe('when OpenBao health query fails', () => {
    beforeEach(async () => {
      mockOpenbaoHealth.mockRejectedValue(new Error('Network error'));
      await createComponent({
        router: createRouter('/-/secrets'),
      });
    });

    it('shows an alert with unhealthy message', () => {
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Cannot connect to OpenBao',
        message:
          'Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
      });
    });

    it('renders the router view', () => {
      expect(findRouterView().exists()).toBe(true);
    });
  });

  describe('entitlement query', () => {
    it('calls the entitlement query with the correct variables', async () => {
      await createPaidExperienceComponent();

      expect(mockEntitlementQuery).toHaveBeenCalledWith({ fullPath: 'top-level-group' });
    });

    it('renders an error when entitlement query fails', async () => {
      const error = new Error('GraphQL error: Entitlement error');
      mockEntitlementQuery.mockRejectedValue(error);
      await createPaidExperienceComponent();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Entitlement error',
        captureError: true,
        error,
      });
    });

    it('skips the entitlement query when feature flag is disabled', async () => {
      await createPaidExperienceComponent({
        glFeatures: { secretsManagerPaidExperience: false },
      });

      expect(mockEntitlementQuery).not.toHaveBeenCalled();
    });

    it('skips the entitlement query when topLevelGroupFullPath is empty', async () => {
      await createPaidExperienceComponent({ topLevelGroupFullPath: '' });

      expect(mockEntitlementQuery).not.toHaveBeenCalled();
    });

    it('shows loading state when entitlement query is skipped but status is still loading', async () => {
      mockSecretManagerStatus.mockReturnValue(new Promise(() => {}));
      await createPaidExperienceComponent({ topLevelGroupFullPath: '' });

      expect(findLoadingIcon().exists()).toBe(true);
      expect(findRouterView().exists()).toBe(false);
    });

    describe('when entitlement state is blocked', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'BLOCKED', blockedReason: 'TRIAL_EXPIRED' }),
        );
        await createComponent({
          provide: {
            glFeatures: { secretsManagerPaidExperience: true },
            topLevelGroupFullPath: 'top-level-group',
          },
          secretsListResponse: mockProjectSecretsResponse(),
        });
      });

      it('allows only deletes', () => {
        expect(findNewSecretButton().exists()).toBe(false);
        expect(findSecretActionsCell().props()).toMatchObject({
          canUpdate: false,
          canDelete: true,
        });
      });
    });
  });

  describe('trial alerts', () => {
    const expiryTwoDays = new Date(Date.now() + 172800000).toISOString();
    const expiryThirtyDays = new Date(Date.now() + 2592000000).toISOString();

    it('does not render trial alert when feature flag is disabled', async () => {
      await createPaidExperienceComponent({
        glFeatures: { secretsManagerPaidExperience: false },
      });

      expect(findTrialAlert().exists()).toBe(false);
    });

    it('does not render trial alert when trial is active with sufficient credits and time', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({
          state: 'TRIAL',
          creditsRemaining: 400,
          creditsTotal: 500,
          trialExpiresAt: expiryThirtyDays,
          onDemandEnabled: true,
        }),
      );
      await createPaidExperienceComponent();

      expect(findTrialAlert().exists()).toBe(false);
    });

    describe('when trial credits are low', () => {
      it('renders a warning alert with on-demand enabled message', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL',
            creditsRemaining: 5,
            creditsTotal: 500,
            trialExpiresAt: expiryTwoDays,
            onDemandEnabled: true,
          }),
        );
        await createPaidExperienceComponent();

        expect(findTrialAlert().props('variant')).toBe('warning');
        expect(findTrialAlert().props('title')).toBe('1% of credits left in secrets manager trial');
        expect(findTrialAlert().text()).toContain(
          'On-demand billing is enabled, and you will incur charges after the trial period ends.',
        );
        expect(findTrialAlertLink().attributes('href')).toBe(
          helpPagePath('ci/secrets/secrets_manager/credit_usage'),
        );
      });

      it('renders a warning alert with on-demand disabled message', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL',
            creditsRemaining: 5,
            creditsTotal: 500,
            trialExpiresAt: expiryTwoDays,
            onDemandEnabled: false,
          }),
        );
        await createPaidExperienceComponent();

        expect(findTrialAlert().props('variant')).toBe('warning');
        expect(findTrialAlert().props('title')).toBe('1% of credits left in secrets manager trial');
        expect(findTrialAlert().text()).toContain(
          'Contact your billing administrator to enable on-demand billing and avoid disruption.',
        );
      });

      it('rounds nonzero percentages below 1% up to 1%', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL',
            creditsRemaining: 2,
            creditsTotal: 500,
            trialExpiresAt: expiryTwoDays,
            onDemandEnabled: true,
          }),
        );
        await createPaidExperienceComponent();

        expect(findTrialAlert().props('title')).toBe('1% of credits left in secrets manager trial');
      });

      // regression: a fractional balance below 1 must render as low credits,
      // not as the credits-exhausted alert (only exactly 0 is exhausted)
      it('does not treat a fractional balance below 1 credit as exhausted', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL',
            creditsRemaining: 0.1,
            creditsTotal: 500,
            trialExpiresAt: expiryThirtyDays,
            onDemandEnabled: true,
          }),
        );
        await createPaidExperienceComponent();

        expect(findTrialAlert().props('title')).toBe('1% of credits left in secrets manager trial');
      });
    });

    describe('when trial credits are exhausted and on-demand is enabled', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL',
            creditsRemaining: 0,
            creditsTotal: 500,
            trialExpiresAt: expiryThirtyDays,
            onDemandEnabled: true,
          }),
        );
        await createPaidExperienceComponent();
      });

      it('renders a warning alert with credits exhausted message', () => {
        expect(findTrialAlert().props('variant')).toBe('warning');
        expect(findTrialAlert().props('title')).toBe('All trial credits used');
        expect(findTrialAlert().text()).toContain(
          'On-demand billing is enabled, and you are incurring charges for continued usage.',
        );
        expect(findTrialAlertLink().attributes('href')).toBe(
          helpPagePath('ci/secrets/secrets_manager/credit_usage'),
        );
      });
    });

    describe('when trial is expiring soon', () => {
      const expiryFiveDays = new Date(Date.now() + 5 * 86400000).toISOString();

      it('renders a warning alert with on-demand enabled message', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL',
            creditsRemaining: 400,
            creditsTotal: 500,
            trialExpiresAt: expiryFiveDays,
            onDemandEnabled: true,
          }),
        );
        await createPaidExperienceComponent();

        expect(findTrialAlert().props('variant')).toBe('warning');
        expect(findTrialAlert().props('title')).toBe('Secrets manager trial ends in 5 days');
        expect(findTrialAlert().text()).toContain(
          'On-demand billing is enabled. When all trial credits are consumed, GitLab credits will be used.',
        );
      });

      it('renders a warning alert with on-demand disabled message', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL',
            creditsRemaining: 400,
            creditsTotal: 500,
            trialExpiresAt: expiryFiveDays,
            onDemandEnabled: false,
          }),
        );
        await createPaidExperienceComponent();

        expect(findTrialAlert().props('variant')).toBe('warning');
        expect(findTrialAlert().props('title')).toBe('Secrets manager trial ends in 5 days');
        expect(findTrialAlert().text()).toContain(
          'Contact your billing administrator to enable on-demand billing and avoid disruption.',
        );
      });
    });

    describe.each`
      blockedReason                                       | expectedTitle
      ${BLOCKED_REASON_CREDITS_EXHAUSTED}                 | ${'0 credits left in secrets manager trial'}
      ${BLOCKED_REASON_GRACE}                             | ${'Your secrets manager subscription has been cancelled'}
      ${BLOCKED_REASON_ON_DEMAND_DISABLED}                | ${'On-demand billing is disabled'}
      ${BLOCKED_REASON_SUBSCRIPTION_GRACE_PERIOD_EXPIRED} | ${'Your secrets manager add-on has been removed from your license'}
      ${BLOCKED_REASON_TRIAL_EXPIRED}                     | ${'GitLab Secrets Manager is disabled'}
    `('when blocked with reason $blockedReason', ({ blockedReason, expectedTitle }) => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'BLOCKED', blockedReason }),
        );
        await createPaidExperienceComponent();
      });

      it('renders a danger alert with the correct title', () => {
        expect(findTrialAlert().props('variant')).toBe('danger');
        expect(findTrialAlert().props('title')).toBe(expectedTitle);
      });
    });

    describe('when the trial has expired', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'BLOCKED', blockedReason: BLOCKED_REASON_TRIAL_EXPIRED }),
        );
        await createPaidExperienceComponent();
      });

      it('tells the user they can still view and delete secrets', () => {
        expect(findTrialAlert().text()).toContain(
          'You can only view details or delete existing secrets.',
        );
      });
    });
  });

  // `isBetaUser` is derived from the entitlement's `betaWindowEligible`, which
  // the backend resolves per realm (namespace enrollment `beta` on SaaS,
  // instance enrollment + provisioned secrets manager on self-managed).
  describe('beta transition alert', () => {
    it('passes correct props for a beta namespace', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
      );

      await createPaidExperienceComponent();

      const alert = findBetaTransitionAlert();
      expect(alert.props('isBeta')).toBe(true);
      expect(alert.props('isTrialEligible')).toBe(true);
      expect(alert.props('betaProgramEnded')).toBe(false);
    });

    it('passes betaProgramEnded=true when the entitlement reports the beta cutoff', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({
          state: 'TRIAL_ELIGIBLE',
          betaWindowEligible: true,
          betaProgramEnded: true,
        }),
      );

      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('betaProgramEnded')).toBe(true);
    });

    it('passes isBeta=false when the entitlement is not beta-window eligible', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: false }),
      );

      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('isBeta')).toBe(false);
    });

    it('passes isBeta=false when the entitlement omits betaWindowEligible', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: null }),
      );

      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('isBeta')).toBe(false);
    });
  });

  describe('beta cohort', () => {
    beforeEach(() => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
      );
    });

    it('runs the secrets manager status query (beta users read their secrets)', async () => {
      await createPaidExperienceComponent();

      expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
    });

    it('provides the beta transition alert with isBeta=true', async () => {
      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('isBeta')).toBe(true);
    });

    // isBetaReadOnly is exposed via provide()/inject, not a prop on the
    // routed component, so assert the computed directly (same pattern as
    // the showTrialStartFlow assertion below).
    it('stays writable while the beta program has not ended', async () => {
      await createPaidExperienceComponent();

      expect(wrapper.vm.isBetaReadOnly).toBe(false);
      expect(wrapper.vm.isReadOnly).toBe(false);
    });

    describe('when the beta program has ended', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL_ELIGIBLE',
            betaWindowEligible: true,
            betaProgramEnded: true,
          }),
        );
        await createPaidExperienceComponent();
      });

      it('drops to read-only', () => {
        expect(wrapper.vm.isBetaReadOnly).toBe(true);
        expect(wrapper.vm.isReadOnly).toBe(true);
      });

      it('exits read-only when the alert emits `start-trial`', async () => {
        findBetaTransitionAlert().vm.$emit('start-trial');
        await nextTick();

        expect(wrapper.vm.isBetaReadOnly).toBe(false);
      });
    });

    // A beta group that converted to the trial and got blocked follows normal
    // entitlement even while the beta program runs -- the backend only sets
    // betaWindowEligible for never-converted groups (trial_eligible / ineligible).
    describe('when a converted beta group is blocked during the beta program', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'BLOCKED', blockedReason: 'TRIAL_EXPIRED' }),
        );
        await createPaidExperienceComponent();
      });

      it('drops to read-only like any blocked entitlement', () => {
        expect(wrapper.vm.isReadOnly).toBe(true);
      });
    });

    // TLG Owner opts into the trial-start flow via the alert CTA.
    // showTrialStartFlow is exposed via provide()/inject, not a prop on
    // the routed component, so assert the local flag rather than the
    // downstream template swap. No coverage exists yet for that
    // downstream swap itself.
    it('flips into the trial-start flow when the alert emits `start-trial`', async () => {
      await createPaidExperienceComponent();
      expect(wrapper.vm.showTrialStartFlow).toBe(false);

      findBetaTransitionAlert().vm.$emit('start-trial');
      await nextTick();

      expect(wrapper.vm.showTrialStartFlow).toBe(true);
    });
  });

  describe('enable add-on', () => {
    const enableSuccessAlert = {
      message:
        'The GitLab Secrets Manager has been enabled for all groups and projects in this namespace. %{linkStart}Manage group permissions.%{linkEnd}',
      messageLinks: { link: managePermissionsPath },
      variant: VARIANT_SUCCESS,
    };

    const setUpBetaEligible = async ({ onDemandEnabled = true } = {}) => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', onDemandEnabled, betaWindowEligible: true }),
      );
      await createPaidExperienceComponent();
    };

    const openModal = async () => {
      findBetaTransitionAlert().vm.$emit('enable-add-on');
      await nextTick();
    };

    const emitEnable = async () => {
      findEnableAddOnModal().vm.$emit('enable');
      await waitForPromises();
      await nextTick();
    };

    it('opens the modal when the alert emits `enable-add-on`', async () => {
      await setUpBetaEligible();
      expect(findEnableAddOnModal().props('visible')).toBe(false);

      await openModal();

      expect(findEnableAddOnModal().props('visible')).toBe(true);
    });

    it('passes onDemandEnabled from the entitlement to the modal', async () => {
      await setUpBetaEligible({ onDemandEnabled: false });

      expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(false);
    });

    // The trial and add-on flows share one status watcher; starting a trial
    // while the add-on enable is in flight would leave one flow stuck.
    it('does not start a trial while the add-on is being enabled', async () => {
      mockEnableAddOn.mockReturnValue(new Promise(() => {})); // add-on hangs -> isEnablingAddOn stays true
      await setUpBetaEligible();
      await openModal();
      await emitEnable();

      findRouterView().vm.$emit('start-trial');
      await waitForPromises();

      expect(mockEnrollNamespace).not.toHaveBeenCalled();
    });

    describe('on success', () => {
      beforeEach(async () => {
        await setUpBetaEligible();
        await openModal();
        await emitEnable();
      });

      it('calls the enable add-on mutation with the top-level group path', () => {
        expect(mockEnableAddOn).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
      });

      it('shows the success alert and refetches the entitlement', () => {
        expect(createAlert).toHaveBeenCalledWith(enableSuccessAlert);
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });

      it('clears the enabling state on the alert', () => {
        expect(findBetaTransitionAlert().props('isEnablingAddOn')).toBe(false);
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        mockEnableAddOn.mockResolvedValue(enableAddOnErrorResponse());
        await setUpBetaEligible();
        await openModal();
        await emitEnable();
      });

      it('surfaces the backend error and resets the enabling state', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'This group is not eligible to enable the Secrets Manager add-on.',
          }),
        );
        expect(findBetaTransitionAlert().props('isEnablingAddOn')).toBe(false);
      });
    });

    // Non-beta trial-eligible users reach the empty state, where the status
    // query is skipped until the add-on enable un-skips it so provisioning
    // can poll through to ACTIVE.
    describe('from the trial empty state', () => {
      const setUpTrialEligible = async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'TRIAL_ELIGIBLE', onDemandEnabled: true }),
        );
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, ENTITY_GROUP),
        );
        await createComponent({
          context: ENTITY_GROUP,
          router: createRouterForTest(ENTITY_GROUP),
          provide: {
            glFeatures: { secretsManagerPaidExperience: true },
            topLevelGroupFullPath: 'top-level-group',
          },
        });
      };

      it('opens the modal when the empty state emits `enable-add-on`', async () => {
        await setUpTrialEligible();
        expect(findEnableAddOnModal().props('visible')).toBe(false);

        findTrialEmptyState().vm.$emit('enable-add-on');
        await nextTick();

        expect(findEnableAddOnModal().props('visible')).toBe(true);
      });

      it('polls provisioning through to the success alert', async () => {
        await setUpTrialEligible();
        findTrialEmptyState().vm.$emit('enable-add-on');
        await nextTick();
        await emitEnable();

        // The empty state (which owns the Enable button spinner) must stay
        // mounted while provisioning polls, so the status watcher can fire.
        expect(findTrialEmptyState().exists()).toBe(true);

        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(mockEnableAddOn).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
        expect(createAlert).toHaveBeenCalledWith(enableSuccessAlert);
        // initial fetch + post-enable refetch once status reaches ACTIVE.
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('provision secrets manager', () => {
    const emitProvisionSecretsManager = async () => {
      findEmptyState().vm.$emit('provision-secrets-manager');
      await waitForPromises();
    };

    describe.each`
      context
      ${ENTITY_PROJECT}
      ${ENTITY_GROUP}
    `('in $context context', ({ context }) => {
      describe('on success', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
          mockEnableSecretsManager.mockResolvedValue(enableSecretManagerResponse({ context }));

          await createComponent({ context, router: createRouterForTest(context) });
          await emitProvisionSecretsManager();
        });

        it('calls the enable mutation with fullPath', () => {
          expect(mockEnableSecretsManager).toHaveBeenCalledWith({
            fullPath: defaultProvide.fullPath,
          });
        });

        it('refetches the secrets manager status', () => {
          // status was fetched on load; refetch after successful mutation.
          expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);
        });
      });

      describe('when the mutation returns errors', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
          mockEnableSecretsManager.mockResolvedValue(
            enableSecretManagerResponse({ context, errors: ['Not authorized'] }),
          );

          await createComponent({ context, router: createRouterForTest(context) });
          await emitProvisionSecretsManager();
        });

        it('creates a generic error alert', () => {
          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message: 'There was a problem enabling the GitLab Secrets Manager. Try again later.',
            }),
          );
        });

        it('clears the loading state on button', () => {
          // button loading is bound to isProvisioning; ensure it's reset after error.
          expect(findEmptyStateNewSecretBtn().props('loading')).toBe(false);
        });
      });
    });
  });

  describe('start trial', () => {
    const emitStartTrial = async () => {
      findTrialEmptyState().vm.$emit('start-trial');
      await waitForPromises();
    };

    const trialSuccessAlert = {
      message:
        'The GitLab Secrets Manager trial has been enabled for all groups and projects within this namespace. %{linkStart}Manage group permissions.%{linkEnd}',
      messageLinks: { link: managePermissionsPath },
      variant: VARIANT_SUCCESS,
    };

    // Trial chain runs against a TLG, so we're always in ENTITY_GROUP context.
    const setUpTrialEligible = async () => {
      await createComponent({
        context: ENTITY_GROUP,
        router: createRouterForTest(ENTITY_GROUP),
        provide: {
          glFeatures: { secretsManagerPaidExperience: true },
          topLevelGroupFullPath: 'top-level-group',
        },
      });
    };

    beforeEach(() => {
      mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL_ELIGIBLE' }));
      // TLG provisioning mutation succeeds; backend then flips status to
      // PROVISIONING while the async job runs, and finally to ACTIVE.
      mockEnableSecretsManager.mockResolvedValue(
        enableSecretManagerResponse({ context: ENTITY_GROUP }),
      );
      mockSecretManagerStatus.mockResolvedValue(
        secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, ENTITY_GROUP),
      );
    });

    describe('on successful onboarding', () => {
      beforeEach(async () => {
        await setUpTrialEligible();
        await emitStartTrial();
        // Simulate the backend provisioning job completing.
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('fires enrollment mutation with the top-level group path', () => {
        expect(mockEnrollNamespace).toHaveBeenCalledWith({ fullPath: 'top-level-group' });
      });

      it('fires trial mutation with the top-level group path', () => {
        expect(mockStartTrial).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
      });

      it('fires provisioning mutation with the current fullPath', () => {
        expect(mockEnableSecretsManager).toHaveBeenCalledWith({
          fullPath: defaultProvide.fullPath,
        });
      });

      it('refetches the entitlement after the chain succeeds', () => {
        // initial fetch + post-chain refetch (fires from the status watch)
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });

      it('shows a single success alert with the settings link', () => {
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('while provisioning is still polling', () => {
      const setUpPendingProvisioning = async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, ENTITY_GROUP),
        );
        await setUpTrialEligible();
        await emitStartTrial();
      };

      it('keeps the trial empty state visible', async () => {
        await setUpPendingProvisioning();
        expect(findTrialEmptyState().exists()).toBe(true);
      });

      it('does not show the success alert', async () => {
        await setUpPendingProvisioning();
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('does not refetch the entitlement while polling', async () => {
        await setUpPendingProvisioning();
        // Only the initial fetch; the post-chain refetch must wait until
        // the status flips to ACTIVE so on-refetch UI reflects the final
        // (TRIAL) state rather than the transient trial-eligible state.
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(1);
      });

      it('shows success alert after polling ends and secrets manager is provisioned', async () => {
        await setUpPendingProvisioning();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });

      it('refetches the entitlement only after status reaches ACTIVE', async () => {
        await setUpPendingProvisioning();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        // initial fetch + post-chain refetch (fires only after ACTIVE)
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });
    });

    describe('when enroll returns a benign already-enrolled error', () => {
      beforeEach(async () => {
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        await setUpTrialEligible();
        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('continues to trial', () => {
        expect(mockStartTrial).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
      });

      it('shows a success message with the settings link', () => {
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when start trial returns a benign error', () => {
      beforeEach(async () => {
        mockStartTrial.mockResolvedValue(
          startTrialErrorResponse(['A Secrets Manager trial is already active for this group.']),
        );
        await setUpTrialEligible();
        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('continues to provisioning', () => {
        expect(mockEnableSecretsManager).toHaveBeenCalled();
      });

      it('shows a success message with the settings link', () => {
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when provisioning returns a benign already-initialized error', () => {
      beforeEach(async () => {
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({
            context: ENTITY_GROUP,
            errors: ['Secrets manager already initialized for the group.'],
          }),
        );
        await setUpTrialEligible();
        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('shows the success alert', () => {
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when enrollment fails with a non-benign error', () => {
      beforeEach(async () => {
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceErrorResponse(['Not authorized']));
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('does not call start trial', () => {
        expect(mockStartTrial).not.toHaveBeenCalled();
      });

      it('does not call provisioning', () => {
        expect(mockEnableSecretsManager).not.toHaveBeenCalled();
      });

      it('shows an error alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'Not authorized' }),
        );
      });

      it('keeps the trial empty state visible for retry', () => {
        expect(findTrialEmptyState().exists()).toBe(true);
      });
    });

    describe('when start trial fails after enrollment succeeds', () => {
      beforeEach(async () => {
        mockStartTrial.mockResolvedValue(startTrialErrorResponse(['This group is not eligible']));
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('does not call provisioning', () => {
        expect(mockEnableSecretsManager).not.toHaveBeenCalled();
      });

      it('shows an error alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'This group is not eligible' }),
        );
      });

      it('re-runs the chain on retry', async () => {
        // partial-progress retry: enroll is idempotent and returns benign
        // error; trial now succeeds; provisioning completes; success alert
        // fires from the status watch.
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        mockStartTrial.mockResolvedValue(startTrialSuccessResponse());

        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(mockEnrollNamespace).toHaveBeenCalledTimes(2);
        expect(mockStartTrial).toHaveBeenCalledTimes(2);
        expect(mockEnableSecretsManager).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when a mutation in the chain throws (transport-level error)', () => {
      // Distinct from "mutation returns errors" (GraphQL payload errors,
      // covered above): this covers the promise-rejection path (network
      // failure, transport-level exception).
      beforeEach(async () => {
        mockEnrollNamespace.mockRejectedValue(new Error('Network error'));
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('surfaces the thrown error message', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'Network error',
            captureError: true,
          }),
        );
      });

      it('does not show the success alert', () => {
        expect(createAlert).not.toHaveBeenCalledWith(trialSuccessAlert);
      });

      it('keeps the trial empty state visible for retry', () => {
        expect(findTrialEmptyState().exists()).toBe(true);
      });
    });

    describe('when a mutation throws without a message', () => {
      // Covers the generic-copy fallback path: some transport errors surface
      // as an Error without a useful `.message`. The catch should fall back
      // to the generic "An error occurred..." copy so the user isn't shown
      // an empty alert.
      beforeEach(async () => {
        mockEnrollNamespace.mockRejectedValue(new Error());
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('shows the generic trial error alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'An error occurred while starting the trial.',
            captureError: true,
          }),
        );
      });
    });

    describe('when provisioning fails after trial succeeds', () => {
      beforeEach(async () => {
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({
            context: ENTITY_GROUP,
            errors: ['Provisioning backend unavailable'],
          }),
        );
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('shows the provisioning error', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'Provisioning backend unavailable' }),
        );
      });

      it('does not show the success alert', () => {
        expect(createAlert).not.toHaveBeenCalledWith(trialSuccessAlert);
      });

      it('keeps the trial empty state visible for retry', () => {
        expect(findTrialEmptyState().exists()).toBe(true);
      });

      it('re-runs the full chain on retry', async () => {
        // benign errors on enroll and trial (already done); provisioning
        // now succeeds and status flips to ACTIVE; single success alert.
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        mockStartTrial.mockResolvedValue(
          startTrialErrorResponse(['A Secrets Manager trial is already active for this group.']),
        );
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({ context: ENTITY_GROUP }),
        );

        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(mockEnableSecretsManager).toHaveBeenCalledTimes(2);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });
  });

  describe('provisioning success alert', () => {
    // simulate the empty state's click, then simulate the backend returning
    // PROVISIONING on the post-mutation refetch (so polling kicks in).
    const startProvisioningFlow = async (context) => {
      mockSecretManagerStatus.mockResolvedValue(
        secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, context),
      );
      findEmptyState().vm.$emit('provision-secrets-manager');
      await waitForPromises();
    };

    describe.each`
      context           | expectedMessage
      ${ENTITY_PROJECT} | ${'GitLab Secrets Manager has been enabled for this project.'}
      ${ENTITY_GROUP}   | ${'GitLab Secrets Manager has been enabled for this group.'}
    `('in $context context', ({ context, expectedMessage }) => {
      beforeEach(async () => {
        // start with an unprovisioned state so the user can click "New secret"
        // to kick off provisioning.
        mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
        mockEnableSecretsManager.mockResolvedValue(enableSecretManagerResponse({ context }));
        await createComponent({ context, router: createRouterForTest(context) });
      });

      it('fires a success alert with a manage permissions link', async () => {
        await startProvisioningFlow(context);
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(createAlert).toHaveBeenCalledWith({
          message: `${expectedMessage} %{linkStart}Manage permissions.%{linkEnd}`,
          messageLinks: { link: managePermissionsPath },
          variant: VARIANT_SUCCESS,
        });
      });
    });
  });
});
