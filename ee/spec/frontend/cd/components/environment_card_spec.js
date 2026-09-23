import { RouterLinkStub } from '@vue/test-utils';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnvironmentCard from 'ee/cd/components/environment_card.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  defaultAvailableAgents,
  makeCdEnvironment,
  makeCdEnvironmentDriverBinding,
} from './mock_data';

describe('EnvironmentCard', () => {
  let wrapper;

  const findCardLink = () => wrapper.findComponentByTestId('environment-card-link');
  const findRelease = () => wrapper.findByTestId('environment-card-release');
  const findLastDeploy = () => wrapper.findByTestId('environment-card-last-deploy');
  const findTimeAgo = () => findLastDeploy().findComponent(TimeAgoTooltip);
  const findDeployedBy = () => wrapper.findByTestId('environment-card-deployed-by');
  const findApps = () => wrapper.findByTestId('environment-card-apps');
  const findClusterAgent = () => wrapper.findByTestId('environment-card-cluster-agent');

  const createComponent = ({
    environment = makeCdEnvironment(),
    agents = defaultAvailableAgents,
  } = {}) => {
    wrapper = shallowMountExtended(EnvironmentCard, {
      propsData: { environment, agents },
      stubs: {
        RouterLink: RouterLinkStub,
      },
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders the environment name', () => {
    expect(wrapper.text()).toContain('prod-eu-west-1');
  });

  it('links the environment name to its detail page', () => {
    expect(findCardLink().props('to')).toEqual({
      name: 'environments_show_route',
      params: { id: '1' },
    });
  });

  it('renders the Kubernetes infrastructure type', () => {
    expect(wrapper.text()).toContain('Kubernetes');
  });

  it('renders the applications count', () => {
    expect(findApps().text()).toBe('5 apps');
  });

  it('renders the name of the agent the driver config points at', () => {
    expect(findClusterAgent().text()).toBe('production-agent');
  });

  describe('when the environment has a latest finished rollout environment', () => {
    it('renders the version set name as the release', () => {
      expect(findRelease().text()).toBe('v2.4.1');
    });

    it('renders the last deploy time', () => {
      expect(findTimeAgo().props('time')).toBe('2026-07-01T10:00:00Z');
    });

    it('renders the username of the principal that triggered the first rollout transition', () => {
      expect(findDeployedBy().text()).toBe('jdoe');
    });
  });

  describe('when the environment has no latest finished rollout environment', () => {
    beforeEach(() => {
      createComponent({
        environment: makeCdEnvironment({ latestFinishedRolloutEnvironment: null }),
      });
    });

    it('renders a placeholder for the release', () => {
      expect(findRelease().text()).toBe('—');
    });

    it('renders a placeholder for the last deploy time', () => {
      expect(findTimeAgo().exists()).toBe(false);
      expect(findLastDeploy().text()).toBe('—');
    });

    it('renders a placeholder for the deployed by value', () => {
      expect(findDeployedBy().text()).toBe('—');
    });
  });

  describe('when the environment has no applications', () => {
    beforeEach(() => {
      createComponent({
        environment: makeCdEnvironment({ applicationsCount: 0 }),
      });
    });

    it('renders a zero applications count', () => {
      expect(findApps().text()).toBe('0 apps');
    });
  });

  describe('when the environment has multiple driver binding versions', () => {
    beforeEach(() => {
      createComponent({
        environment: makeCdEnvironment({
          environmentDriverBindings: {
            nodes: [
              makeCdEnvironmentDriverBinding(),
              makeCdEnvironmentDriverBinding({
                id: 'gid://gitlab/Cd::EnvironmentDriverBinding/2',
                version: 2,
                driverConfig: { cluster_agent_id: '2' },
              }),
            ],
          },
        }),
      });
    });

    it('renders the cluster agent name of the highest version', () => {
      expect(findClusterAgent().text()).toBe('staging-agent');
    });
  });

  describe('when the environment has no driver bindings', () => {
    beforeEach(() => {
      createComponent({
        environment: makeCdEnvironment({ environmentDriverBindings: { nodes: [] } }),
      });
    });

    it('renders a placeholder for the cluster agent name', () => {
      expect(findClusterAgent().text()).toBe('—');
    });
  });

  describe('when the driver config carries no cluster agent id', () => {
    beforeEach(() => {
      createComponent({
        environment: makeCdEnvironment({
          environmentDriverBindings: {
            nodes: [makeCdEnvironmentDriverBinding({ driverConfig: {} })],
          },
        }),
      });
    });

    it('renders a placeholder for the cluster agent name', () => {
      expect(findClusterAgent().text()).toBe('—');
    });
  });

  describe('when the driver config points at an agent the viewer cannot see', () => {
    beforeEach(() => {
      createComponent({
        environment: makeCdEnvironment({
          environmentDriverBindings: {
            nodes: [makeCdEnvironmentDriverBinding({ driverConfig: { cluster_agent_id: '99' } })],
          },
        }),
      });
    });

    it('renders a placeholder for the cluster agent name', () => {
      expect(findClusterAgent().text()).toBe('—');
    });
  });

  describe('when the agents have not loaded yet', () => {
    beforeEach(() => {
      createComponent({ agents: [] });
    });

    it('renders a placeholder for the cluster agent name', () => {
      expect(findClusterAgent().text()).toBe('—');
    });
  });
});
