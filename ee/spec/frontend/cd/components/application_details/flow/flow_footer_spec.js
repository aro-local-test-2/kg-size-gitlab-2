import { GlIcon, GlModal } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { createMockSubscription } from 'mock-apollo-client';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import FlowFooter from 'ee/cd/components/application_details/flow/flow_footer.vue';
import cdRolloutApprovalGatesQuery from 'ee/cd/graphql/applications/flow/cd_rollout_approval_gates.query.graphql';
import cdRolloutGateUpdatedSubscription from 'ee/cd/graphql/applications/flow/cd_rollout_gate_updated.subscription.graphql';
import cdRolloutGateResolveMutation from 'ee/cd/graphql/applications/flow/cd_rollout_gate_resolve.mutation.graphql';
import {
  buildRolloutApprovalGateResponse,
  buildRolloutGateResolveResponse,
  makeCdRolloutGate,
} from 'ee/cd/../../../../spec/frontend/cd/components/mock_data';

Vue.use(VueApollo);

const ROLLOUT_ID = 'gid://gitlab/Cd::Rollout/5';

const pendingGate = (overrides = {}) => makeCdRolloutGate({ state: 'PENDING', ...overrides });
const approvedGate = (overrides = {}) => makeCdRolloutGate({ state: 'APPROVED', ...overrides });
const rejectedGate = (overrides = {}) => makeCdRolloutGate({ state: 'REJECTED', ...overrides });

describe('FlowFooter', () => {
  let wrapper;
  let gateHandler;
  let resolveHandler;
  let hideModal;

  const failedStep = (overrides = {}) => ({
    nodeId: 'item-1-step-0',
    title: 'deploy to production',
    error: 'image pull backoff',
    ...overrides,
  });

  let gateSubscription;

  const createComponent = async ({
    gates = [],
    failedSteps = [],
    canResolve = true,
    queryHandler = jest.fn().mockResolvedValue(buildRolloutApprovalGateResponse({ gates })),
    mutationHandler = jest.fn().mockResolvedValue(buildRolloutGateResolveResponse()),
  } = {}) => {
    gateHandler = queryHandler;
    resolveHandler = mutationHandler;
    hideModal = jest.fn();
    gateSubscription = createMockSubscription();

    wrapper = shallowMountExtended(FlowFooter, {
      apolloProvider: createMockApollo([
        [cdRolloutApprovalGatesQuery, gateHandler],
        [cdRolloutGateResolveMutation, resolveHandler],
        [cdRolloutGateUpdatedSubscription, () => gateSubscription],
      ]),
      propsData: { rolloutId: ROLLOUT_ID, canResolve, failedSteps },
      stubs: { GlModal: stubComponent(GlModal, { methods: { hide: hideModal } }) },
    });

    await waitForPromises();
  };

  const findFooter = () => wrapper.findByTestId('flow-footer');
  const findTitles = () => wrapper.findAllByTestId('status-title');
  const findTitle = () => wrapper.findByTestId('status-title');
  const findEnvironment = () => wrapper.findByTestId('status-environment');
  const findApproveButton = () => wrapper.findComponentByTestId('approve-button');
  const findRejectButton = () => wrapper.findComponentByTestId('reject-button');
  const findAwaitingText = () => wrapper.findByTestId('status-pending');
  const findResolution = () => wrapper.findByTestId('status-resolution');
  const findReason = () => wrapper.findByTestId('status-reason');
  const findReasons = () => wrapper.findAllByTestId('status-reason');
  const findResolutionReason = () => wrapper.findByTestId('status-resolution-reason');
  const findAllReasons = () =>
    wrapper.findAll('[data-testid="status-reason"], [data-testid="status-resolution-reason"]');
  const reasonText = () => (findReason().exists() ? findReason().text() : null);
  const findGateLoadError = () => wrapper.findComponentByTestId('gate-load-error');
  const findApproveError = () => wrapper.findComponentByTestId('approve-error');
  const findRejectError = () => wrapper.findComponentByTestId('reject-error');
  const findReasonInput = () => wrapper.findComponentByTestId('reject-reason');
  const findModal = () => wrapper.findComponent(GlModal);
  const findStatusIcon = () => wrapper.findComponent(GlIcon);

  const approve = async () => {
    findApproveButton().vm.$emit('click');
    await waitForPromises();
  };

  const confirmRejection = async () => {
    findModal().vm.$emit('primary', { preventDefault: () => {} });
    await waitForPromises();
  };

  describe('when the rollout has no approval gate', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('does not render flow footer', () => {
      expect(findFooter().exists()).toBe(false);
    });
  });

  describe('when the gate fails to load', () => {
    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException').mockImplementation();

      await createComponent({
        gates: [pendingGate()],
        queryHandler: jest.fn().mockRejectedValue(new Error('boom')),
      });
    });

    it('renders the error', () => {
      expect(findGateLoadError().text()).toBe(
        'Failed to load the approval gate. Refresh to try again.',
      );
    });

    it('does not render the gate', () => {
      expect(findTitle().exists()).toBe(false);
      expect(findResolution().exists()).toBe(false);
    });

    it('does not render the approve and reject buttons', () => {
      expect(findApproveButton().exists()).toBe(false);
      expect(findRejectButton().exists()).toBe(false);
    });

    it('reports the exception to Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(new Error('boom'));
    });
  });

  describe('when the gate is open', () => {
    describe('when the user can resolve it', () => {
      beforeEach(async () => {
        await createComponent({ gates: [pendingGate()] });
      });

      it('renders the gated step as the title', () => {
        expect(findTitle().text()).toBe('Prod sign-off');
      });

      it('renders the approve and reject buttons', () => {
        expect(findApproveButton().exists()).toBe(true);
        expect(findRejectButton().exists()).toBe(true);
      });

      it('does not render a resolution', () => {
        expect(findResolution().exists()).toBe(false);
      });
    });

    describe('when the user cannot resolve it', () => {
      beforeEach(async () => {
        await createComponent({ gates: [pendingGate()], canResolve: false });
      });

      it('does not render the approve and reject buttons', () => {
        expect(findApproveButton().exists()).toBe(false);
        expect(findRejectButton().exists()).toBe(false);
      });

      it('shows the rollout as awaiting approval', () => {
        expect(findAwaitingText().text()).toBe('Awaiting approval');
      });
    });

    describe('when an earlier gate was already resolved', () => {
      beforeEach(async () => {
        await createComponent({
          gates: [
            approvedGate({ id: 1 }),
            pendingGate({ id: 2, name: 'Promote to 50%?', environment: 'prod-eu-west-1' }),
          ],
        });
      });

      it('renders both gates, oldest first', () => {
        expect(findTitles().wrappers.map((title) => title.text())).toEqual([
          'Approved Prod sign-off',
          'Promote to 50%?',
        ]);
      });

      it('renders the environment of the step', () => {
        expect(findEnvironment().text()).toBe('Environment: prod-eu-west-1');
      });
    });

    describe('when approving', () => {
      beforeEach(async () => {
        await createComponent({ gates: [pendingGate()] });
        await approve();
      });

      it('records the approval', () => {
        expect(resolveHandler).toHaveBeenCalledWith({
          input: { id: ROLLOUT_ID, status: 'APPROVED', resolutionReason: null },
        });
      });

      it('refetches the gate', () => {
        expect(gateHandler).toHaveBeenCalledTimes(2);
      });
    });

    describe('when rejecting', () => {
      describe('when a reason is given', () => {
        beforeEach(async () => {
          await createComponent({ gates: [pendingGate()] });
          findReasonInput().vm.$emit('input', '  Failing canary  ');
          await confirmRejection();
        });

        it('records the rejection with the trimmed reason', () => {
          expect(resolveHandler).toHaveBeenCalledWith({
            input: { id: ROLLOUT_ID, status: 'REJECTED', resolutionReason: 'Failing canary' },
          });
        });
      });

      describe('when no reason is given', () => {
        beforeEach(async () => {
          await createComponent({ gates: [pendingGate()] });
          await confirmRejection();
        });

        it('records the rejection without a reason', () => {
          expect(resolveHandler).toHaveBeenCalledWith({
            input: { id: ROLLOUT_ID, status: 'REJECTED', resolutionReason: null },
          });
        });
      });

      describe('when the rejection is recorded', () => {
        beforeEach(async () => {
          await createComponent({ gates: [pendingGate()] });
          await confirmRejection();
        });

        it('closes the modal', () => {
          expect(hideModal).toHaveBeenCalled();
        });
      });

      describe('when the rejection cannot be recorded', () => {
        beforeEach(async () => {
          await createComponent({
            gates: [pendingGate()],
            mutationHandler: jest
              .fn()
              .mockResolvedValue(
                buildRolloutGateResolveResponse(['Rollout has no open approval gate.']),
              ),
          });
          findReasonInput().vm.$emit('input', 'Failing canary');
          await confirmRejection();
        });

        it('renders the error inside the modal', () => {
          expect(findRejectError().text()).toBe('Rollout has no open approval gate.');
        });

        it('keeps the modal open so the reason can be retried', () => {
          expect(hideModal).not.toHaveBeenCalled();
        });
      });

      describe('while the decision is in flight', () => {
        beforeEach(async () => {
          await createComponent({
            gates: [pendingGate()],
            mutationHandler: jest.fn(() => new Promise(() => {})),
          });
          findModal().vm.$emit('primary', { preventDefault: () => {} });
          await nextTick();
        });

        it('blocks every way of closing the modal', () => {
          expect(findModal().attributes()).toMatchObject({
            'no-close-on-esc': 'true',
            'no-close-on-backdrop': 'true',
            'hide-header-close': 'true',
          });
        });

        it('disables the cancel button', () => {
          expect(findModal().props('actionCancel').attributes.disabled).toBe(true);
        });
      });

      describe('when the modal is dismissed', () => {
        beforeEach(async () => {
          await createComponent({
            gates: [pendingGate()],
            mutationHandler: jest
              .fn()
              .mockResolvedValue(
                buildRolloutGateResolveResponse(['Rollout has no open approval gate.']),
              ),
          });
          findReasonInput().vm.$emit('input', 'Failing canary');
          await confirmRejection();
          findModal().vm.$emit('hidden');
          await nextTick();
        });

        it('clears the reason', () => {
          expect(findReasonInput().attributes('value')).toBe('');
        });

        it('clears the error so it does not reappear on reopen', () => {
          expect(findRejectError().exists()).toBe(false);
        });
      });
    });

    describe('when the decision cannot be recorded', () => {
      beforeEach(async () => {
        await createComponent({
          gates: [pendingGate()],
          mutationHandler: jest
            .fn()
            .mockResolvedValue(
              buildRolloutGateResolveResponse(['Rollout has no open approval gate.']),
            ),
        });
        await approve();
      });

      it('renders the returned error', () => {
        expect(findApproveError().text()).toBe('Rollout has no open approval gate.');
      });

      it('does not refetch the gate', () => {
        expect(gateHandler).toHaveBeenCalledTimes(1);
      });
    });

    describe('when the mutation fails', () => {
      beforeEach(async () => {
        await createComponent({
          gates: [pendingGate()],
          mutationHandler: jest.fn().mockRejectedValue(new Error('boom')),
        });
        await approve();
      });

      it('renders a generic error', () => {
        expect(findApproveError().text()).toBe('Failed to record the decision. Please try again.');
      });
    });

    describe('when the decision is recorded but the refresh fails', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException').mockImplementation();

        await createComponent({ gates: [pendingGate()] });
        gateHandler.mockRejectedValueOnce(new Error('boom'));
        await approve();
      });

      it('does not report the decision as failed', () => {
        expect(findApproveError().exists()).toBe(false);
      });

      it('renders the load error', () => {
        expect(findGateLoadError().text()).toBe(
          'Failed to load the approval gate. Refresh to try again.',
        );
      });

      it('does not render the approve and reject buttons', () => {
        expect(findApproveButton().exists()).toBe(false);
        expect(findRejectButton().exists()).toBe(false);
      });
    });

    describe('while the decision is being refreshed', () => {
      beforeEach(async () => {
        await createComponent({ gates: [pendingGate()] });
        gateHandler.mockImplementationOnce(() => new Promise(() => {}));
        findApproveButton().vm.$emit('click');
        await waitForPromises();
      });

      it('disables the approve and reject buttons', () => {
        expect(findApproveButton().props('loading')).toBe(true);
        expect(findRejectButton().props('disabled')).toBe(true);
      });
    });
  });

  describe.each`
    decision      | buildGate       | title
    ${'approved'} | ${approvedGate} | ${'Approved Prod sign-off'}
    ${'rejected'} | ${rejectedGate} | ${'Rejected Prod sign-off'}
  `('when the gate was $decision', ({ buildGate, title }) => {
    beforeEach(async () => {
      await createComponent({ gates: [buildGate()] });
    });

    it('renders the decision and the gate name as the title', () => {
      expect(findTitle().text()).toBe(title);
    });

    it('shows who resolved it', () => {
      expect(findResolution().text()).toContain('@alice');
    });

    it('does not render the approve and reject buttons', () => {
      expect(findApproveButton().exists()).toBe(false);
      expect(findRejectButton().exists()).toBe(false);
    });
  });

  describe.each`
    state                    | buildGate                                        | icon
    ${'open'}                | ${pendingGate}                                   | ${'status-running'}
    ${'approved'}            | ${approvedGate}                                  | ${'status-success'}
    ${'rejected'}            | ${rejectedGate}                                  | ${'status-failed'}
    ${'in an unknown state'} | ${() => makeCdRolloutGate({ state: 'EXPIRED' })} | ${'status-neutral'}
  `('when the gate is $state', ({ buildGate, icon }) => {
    beforeEach(async () => {
      await createComponent({ gates: [buildGate()] });
    });

    it('renders the matching status icon', () => {
      expect(findStatusIcon().props('name')).toBe(icon);
    });
  });

  describe.each`
    state         | buildGate       | title
    ${'pending'}  | ${pendingGate}  | ${'Awaiting approval'}
    ${'approved'} | ${approvedGate} | ${'Approved'}
  `('when a nameless gate is $state', ({ buildGate, title }) => {
    beforeEach(async () => {
      await createComponent({ gates: [buildGate({ name: null })], canResolve: false });
    });

    it('renders the decision alone as the title', () => {
      expect(findTitle().text()).toBe(title);
    });

    it('does not repeat the title as awaiting text', () => {
      expect(findAwaitingText().exists()).toBe(false);
    });
  });

  describe('when a gate opens over the subscription', () => {
    beforeEach(async () => {
      await createComponent({ gates: [] });

      gateSubscription.next({
        data: {
          cdRolloutGateUpdated: {
            __typename: 'CdRollout',
            id: ROLLOUT_ID,
            gates: [pendingGate()],
          },
        },
      });
      await waitForPromises();
    });

    it('renders the footer', () => {
      expect(findFooter().exists()).toBe(true);
    });

    it('renders the approve button', () => {
      expect(findApproveButton().exists()).toBe(true);
    });
  });

  describe('when a gate update arrives over the subscription', () => {
    beforeEach(async () => {
      await createComponent({ gates: [pendingGate()] });

      gateSubscription.next({
        data: {
          cdRolloutGateUpdated: {
            __typename: 'CdRollout',
            id: ROLLOUT_ID,
            gates: [approvedGate()],
          },
        },
      });
      await waitForPromises();
    });

    it('renders the resolution', () => {
      expect(findResolution().text()).toContain('@alice');
    });

    it('renders no approve button', () => {
      expect(findApproveButton().exists()).toBe(false);
    });

    it('does not refetch the gates', () => {
      expect(gateHandler).toHaveBeenCalledTimes(1);
    });
  });

  describe('reasons', () => {
    const opened = 'Promoting to 100% needs sign-off';
    const resolved = 'Canary error rate too high';

    const reasonTexts = () =>
      [findReason(), findResolutionReason()].map((paragraph) =>
        paragraph.exists() ? paragraph.text() : null,
      );

    it.each`
      scenario                   | gate                                                                  | texts
      ${'neither reason'}        | ${() => pendingGate()}                                                | ${[null, null]}
      ${'the gate reason'}       | ${() => pendingGate({ reason: opened })}                              | ${[opened, null]}
      ${'the resolution reason'} | ${() => rejectedGate({ resolutionReason: resolved })}                 | ${[null, resolved]}
      ${'both reasons'}          | ${() => rejectedGate({ reason: opened, resolutionReason: resolved })} | ${[opened, resolved]}
    `('renders $scenario', async ({ gate, texts }) => {
      await createComponent({ gates: [gate()] });

      expect(reasonTexts()).toEqual(texts);
    });

    it('renders the reason above the resolution reason', async () => {
      await createComponent({
        gates: [rejectedGate({ reason: opened, resolutionReason: resolved })],
      });

      expect(findAllReasons().wrappers.map((paragraph) => paragraph.text())).toEqual([
        opened,
        resolved,
      ]);
    });
  });

  describe('when the gate was resolved by a non-user principal', () => {
    beforeEach(async () => {
      await createComponent({ gates: [approvedGate({ username: null })] });
    });

    it('does not render a username', () => {
      expect(findResolution().text()).not.toContain('@');
    });
  });

  describe.each`
    scenario       | step                           | title                            | reason
    ${'a reason'}  | ${failedStep()}                | ${'deploy to production failed'} | ${'image pull backoff'}
    ${'no reason'} | ${failedStep({ error: null })} | ${'deploy to production failed'} | ${null}
    ${'no title'}  | ${failedStep({ title: '' })}   | ${'Step failed'}                 | ${'image pull backoff'}
  `('when a step failed with $scenario', ({ step, title, reason }) => {
    beforeEach(async () => {
      await createComponent({ failedSteps: [step] });
    });

    it('renders the title', () => {
      expect(findTitle().text()).toBe(title);
    });

    it('renders the reason', () => {
      expect(reasonText()).toBe(reason);
    });

    it('renders the danger icon', () => {
      expect(findStatusIcon().props('name')).toBe('status-failed');
    });
  });

  describe('when several steps failed', () => {
    beforeEach(async () => {
      await createComponent({
        failedSteps: [
          failedStep(),
          failedStep({ nodeId: 'item-2', title: 'smoke tests', error: 'assertion failed' }),
        ],
      });
    });

    it('renders a row per failure', () => {
      expect(findTitles().wrappers.map((title) => title.text())).toEqual([
        'deploy to production failed',
        'smoke tests failed',
      ]);
    });

    it('renders a reason per failure', () => {
      expect(findReasons().wrappers.map((reason) => reason.text())).toEqual([
        'image pull backoff',
        'assertion failed',
      ]);
    });
  });

  describe.each`
    state         | buildGate       | gateTitle
    ${'pending'}  | ${pendingGate}  | ${'Prod sign-off'}
    ${'resolved'} | ${approvedGate} | ${'Approved Prod sign-off'}
  `('when a step failed and a gate is $state', ({ buildGate, gateTitle }) => {
    beforeEach(async () => {
      await createComponent({ gates: [buildGate()], failedSteps: [failedStep()] });
    });

    it('renders the failure before the gate', () => {
      expect(findTitles().wrappers.map((title) => title.text())).toEqual([
        'deploy to production failed',
        gateTitle,
      ]);
    });
  });

  describe('when a step failed and the gate can still be resolved', () => {
    beforeEach(async () => {
      await createComponent({ gates: [pendingGate()], failedSteps: [failedStep()] });
    });

    it('renders the approve and reject buttons', () => {
      expect(findApproveButton().exists()).toBe(true);
      expect(findRejectButton().exists()).toBe(true);
    });
  });
});
