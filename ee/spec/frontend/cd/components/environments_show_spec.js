import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DeploymentDetails from 'ee/cd/components/deployment_details.vue';
import EnvironmentsShow from 'ee/cd/components/environments_show.vue';
import cdEnvironmentQuery from 'ee/cd/graphql/environments/cd_environment.query.graphql';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import {
  buildEnvironmentQueryResponse,
  makeCdEnvironment,
  makeCdEnvironmentApplication,
} from './mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

const ENVIRONMENT_ID = '42';
const ENVIRONMENT_GID = 'gid://gitlab/Cd::Environment/42';

describe('EnvironmentsShow', () => {
  let wrapper;

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findNotFound = () => wrapper.findComponent(GlEmptyState);
  const findPageHeading = () => wrapper.findComponent(PageHeading);
  const findEnvironmentName = () => wrapper.findByTestId('environment-name');
  const findRunningAppsTile = () => wrapper.findByTestId('metadata-tile-running-apps');
  const findBackLink = () => wrapper.findComponentByTestId('back-link');
  const findDeploymentDetails = () => wrapper.findComponent(DeploymentDetails);

  const createComponent = ({ id = ENVIRONMENT_ID, handler } = {}) => {
    const queryHandler =
      handler ??
      jest
        .fn()
        .mockResolvedValue(
          buildEnvironmentQueryResponse(makeCdEnvironment({ id: ENVIRONMENT_GID })),
        );

    wrapper = shallowMountExtended(EnvironmentsShow, {
      apolloProvider: createMockApollo([[cdEnvironmentQuery, queryHandler]]),
      propsData: { id },
      stubs: {
        RouterLink: { template: '<a><slot /></a>' },
      },
    });
  };

  describe('loading state', () => {
    describe('while the query is in flight', () => {
      beforeEach(() => {
        createComponent();
      });

      it('shows a loading icon', () => {
        expect(findLoadingIcon().exists()).toBe(true);
        expect(findPageHeading().exists()).toBe(false);
        expect(findNotFound().exists()).toBe(false);
      });
    });

    describe('when the query resolves', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('hides the loading icon', () => {
        expect(findLoadingIcon().exists()).toBe(false);
      });
    });
  });

  describe('when the environment is found', () => {
    const applicationNodes = [makeCdEnvironmentApplication()];
    const environment = makeCdEnvironment({
      id: ENVIRONMENT_GID,
      name: 'acme-production',
      applicationsCount: 7,
      applications: {
        __typename: 'CdEnvironmentApplicationConnection',
        nodes: applicationNodes,
      },
    });

    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(buildEnvironmentQueryResponse(environment)),
      });
      await waitForPromises();
    });

    it('renders the environment name as the page heading', () => {
      expect(findEnvironmentName().text()).toBe('acme-production');
    });

    it('renders the deployed applications section with the queried applications', () => {
      expect(findDeploymentDetails().exists()).toBe(true);
      expect(findDeploymentDetails().props('applications')).toEqual(applicationNodes);
    });

    it('renders the Running Apps tile with the applicationsCount value', () => {
      const tile = findRunningAppsTile();

      expect(tile.text()).toContain('Running Apps');
      expect(tile.text()).toContain('7');
    });

    it('renders the back link to the environments index', () => {
      expect(findBackLink().text()).toContain('All environments');
      expect(findBackLink().props('icon')).toBe('arrow-left');
    });
  });

  describe('when the applications count is missing', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValue(
            buildEnvironmentQueryResponse(
              makeCdEnvironment({ id: ENVIRONMENT_GID, applicationsCount: null }),
            ),
          ),
      });
      await waitForPromises();
    });

    it('renders the Running Apps tile with an em-dash placeholder', () => {
      expect(findRunningAppsTile().text()).toContain('—');
    });
  });

  describe('when the environment is not found (null response)', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(buildEnvironmentQueryResponse(null)),
      });
      await waitForPromises();
    });

    it('renders the not-found empty state', () => {
      expect(findNotFound().exists()).toBe(true);
    });

    it('does not render the page heading', () => {
      expect(findPageHeading().exists()).toBe(false);
    });

    it('does not render the deployed applications section', () => {
      expect(findDeploymentDetails().exists()).toBe(false);
    });

    it('does not render the loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(false);
    });
  });

  describe('when the query fails', () => {
    const error = new Error('GraphQL error');

    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockRejectedValue(error),
      });
      await waitForPromises();
    });

    it('captures the error with Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    it('renders the not-found empty state as a fallback', () => {
      expect(findNotFound().exists()).toBe(true);
    });
  });
});
