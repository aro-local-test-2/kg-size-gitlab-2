import MockAdapter from 'axios-mock-adapter';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_CREATED, HTTP_STATUS_UNPROCESSABLE_ENTITY } from '~/lib/utils/http_status';
import { createAlert } from '~/alert';
import DuoReadinessAgentConfigRow from 'ee/pages/projects/shared/permissions/components/duo_readiness_agent_config_row.vue';
import DuoReadinessRow from '~/pages/projects/shared/permissions/components/duo_readiness_row.vue';

jest.mock('~/alert');

const GENERATE_PATH = '/g/p/-/settings/gitlab_duo/agent_config';
const SESSIONS_PATH = '/g/p/-/automate/agent-sessions';

const defaultReadiness = {
  agentConfigPresent: true,
  agentConfigPath: '/g/p/-/blob/main/.gitlab/duo/agent-config.yml',
  agentConfigMergeRequestPath: null,
  generateAvailable: true,
  repositoryEmpty: false,
  canGenerate: true,
  generatePath: GENERATE_PATH,
};

describe('DuoReadinessAgentConfigRow', () => {
  let wrapper;
  let mock;

  const createComponent = ({ readiness = {}, flowExecutionEnabled = true } = {}) => {
    wrapper = mountExtended(DuoReadinessAgentConfigRow, {
      propsData: {
        readiness: { ...defaultReadiness, ...readiness },
        flowExecutionEnabled,
        projectFullPath: 'g/p',
      },
    });
  };

  const findRow = () => wrapper.findComponent(DuoReadinessRow);
  const findAction = () => wrapper.findByTestId('agent-config-row-action');

  beforeEach(() => {
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
  });

  describe('when the file is on the default branch', () => {
    beforeEach(() => {
      createComponent();
    });

    it('is done and links to the file', () => {
      expect(findRow().props('status')).toBe('done');
      expect(findAction().text()).toBe('View file');
    });
  });

  // The file is optional, so the row must not imply agents are blocked without it.
  it('does not claim agents are blocked', () => {
    createComponent({ readiness: { agentConfigPresent: false } });

    const description = findRow().props('description');

    expect(description).toBe(
      'Add a config file to customize how flows run in CI/CD. File not found.',
    );
    expect(description).not.toMatch(/can.?not run/i);
  });

  // Every link here leaves the settings page, which still holds unsaved toggles.
  it('opens the file it links to in a new tab', () => {
    createComponent({ readiness: { agentConfigPresent: true, agentConfigPath: '/f.yml' } });

    expect(findAction().attributes('target')).toBe('_blank');
  });

  it('is blocked on flow execution rather than prompting', () => {
    createComponent({ readiness: { agentConfigPresent: false }, flowExecutionEnabled: false });

    expect(findRow().props('status')).toBe('blocked');
    expect(findAction().exists()).toBe(false);
  });

  describe('when the repository is empty', () => {
    beforeEach(() => {
      createComponent({
        readiness: { agentConfigPresent: false, generateAvailable: false, repositoryEmpty: true },
      });
    });

    it('is blocked, explains the missing commit, and offers no action', () => {
      expect(findRow().props('status')).toBe('blocked');
      expect(findRow().props('description')).toBe(
        'The repository is empty. Push a first commit, then return here to generate a config file.',
      );
      expect(findAction().exists()).toBe(false);
    });
  });

  it('links the session of a run that is already in progress at load', () => {
    createComponent({ readiness: { agentConfigPresent: false, agentConfigWorkflowId: 7 } });

    expect(findRow().props('description')).toBe(
      'Generating the file. The session opens a merge request when it finishes.',
    );
    expect(findAction().text()).toBe('View session');
    expect(findAction().attributes('href')).toBe(`${SESSIONS_PATH}/7`);
  });

  it('links an open merge request rather than offering Generate again', () => {
    createComponent({
      readiness: {
        agentConfigPresent: false,
        agentConfigMergeRequestPath: '/g/p/-/merge_requests/7',
      },
    });

    expect(findAction().text()).toBe('View merge request');
    expect(findAction().attributes('href')).toBe('/g/p/-/merge_requests/7');
  });

  it.each`
    scenario                    | readiness
    ${'the user cannot set up'} | ${{ agentConfigPresent: false, canGenerate: false }}
    ${'Duo Developer is off'}   | ${{ agentConfigPresent: false, generateAvailable: false }}
  `('offers no action when $scenario', ({ readiness }) => {
    createComponent({ readiness });

    expect(findAction().exists()).toBe(false);
  });

  describe('generating the file', () => {
    const createGeneratable = () => createComponent({ readiness: { agentConfigPresent: false } });

    it('starts a session and links to it', async () => {
      mock.onPost(GENERATE_PATH).reply(HTTP_STATUS_CREATED, { workflow_id: 42 });
      createGeneratable();

      findAction().trigger('click');
      await waitForPromises();

      expect(mock.history.post).toHaveLength(1);
      expect(findRow().props('description')).toBe(
        'Generating the file. The session opens a merge request when it finishes.',
      );
      expect(findAction().attributes('href')).toBe(`${SESSIONS_PATH}/42`);
    });

    describe('when the request is rejected', () => {
      beforeEach(async () => {
        mock.onPost(GENERATE_PATH).reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, {
          message: 'An initializer run is already in progress.',
        });
        createGeneratable();

        findAction().trigger('click');
        await waitForPromises();
      });

      it('surfaces the server message and keeps the action', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'An initializer run is already in progress.' }),
        );
        expect(findAction().text()).toBe('Generate');
      });
    });

    describe('when the request is rejected because a run is already active', () => {
      beforeEach(async () => {
        mock.onPost(GENERATE_PATH).reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, {
          message: 'An initializer run is already in progress.',
          workflow_id: 42,
        });
        createGeneratable();

        findAction().trigger('click');
        await waitForPromises();
      });

      it('links the running session instead of alerting', () => {
        expect(createAlert).not.toHaveBeenCalled();
        expect(findAction().text()).toBe('View session');
        expect(findAction().attributes('href')).toBe(`${SESSIONS_PATH}/42`);
      });
    });
  });
});
