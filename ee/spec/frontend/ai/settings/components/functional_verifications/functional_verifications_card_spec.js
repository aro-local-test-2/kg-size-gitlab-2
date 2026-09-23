import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import FunctionalVerificationsCard from 'ee/ai/settings/components/functional_verifications/functional_verifications_card.vue';
import AgenticChatVerificationCheck from 'ee/ai/settings/components/functional_verifications/agentic_chat_verification_check.vue';
import NamespaceSelector from 'ee/ai/settings/components/functional_verifications/namespace_selector.vue';
import HealthCheckCard from 'ee/vue_shared/components/health_check_card.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import getVerificationFeatureSettingsQuery from 'ee/ai/settings/graphql/queries/get_verification_feature_settings.query.graphql';
import getNamespacesQuery from 'ee/ai/settings/components/functional_verifications/graphql/queries/get_groups.query.graphql';
import getFunctionalVerificationStatusQuery from 'ee/ai/settings/graphql/queries/get_functional_verification_status.query.graphql';
import {
  FUNCTIONAL_VERIFICATION_STATUS,
  MODEL_PROVIDERS,
  AGENTIC_CHAT_FEATURE,
} from 'ee/ai/settings/components/functional_verifications/constants';

Vue.use(VueApollo);

describe('FunctionalVerificationsCard', () => {
  let wrapper;

  const featureSettingNode = (provider, extra = {}) => ({
    feature: AGENTIC_CHAT_FEATURE,
    provider,
    selfHostedModel: null,
    ...extra,
  });

  const selfHostedFeatureSetting = (extra = {}) =>
    featureSettingNode(MODEL_PROVIDERS.SELF_HOSTED, {
      selfHostedModel: { id: 'gid://gitlab/Ai::SelfHostedModel/1', name: 'Mixtral 8x7B' },
      ...extra,
    });

  const queryHandler = (nodes = [selfHostedFeatureSetting()]) =>
    jest.fn().mockResolvedValue({ data: { aiFeatureSettings: { nodes } } });

  const failedQueryHandler = () => jest.fn().mockRejectedValue(new Error('error'));

  const runStatusHandler = (run = null) =>
    jest.fn().mockResolvedValue({ data: { functionalVerificationStatus: run } });

  const mockNamespace = { id: 'gid://gitlab/Group/1', name: 'Group A', fullPath: 'group-a' };

  const findHealthCheckCard = () => wrapper.findComponent(HealthCheckCard);
  const findAgenticChatCheck = () => wrapper.findComponent(AgenticChatVerificationCheck);
  const findNamespaceSelector = () => wrapper.findComponent(NamespaceSelector);
  const findSelfHostedOnlyNotice = () => wrapper.findByTestId('self-hosted-only-notice');
  const findExpandText = () => wrapper.findByTestId('health-check-card-expand-text');
  const findTimeAgoTooltip = () => wrapper.findComponent(TimeAgoTooltip);

  const createComponent = async ({
    handler = queryHandler(),
    statusHandler = runStatusHandler(),
    expanded,
    selectedNamespace = mockNamespace,
  } = {}) => {
    wrapper = mountExtended(FunctionalVerificationsCard, {
      apolloProvider: createMockApollo([
        [getVerificationFeatureSettingsQuery, handler],
        [getFunctionalVerificationStatusQuery, statusHandler],
        [
          getNamespacesQuery,
          jest.fn().mockResolvedValue({
            data: {
              adminDuoAvailabilityNamespaces: {
                nodes: [],
                pageInfo: {
                  hasNextPage: false,
                  hasPreviousPage: false,
                  startCursor: null,
                  endCursor: null,
                },
              },
            },
          }),
        ],
      ]),
      data() {
        return {
          selectedNamespace,
          ...(expanded !== undefined && { expanded }),
        };
      },
      provide: { duoInstanceModelSelectionPath: '/admin/gitlab_duo/model_selection' },
    });

    await waitForPromises();
  };

  it('renders the static title', async () => {
    await createComponent();

    expect(findHealthCheckCard().props('title')).toBe('Functional verification checks');
  });

  it('shows "Hide results" when expanded', async () => {
    await createComponent({ expanded: true });

    expect(findExpandText().text()).toBe('Hide results');
  });

  it('does not show "Hide results" when not expanded', async () => {
    await createComponent({ expanded: false });

    expect(findExpandText().text()).not.toBe('Hide results');
  });

  it('toggles expanded when the card emits toggle', async () => {
    await createComponent({ expanded: false });

    findHealthCheckCard().vm.$emit('toggle');
    await waitForPromises();

    expect(findHealthCheckCard().props('expanded')).toBe(true);
  });

  it('renders the credits hint in the header', async () => {
    await createComponent();

    expect(wrapper.findByTestId('functional-verifications-credits-hint').exists()).toBe(true);
  });

  describe('verification run status', () => {
    it('shows "Not run" and no notice when not yet run', async () => {
      await createComponent();

      expect(findExpandText().text()).toBe('Not run');
      expect(findSelfHostedOnlyNotice().exists()).toBe(false);
      expect(findAgenticChatCheck().props('disabled')).toBe(false);
    });

    it('shows "Running" while a run is in progress', async () => {
      await createComponent({
        statusHandler: runStatusHandler({
          state: FUNCTIONAL_VERIFICATION_STATUS.RUNNING,
          updatedAt: null,
        }),
      });

      expect(findExpandText().text()).toBe('Running');
    });

    it('shows the passed count and last run time', async () => {
      await createComponent({
        statusHandler: runStatusHandler({
          state: FUNCTIONAL_VERIFICATION_STATUS.PASSED,
          updatedAt: '2026-09-04T12:00:00Z',
        }),
      });

      expect(findExpandText().text()).toContain('1 check passed');
      expect(findExpandText().text()).toContain('Last run');
      expect(findTimeAgoTooltip().props('time')).toEqual(new Date('2026-09-04T12:00:00Z'));
    });

    it('shows the failed count and last run time', async () => {
      await createComponent({
        statusHandler: runStatusHandler({
          state: FUNCTIONAL_VERIFICATION_STATUS.FAILED,
          updatedAt: '2026-09-04T12:00:00Z',
        }),
      });

      expect(findExpandText().text()).toContain('1 check failed');
      expect(findExpandText().text()).toContain('Last run');
      expect(findTimeAgoTooltip().props('time')).toEqual(new Date('2026-09-04T12:00:00Z'));
    });

    it('shows no last run time when there is no checked at date', async () => {
      await createComponent();

      expect(findTimeAgoTooltip().exists()).toBe(false);
    });
  });

  describe('model selection', () => {
    describe('when a self-hosted model is selected', () => {
      it('shows no notice and enables the check', async () => {
        await createComponent();

        expect(findSelfHostedOnlyNotice().exists()).toBe(false);
        expect(findAgenticChatCheck().props('disabled')).toBe(false);
      });

      it('passes the model name and provider down to the check', async () => {
        await createComponent();

        expect(findAgenticChatCheck().props('model')).toEqual({
          provider: MODEL_PROVIDERS.SELF_HOSTED,
          name: 'Mixtral 8x7B',
        });
      });
    });

    describe.each`
      scenario                         | handler                                                                     | expectedModel
      ${'the model is disabled'}       | ${() => queryHandler([featureSettingNode(MODEL_PROVIDERS.DISABLED)])}       | ${{ provider: MODEL_PROVIDERS.DISABLED, name: '' }}
      ${'the model is GitLab-managed'} | ${() => queryHandler([featureSettingNode(MODEL_PROVIDERS.GITLAB_MANAGED)])} | ${{ provider: MODEL_PROVIDERS.GITLAB_MANAGED, name: '' }}
      ${'the query fails'}             | ${failedQueryHandler}                                                       | ${null}
    `('when $scenario', ({ handler, expectedModel }) => {
      it('shows the self-hosted-only notice and disables the check', async () => {
        await createComponent({ handler: handler() });

        expect(findExpandText().text()).toBe('Verification check supports only self-hosted models');
        expect(findSelfHostedOnlyNotice().exists()).toBe(true);
        expect(findAgenticChatCheck().props('disabled')).toBe(true);
      });

      it('passes the expected model info down to the check', async () => {
        await createComponent({ handler: handler() });

        expect(findAgenticChatCheck().props('model')).toEqual(expectedModel);
      });
    });
  });

  describe('namespace selection', () => {
    it('renders the namespace selector', async () => {
      await createComponent();

      expect(findNamespaceSelector().exists()).toBe(true);
    });

    describe('when no namespace is selected', () => {
      let statusHandler;

      beforeEach(async () => {
        statusHandler = runStatusHandler();
        await createComponent({ selectedNamespace: null, statusHandler });
      });

      it('skips the verification status query', () => {
        expect(statusHandler).not.toHaveBeenCalled();
      });

      it('disables the agentic chat functional verification check', () => {
        expect(findAgenticChatCheck().props('disabled')).toBe(true);
      });

      it('disables expanding the card', () => {
        expect(findHealthCheckCard().props('expandDisabled')).toBe(true);
      });

      it('shows a prompt to select a group', () => {
        expect(findExpandText().text()).toBe('To get started, select a group');
      });
    });

    describe('when a namespace is selected', () => {
      beforeEach(async () => {
        await createComponent({ selectedNamespace: null, expanded: false });

        findNamespaceSelector().vm.$emit('select', mockNamespace);
        await waitForPromises();
      });

      it('automatically expands the card once a namespace is selected', () => {
        expect(findHealthCheckCard().props('expanded')).toBe(true);
      });

      it('enables the agentic chat functional verification check', () => {
        expect(findAgenticChatCheck().props('disabled')).toBe(false);
      });

      it('does not disable expanding the card', () => {
        expect(findHealthCheckCard().props('expandDisabled')).toBe(false);
      });
    });
  });
});
