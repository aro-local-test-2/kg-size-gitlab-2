import { RouterLinkStub } from '@vue/test-utils';
import { GlTableLite } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import DeploymentDetails from 'ee/cd/components/deployment_details.vue';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import { makeCdEnvironmentApplication } from './mock_data';

const makeHealthNode = ({ id, versions = [] }) => ({
  __typename: 'CdServiceEnvironmentHealth',
  id: `gid://gitlab/Cd::ServiceEnvironmentHealth/${id}`,
  deployedVersions: {
    __typename: 'CdVersionConnection',
    nodes: versions.map(({ name, createdAt }, index) => ({
      __typename: 'CdVersion',
      id: `gid://gitlab/Cd::Version/${id}-${index}`,
      name,
      createdAt,
    })),
  },
});

describe('DeploymentDetails', () => {
  let wrapper;

  const findHeading = () => wrapper.findByTestId('deployed-applications-heading');
  const findTable = () => wrapper.findComponent(GlTableLite);
  const findRows = () => wrapper.findAll('tbody tr');
  const findApplicationLinks = () => wrapper.findAllComponents(RouterLinkStub);
  const findReleaseVersion = () => wrapper.findByTestId('release-version');
  const findTimeAgo = () => wrapper.findComponent(TimeAgo);
  const findEmptyMessage = () => wrapper.findByTestId('no-applications');

  const createComponent = ({ applications = [makeCdEnvironmentApplication()] } = {}) => {
    wrapper = mountExtended(DeploymentDetails, {
      propsData: { applications },
      stubs: {
        RouterLink: RouterLinkStub,
      },
    });
  };

  it('renders the section heading', () => {
    createComponent();

    expect(findHeading().text()).toBe('Deployed applications');
  });

  describe('with deployed applications', () => {
    beforeEach(() => {
      createComponent({
        applications: [
          makeCdEnvironmentApplication(),
          makeCdEnvironmentApplication({
            application: {
              __typename: 'CdApplication',
              id: 'gid://gitlab/Cd::Application/6',
              name: 'data-pipeline',
              lastDeployedAt: '2026-08-02T10:00:00Z',
            },
            servicesCount: 3,
          }),
        ],
      });
    });

    it('renders a row per application', () => {
      expect(findRows()).toHaveLength(2);
    });

    it('links each application name to its detail route', () => {
      const links = findApplicationLinks();

      expect(links.at(0).text()).toBe('payments-platform');
      expect(links.at(1).text()).toBe('data-pipeline');
      expect(links.at(0).props('to')).toEqual({
        name: 'applications_show_route',
        params: { id: '5' },
      });
    });

    it('renders the deployed release version', () => {
      expect(findReleaseVersion().text()).toBe('v2.4.1');
    });

    it('renders the services count', () => {
      expect(findRows().at(1).text()).toContain('3');
    });

    it('renders the last deployed time', () => {
      expect(findTimeAgo().props('time')).toBe('2026-08-01T10:00:00Z');
    });
  });

  describe('when services are deployed with different versions', () => {
    beforeEach(() => {
      createComponent({
        applications: [
          makeCdEnvironmentApplication({
            serviceEnvironmentHealths: {
              __typename: 'CdServiceEnvironmentHealthConnection',
              nodes: [
                makeHealthNode({
                  id: 101,
                  versions: [{ name: 'v2.3.0', createdAt: '2026-07-01T10:00:00Z' }],
                }),
                makeHealthNode({
                  id: 103,
                  versions: [{ name: 'v2.4.1', createdAt: '2026-08-01T10:00:00Z' }],
                }),
              ],
            },
          }),
        ],
      });
    });

    it('renders only the latest version', () => {
      expect(findReleaseVersion().text()).toBe('v2.4.1');
      expect(wrapper.text()).not.toContain('v2.3.0');
    });
  });

  describe('when an application has no deployed versions and no deploy time', () => {
    beforeEach(() => {
      createComponent({
        applications: [
          makeCdEnvironmentApplication({
            application: {
              __typename: 'CdApplication',
              id: 'gid://gitlab/Cd::Application/7',
              name: 'web-frontend',
              lastDeployedAt: null,
            },
            serviceEnvironmentHealths: {
              __typename: 'CdServiceEnvironmentHealthConnection',
              nodes: [makeHealthNode({ id: 101 })],
            },
          }),
        ],
      });
    });

    it('renders placeholders for the release and last deployed columns', () => {
      expect(findReleaseVersion().exists()).toBe(false);
      expect(findTimeAgo().exists()).toBe(false);
      expect(findRows().at(0).text()).toContain('—');
    });
  });

  describe('when the environment has no deployed applications', () => {
    beforeEach(() => {
      createComponent({ applications: [] });
    });

    it('renders the empty message instead of the table', () => {
      expect(findEmptyMessage().text()).toBe('No applications are deployed to this environment.');
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('when the only application is redacted', () => {
    beforeEach(() => {
      createComponent({
        applications: [makeCdEnvironmentApplication({ application: null })],
      });
    });

    it('renders the empty message instead of the table', () => {
      expect(findEmptyMessage().exists()).toBe(true);
      expect(findTable().exists()).toBe(false);
    });
  });
});
