import { GlLoadingIcon } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import StepSidePanel from 'ee/cd/components/application_details/flow/step_side_panel.vue';
import cdRolloutApprovalGatesQuery from 'ee/cd/graphql/applications/flow/cd_rollout_approval_gates.query.graphql';
import {
  buildRolloutApprovalGateResponse,
  makeCdRolloutGate,
} from 'ee/cd/../../../../spec/frontend/cd/components/mock_data';

Vue.use(VueApollo);

const ROLLOUT_ID = 'gid://gitlab/Cd::Rollout/5';
const STEP_ID = 'gid://gitlab/Cd::RolloutStep/8';
const OTHER_STEP_ID = 'gid://gitlab/Cd::RolloutStep/99';

const deployStep = (overrides = {}) => ({
  id: STEP_ID,
  category: 'deploy',
  state: 'SUCCESS',
  title: 'Canary deploy 25%',
  environment: { id: 'gid://gitlab/Cd::Environment/1', name: 'production' },
  services: ['api', 'worker'],
  ...overrides,
});

const approvalStep = (overrides = {}) => ({
  id: STEP_ID,
  category: 'approve',
  state: 'AWAITING_APPROVAL',
  title: 'Release sign-off',
  environment: null,
  services: [],
  ...overrides,
});

const triggerStep = (overrides = {}) => ({
  id: null,
  category: 'trigger',
  state: 'SUCCESS',
  title: 'Trigger',
  releaseName: 'v1.6.2',
  environment: null,
  services: [],
  author: 'data-platform',
  ...overrides,
});

const waitStep = (overrides = {}) => ({
  id: STEP_ID,
  category: 'wait',
  state: 'PENDING',
  title: 'Wait 10m',
  environment: null,
  services: [],
  ...overrides,
});

const gateFor = ({ stepId = STEP_ID, ...overrides } = {}) => {
  const gate = makeCdRolloutGate({ state: 'APPROVED', name: 'Release sign-off', ...overrides });

  return { ...gate, step: { ...gate.step, id: stepId } };
};

const gatesHandler = (gates = []) =>
  jest.fn().mockResolvedValue(buildRolloutApprovalGateResponse({ gates }));

describe('StepSidePanel', () => {
  let wrapper;

  const findEyebrow = () => wrapper.findByTestId('step-category');
  const findTitle = () => wrapper.findByTestId('step-title');
  const findEnvironment = () => wrapper.findByTestId('step-env');
  const findState = () => wrapper.findComponentByTestId('step-state');
  const findServices = () => wrapper.findByTestId('changed-services-list');
  const findResolution = () => wrapper.findByTestId('gate-resolution');
  const findGatePending = () => wrapper.findByTestId('gate-pending');
  const findGateReason = () => wrapper.findByTestId('gate-reason');
  const findGateResolutionReason = () => wrapper.findByTestId('gate-resolution-reason');
  const findAllGateReasons = () =>
    wrapper.findAll('[data-testid="gate-reason"], [data-testid="gate-resolution-reason"]');
  const findReleaseAuthor = () => wrapper.findByTestId('release-author');
  const findPortal = () => wrapper.findComponent(MountingPortal);
  const findGateError = () => wrapper.findComponentByTestId('panel-gate-load-error');
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findStepError = () => wrapper.findComponentByTestId('step-error');

  const createComponent = async ({ step = deployStep(), handler = gatesHandler() } = {}) => {
    wrapper = shallowMountExtended(StepSidePanel, {
      apolloProvider: createMockApollo([[cdRolloutApprovalGatesQuery, handler]]),
      propsData: { rolloutId: ROLLOUT_ID, step },
      stubs: {
        DynamicPanel,
        MountingPortal: stubComponent(MountingPortal, { name: 'MountingPortal' }),
      },
    });

    await waitForPromises();
  };

  describe('header', () => {
    describe.each`
      category     | step                            | eyebrow            | title
      ${'trigger'} | ${triggerStep()}                | ${'Trigger'}       | ${'Release v1.6.2'}
      ${'deploy'}  | ${deployStep()}                 | ${'Deploy step'}   | ${'Canary deploy 25%'}
      ${'approve'} | ${approvalStep()}               | ${'Approval step'} | ${'Release sign-off'}
      ${'wait'}    | ${waitStep()}                   | ${'Wait step'}     | ${'Wait 10m'}
      ${'unknown'} | ${waitStep({ category: null })} | ${'Step'}          | ${'Wait 10m'}
    `('for a $category step', ({ step, eyebrow, title }) => {
      beforeEach(async () => {
        await createComponent({ step });
      });

      it('renders the category', () => {
        expect(findEyebrow().text()).toBe(eyebrow);
      });

      it('renders the name', () => {
        expect(findTitle().text()).toBe(title);
      });
    });

    describe.each`
      category     | step              | badge                  | variant
      ${'deploy'}  | ${deployStep()}   | ${'Succeeded'}         | ${'success'}
      ${'approve'} | ${approvalStep()} | ${'Awaiting approval'} | ${'warning'}
      ${'wait'}    | ${waitStep()}     | ${'Pending'}           | ${'neutral'}
    `('for a $category step', ({ step, badge, variant }) => {
      beforeEach(async () => {
        await createComponent({ step });
      });

      it('renders the state badge', () => {
        expect(findState().text()).toBe(badge);
      });

      it('renders the badge variant', () => {
        expect(findState().props('variant')).toBe(variant);
      });
    });

    describe('for a trigger step', () => {
      beforeEach(async () => {
        await createComponent({ step: triggerStep() });
      });

      it('renders no state badge', () => {
        expect(findState().exists()).toBe(false);
      });
    });

    describe('when the step targets an environment', () => {
      beforeEach(async () => {
        await createComponent({ step: deployStep() });
      });

      it('renders the environment name', () => {
        expect(findEnvironment().text()).toBe('production');
      });
    });

    describe('when the step targets no environment', () => {
      beforeEach(async () => {
        await createComponent({ step: waitStep() });
      });

      it('renders no environment', () => {
        expect(findEnvironment().exists()).toBe(false);
      });
    });
  });

  describe('a deploy step', () => {
    beforeEach(async () => {
      await createComponent({ step: deployStep() });
    });

    it('renders the services it updates', () => {
      expect(
        findServices()
          .findAll('li')
          .wrappers.map((item) => item.text()),
      ).toEqual(['api', 'worker']);
    });
  });

  describe('a deploy step that updates no services', () => {
    beforeEach(async () => {
      await createComponent({ step: deployStep({ services: [] }) });
    });

    it('renders an empty state', () => {
      expect(findServices().exists()).toBe(false);
      expect(wrapper.text()).toContain('No version changes in this deploy.');
    });
  });

  describe('a failed step', () => {
    beforeEach(async () => {
      await createComponent({ step: deployStep({ state: 'FAILED', error: 'image pull failed' }) });
    });

    it('renders the failure reason', () => {
      expect(findStepError().text()).toBe('image pull failed');
    });

    it('renders the reason as a danger alert', () => {
      expect(findStepError().props('variant')).toBe('danger');
    });

    it('renders a reason that cannot be dismissed', () => {
      expect(findStepError().props('dismissible')).toBe(false);
    });
  });

  describe('a wait step', () => {
    beforeEach(async () => {
      await createComponent({ step: waitStep() });
    });

    it('renders no body', () => {
      expect(findServices().exists()).toBe(false);
      expect(findResolution().exists()).toBe(false);
    });
  });

  describe.each(['deploy', 'wait', 'trigger'])('a %s step', (category) => {
    let handler;

    beforeEach(async () => {
      handler = gatesHandler();

      await createComponent({ step: { ...waitStep(), category }, handler });
    });

    it('does not query the gates', () => {
      expect(handler).not.toHaveBeenCalled();
    });
  });

  describe('a trigger step', () => {
    beforeEach(async () => {
      await createComponent({ step: triggerStep() });
    });

    it('renders who bundled the release', () => {
      expect(findReleaseAuthor().text()).toBe('Bundled by @data-platform');
    });
  });

  describe('a trigger step for a rollout with no release', () => {
    beforeEach(async () => {
      await createComponent({ step: triggerStep({ releaseName: null, author: null }) });
    });

    it('renders the step name', () => {
      expect(findTitle().text()).toBe('Trigger');
    });

    it('renders no author', () => {
      expect(findReleaseAuthor().exists()).toBe(false);
    });
  });

  describe('an approval step', () => {
    describe('when the gate was approved', () => {
      beforeEach(async () => {
        await createComponent({ step: approvalStep(), handler: gatesHandler([gateFor()]) });
      });

      it('renders who resolved it', () => {
        expect(findResolution().text()).toContain('@alice approved');
      });
    });

    describe('when the gate was rejected', () => {
      beforeEach(async () => {
        await createComponent({
          step: approvalStep(),
          handler: gatesHandler([gateFor({ state: 'REJECTED' })]),
        });
      });

      it('renders the rejection', () => {
        expect(findResolution().text()).toContain('@alice rejected');
      });
    });

    describe('reasons', () => {
      const opened = 'Promoting to 100% needs sign-off';
      const resolved = 'not ready for prod';

      const reasonTexts = () =>
        [findGateReason(), findGateResolutionReason()].map((paragraph) =>
          paragraph.exists() ? paragraph.text() : null,
        );

      it.each`
        scenario                   | gate                                                                          | texts
        ${'neither reason'}        | ${gateFor({ state: 'REJECTED' })}                                             | ${[null, null]}
        ${'the gate reason'}       | ${gateFor({ state: 'PENDING', reason: opened })}                              | ${[opened, null]}
        ${'the resolution reason'} | ${gateFor({ state: 'REJECTED', resolutionReason: resolved })}                 | ${[null, resolved]}
        ${'both reasons'}          | ${gateFor({ state: 'REJECTED', reason: opened, resolutionReason: resolved })} | ${[opened, resolved]}
      `('renders $scenario', async ({ gate, texts }) => {
        await createComponent({ step: approvalStep(), handler: gatesHandler([gate]) });

        expect(reasonTexts()).toEqual(texts);
      });

      it('renders the reason above the resolution reason', async () => {
        await createComponent({
          step: approvalStep(),
          handler: gatesHandler([
            gateFor({ state: 'REJECTED', reason: opened, resolutionReason: resolved }),
          ]),
        });

        expect(findAllGateReasons().wrappers.map((paragraph) => paragraph.text())).toEqual([
          opened,
          resolved,
        ]);
      });
    });

    describe('when the gate is still awaiting a decision', () => {
      beforeEach(async () => {
        await createComponent({
          step: approvalStep(),
          handler: gatesHandler([gateFor({ state: 'PENDING' })]),
        });
      });

      it('renders the pending text', () => {
        expect(findGatePending().text()).toBe('Waiting for approval.');
        expect(findResolution().exists()).toBe(false);
      });
    });

    describe('when the rollout has gates for several steps', () => {
      beforeEach(async () => {
        await createComponent({
          step: approvalStep(),
          handler: gatesHandler([
            gateFor({ id: 1, username: 'other', stepId: OTHER_STEP_ID }),
            gateFor({ id: 2, username: 'alice' }),
          ]),
        });
      });

      it('renders the gate belonging to this step', () => {
        expect(findResolution().text()).toContain('@alice approved');
      });
    });

    describe('when the resolving principal is not a user', () => {
      beforeEach(async () => {
        await createComponent({
          step: approvalStep(),
          handler: gatesHandler([gateFor({ username: null })]),
        });
      });

      it('renders the resolution without a username', () => {
        expect(findResolution().text()).toBe('Approved');
      });
    });

    describe('while the gates are loading', () => {
      beforeEach(async () => {
        await createComponent({
          step: approvalStep(),
          handler: jest.fn().mockReturnValue(new Promise(() => {})),
        });
      });

      it('renders a loading icon', () => {
        expect(findLoadingIcon().exists()).toBe(true);
      });
    });

    describe('when the gates fail to load', () => {
      beforeEach(async () => {
        await createComponent({
          step: approvalStep(),
          handler: jest.fn().mockRejectedValue(new Error('nope')),
        });
      });

      it('renders an error', () => {
        expect(findGateError().text()).toBe(
          'Failed to load the approval gate. Refresh to try again.',
        );
      });

      it('renders no pending text', () => {
        expect(findGatePending().exists()).toBe(false);
      });
    });

    describe('when no gate belongs to this step', () => {
      beforeEach(async () => {
        await createComponent({
          step: approvalStep(),
          handler: gatesHandler([gateFor({ id: 1, username: 'other', stepId: OTHER_STEP_ID })]),
        });
      });

      it('renders no resolution', () => {
        expect(findResolution().exists()).toBe(false);
      });

      it('renders no pending text', () => {
        expect(findGatePending().exists()).toBe(false);
      });
    });
  });

  it('mounts into the contextual panel portal', async () => {
    await createComponent();

    expect(findPortal().attributes('mount-to')).toBe('#contextual-panel-portal');
  });
});
