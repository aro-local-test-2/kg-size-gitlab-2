import { waitFor } from '@testing-library/vue';
import {
  expectGraphQLCalls,
  lastRequestVariables,
  snapshotRequests,
} from 'ee_jest/integration/core/operation_helpers';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { availableAgentsResponse, environmentTiersResponse } from 'ee_jest/integration/cd/handlers';
import {
  expectListToShow,
  findPanel,
  findRegisterButton,
  mountCdApp,
  readCardField,
  withinPanel,
} from './test_setup';

const ORGANIZATION_ID = environmentTiersResponse.data.organization.id;
const [PRODUCTION_AGENT] = availableAgentsResponse.data.organization.cdAvailableAgents.nodes;
const PRODUCTION_AGENT_NUMERIC_ID = String(getIdFromGraphQLId(PRODUCTION_AGENT.id));

const NEW_ENVIRONMENT = 'production-ap';
// Only the first page is on screen; the fixtures are capped at two environments per page.
const EXISTING_ENVIRONMENTS = ['production-eu', 'dev-sandbox'];

describe('CD register environment panel', () => {
  const findNameInput = () => document.querySelector('#environment-name');
  const findSubmitButton = () =>
    document.querySelector('[data-testid="submit-environment-button"]');
  const findListboxToggle = (testId) => document.querySelector(`[data-testid="${testId}"] button`);
  const findListboxOption = (name) => () => withinPanel()?.queryByRole('option', { name }) ?? null;

  const selectListboxItem = async (testId, name) => {
    await waitAndClick(() => findListboxToggle(testId));
    await waitAndClick(findListboxOption(name));
  };

  const openPanel = async () => {
    await waitAndClick(findRegisterButton);
    await waitForElement(findPanel);
  };

  beforeEach(async () => {
    createPortalElement();

    mountCdApp();

    await expectListToShow(EXISTING_ENVIRONMENTS);
    await openPanel();
  });

  describe('when the form is filled in and submitted', () => {
    let baseline;

    beforeEach(async () => {
      await waitAndSetValue(findNameInput, NEW_ENVIRONMENT);
      await selectListboxItem('tier-listbox', 'Production');
      await selectListboxItem('agent-listbox', PRODUCTION_AGENT.name);

      baseline = snapshotRequests();

      findSubmitButton().click();
    });

    it('sends the values chosen in the form to the create mutation', async () => {
      await waitFor(() => {
        expect(lastRequestVariables('cdEnvironmentCreate')).toEqual({
          input: {
            name: NEW_ENVIRONMENT,
            tier: 'PRODUCTION',
            organizationId: ORGANIZATION_ID,
            environmentDriverBinding: {
              driverRef: 'argo-rollouts',
              // The driver stores the raw numeric id, not the global id the picker holds.
              driverConfig: { cluster_agent_id: PRODUCTION_AGENT_NUMERIC_ID },
            },
          },
        });
      });
    });

    it('adds the new environment to the list without refetching it', async () => {
      await expectListToShow([...EXISTING_ENVIRONMENTS, NEW_ENVIRONMENT]);

      expectGraphQLCalls(baseline, {
        expect: ['cdEnvironmentCreate'],
        forbid: ['cdEnvironments'],
      });
    });

    it('shows the agent chosen in the form on the new card', async () => {
      await expectListToShow([...EXISTING_ENVIRONMENTS, NEW_ENVIRONMENT]);

      expect(readCardField(NEW_ENVIRONMENT, 'environment-card-cluster-agent')).toBe(
        PRODUCTION_AGENT.name,
      );
    });

    it('closes the panel', async () => {
      await waitForElementToBeNull(findPanel);
    });
  });

  describe.each`
    missing    | fill                                                               | error
    ${'name'}  | ${() => selectListboxItem('agent-listbox', PRODUCTION_AGENT.name)} | ${'Name is required.'}
    ${'agent'} | ${() => waitAndSetValue(findNameInput, NEW_ENVIRONMENT)}           | ${'Select a GitLab Agent.'}
  `('when the $missing is missing', ({ fill, error }) => {
    let baseline;

    beforeEach(async () => {
      await fill();

      baseline = snapshotRequests();

      findSubmitButton().click();
    });

    it('reports the error and does not call the mutation', async () => {
      await waitFor(() => {
        expect(getText(findPanel())).toContain(error);
      });

      expectGraphQLCalls(baseline, { expect: [], forbid: ['cdEnvironmentCreate'] });
    });
  });
});
