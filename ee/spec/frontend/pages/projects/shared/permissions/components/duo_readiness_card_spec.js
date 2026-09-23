import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlProgressBar } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DuoReadinessCard from '~/pages/projects/shared/permissions/components/duo_readiness_card.vue';
import runnerAvailableQuery from 'ee/pages/projects/shared/permissions/graphql/duo_workflow_runner_available.query.graphql';
import duoMcpServersCountQuery from 'ee/pages/projects/shared/permissions/graphql/duo_mcp_servers_count.query.graphql';

Vue.use(VueApollo);

describe('DuoReadinessCard', () => {
  let wrapper;

  const runnerResponse = (available) => ({
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        duoWorkflowRunnerAvailable: available,
        duoWorkflowUsableRunnerType: available ? 'instance_type' : null,
      },
    },
  });

  const createComponent = ({ runnerAvailable = true, ...props } = {}) => {
    wrapper = mountExtended(DuoReadinessCard, {
      apolloProvider: createMockApollo([
        [runnerAvailableQuery, jest.fn().mockResolvedValue(runnerResponse(runnerAvailable))],
        [
          duoMcpServersCountQuery,
          jest.fn().mockResolvedValue({
            data: { project: { id: 'gid://gitlab/Project/1', duoMcpServersCount: 0 } },
          }),
        ],
      ]),
      propsData: {
        duoEnabledSetting: {
          label: 'GitLab Duo',
          helpText: 'Use AI-native features in this project.',
          helpPath: '/help/user/gitlab_duo/_index',
        },
        duoReadiness: {
          platformEnabled: true,
          runnersPath: '/g/p/-/settings/ci_cd',
          agentConfigPresent: true,
        },
        projectFullPath: 'g/p',
        duoEnabled: true,
        duoRemoteFlowsAvailability: true,
        ...props,
      },
    });
  };

  const findCount = () => wrapper.findByTestId('readiness-progress-count');
  const findStateLine = () => wrapper.findByTestId('readiness-state-line');
  const findProgressBar = () => wrapper.findComponent(GlProgressBar);

  describe('progress header', () => {
    it('counts the runner only once its check resolves', async () => {
      createComponent();

      expect(findCount().text()).toBe('1 step left');

      await waitForPromises();

      expect(findCount().text()).toBe('All steps complete');
      expect(findProgressBar().props()).toMatchObject({
        value: 5,
        max: 5,
        variant: 'success',
        ariaLabel: 'Agent setup progress: 5 of 5 steps complete',
      });
    });

    describe('when every required step is done', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('reads ready', () => {
        expect(findStateLine().text()).toBe('Ready. Flows can run in this project.');
      });
    });

    describe('when the Agent Platform is off above the project', () => {
      beforeEach(async () => {
        createComponent({
          duoReadiness: { platformEnabled: false, runnersPath: '/g/p/-/settings/ci_cd' },
        });
        await waitForPromises();
      });

      it('reads blocked', () => {
        expect(findStateLine().text()).toBe(
          'Blocked: the Agent Platform is off, so nothing below can be set up yet.',
        );
      });
    });

    describe('when GitLab Duo is off', () => {
      beforeEach(async () => {
        createComponent({ duoEnabled: false });
        await waitForPromises();
      });

      it('reads not set up', () => {
        expect(findStateLine().text()).toBe('Not set up yet. To get started, turn on GitLab Duo.');
      });

      it('counts two steps left', () => {
        expect(findCount().text()).toBe('2 steps left');
        expect(findProgressBar().props('ariaLabel')).toBe(
          'Agent setup progress: 3 of 5 steps complete',
        );
      });
    });

    describe('when flow execution is off', () => {
      beforeEach(async () => {
        createComponent({ duoRemoteFlowsAvailability: false });
        await waitForPromises();
      });

      it('names the working features', () => {
        expect(findStateLine().text()).toBe(
          'Chat and Code Suggestions work today. 1 more step to set up flows.',
        );
      });
    });

    describe('when only the runner is missing', () => {
      beforeEach(async () => {
        createComponent({ runnerAvailable: false });
        await waitForPromises();
      });

      it('reads steps remaining', () => {
        expect(findCount().text()).toBe('1 step left');
        expect(findStateLine().text()).toBe('1 step left to set up flows.');
      });
    });

    it('caps the total at the five counted rows', async () => {
      createComponent({ duoFoundationalFlowsAvailability: true });
      await waitForPromises();

      expect(findCount().text()).toBe('All steps complete');
    });

    it('counts the agent configuration file', async () => {
      createComponent({
        duoReadiness: {
          platformEnabled: true,
          runnersPath: '/g/p/-/settings/ci_cd',
          agentConfigPresent: false,
        },
      });
      await waitForPromises();

      expect(findCount().text()).toBe('1 step left');
      expect(findStateLine().text()).toBe('1 step left to set up flows.');
    });
  });

  describe('settings state contract', () => {
    it('emits toggle changes back to the parent form', async () => {
      createComponent();
      await waitForPromises();

      wrapper.findComponentByTestId('duo_features_enabled_toggle').vm.$emit('change', false);
      wrapper.findComponentByTestId('duo-remote-flows-enabled').vm.$emit('change', false);

      expect(wrapper.emitted('update:duo-enabled')).toEqual([[false]]);
      expect(wrapper.emitted('update:duo-remote-flows-availability')).toEqual([[false]]);
    });

    it('links Learn more on the GitLab Duo row', async () => {
      createComponent();
      await waitForPromises();

      const link = wrapper.findByTestId('duo-row-help-link');

      expect(link.text()).toBe('Learn more');
      expect(link.attributes('href')).toBe('/help/user/gitlab_duo/_index');
      expect(link.attributes('target')).toBe('_blank');
    });

    it('keeps the toggle form fields, so the settings form still submits them', async () => {
      createComponent();
      await waitForPromises();

      expect(
        wrapper
          .find('input[name="project[project_setting_attributes][duo_features_enabled]"]')
          .exists(),
      ).toBe(true);
      expect(
        wrapper
          .find('input[name="project[project_setting_attributes][duo_remote_flows_enabled]"]')
          .exists(),
      ).toBe(true);
    });
  });
});
