import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import AgenticChatVerificationCheck from 'ee/ai/settings/components/functional_verifications/agentic_chat_verification_check.vue';
import FunctionalVerificationCheck from 'ee/ai/settings/components/functional_verifications/functional_verification_check.vue';
import getFunctionalVerificationStatusQuery from 'ee/ai/settings/graphql/queries/get_functional_verification_status.query.graphql';
import {
  FUNCTIONAL_VERIFICATION_STATUS,
  MODEL_PROVIDERS,
} from 'ee/ai/settings/components/functional_verifications/constants';

Vue.use(VueApollo);

describe('AgenticChatVerificationCheck', () => {
  let wrapper;

  const findFunctionalVerificationCheck = () => wrapper.findComponent(FunctionalVerificationCheck);

  const runStatusHandler = (run = null) =>
    jest.fn().mockResolvedValue({ data: { functionalVerificationStatus: run } });

  const failedStatusHandler = () => jest.fn().mockRejectedValue(new Error('error'));

  const createComponent = async ({ props = {}, statusHandler = runStatusHandler() } = {}) => {
    wrapper = mountExtended(AgenticChatVerificationCheck, {
      apolloProvider: createMockApollo([[getFunctionalVerificationStatusQuery, statusHandler]]),
      propsData: { ...props },
    });

    await waitForPromises();
  };

  it('renders the static name and description', async () => {
    await createComponent();

    expect(findFunctionalVerificationCheck().props()).toMatchObject({
      name: 'Agentic Chat',
      description: 'Verifies the request flow of Agentic Chat end to end.',
    });
  });

  describe('when there is no verification run', () => {
    it('defaults to a not-run status', async () => {
      await createComponent({ statusHandler: runStatusHandler(null) });

      expect(findFunctionalVerificationCheck().props()).toMatchObject({
        status: FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN,
        lastRunAt: null,
        errorText: '',
      });
    });
  });

  describe('when there is a verification run', () => {
    it('passes through the status from the query', async () => {
      await createComponent({
        statusHandler: runStatusHandler({
          state: FUNCTIONAL_VERIFICATION_STATUS.PASSED,
          updatedAt: '2026-09-04T12:00:00Z',
        }),
      });

      expect(findFunctionalVerificationCheck().props()).toMatchObject({
        status: FUNCTIONAL_VERIFICATION_STATUS.PASSED,
        lastRunAt: '2026-09-04T12:00:00Z',
      });
    });
  });

  it('passes the model prop through', async () => {
    const model = { provider: MODEL_PROVIDERS.SELF_HOSTED, name: 'Mixtral 8x7B' };

    await createComponent({ props: { model } });

    expect(findFunctionalVerificationCheck().props('model')).toEqual(model);
  });

  it('passes null for the model when there is no model info', async () => {
    await createComponent();

    expect(findFunctionalVerificationCheck().props('model')).toBeNull();
  });

  it('passes the disabled prop through and skips the query', async () => {
    const statusHandler = runStatusHandler();

    await createComponent({ props: { disabled: true }, statusHandler });

    expect(findFunctionalVerificationCheck().props('disabled')).toBe(true);
    expect(statusHandler).not.toHaveBeenCalled();
  });

  it('emits updated with the run whenever it loads or changes', async () => {
    await createComponent({
      statusHandler: runStatusHandler({
        state: FUNCTIONAL_VERIFICATION_STATUS.FAILED,
        updatedAt: '2026-09-04T12:00:00Z',
      }),
    });

    const emitted = wrapper.emitted('updated');

    expect(emitted[emitted.length - 1][0]).toMatchObject({
      state: FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      checkedAt: '2026-09-04T12:00:00Z',
    });
  });

  it('shows an error when the query fails', async () => {
    await createComponent({ statusHandler: failedStatusHandler() });

    expect(findFunctionalVerificationCheck().props('errorText')).toBe(
      'Failed to load last run details.',
    );
  });

  it('does not emit run when the check emits run', async () => {
    await createComponent();

    findFunctionalVerificationCheck().vm.$emit('run');

    // No-op until the mutation/WebSocket-driven run is wired up.
    expect(wrapper.emitted('run')).toBeUndefined();
  });
});
