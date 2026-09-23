import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ApplicationHeader from 'ee/cd/components/application_details/application_header.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';

const APPLICATION = {
  id: 'gid://gitlab/Cd::Application/5',
  name: 'data-pipeline',
  description: 'An application',
  lastDeployedAt: '2024-06-01T00:00:00Z',
  services: { count: 2 },
  environments: { count: 2 },
};

describe('ApplicationHeader', () => {
  let wrapper;

  const createComponent = (application = {}) => {
    wrapper = shallowMountExtended(ApplicationHeader, {
      propsData: { application: { ...APPLICATION, ...application } },
      slots: { actions: '<button>Create release</button>' },
      stubs: { PageHeading },
    });
  };

  const findMeta = () => wrapper.findByTestId('application-meta');
  const findLastDeployed = () => wrapper.findByTestId('last-deployed');
  const findTimeAgo = () => wrapper.findComponent(TimeAgoTooltip);

  beforeEach(() => {
    createComponent();
  });

  it('shows the application name', () => {
    expect(wrapper.findByTestId('page-heading').text()).toBe('data-pipeline');
  });

  it('shows the description', () => {
    expect(wrapper.text()).toContain('An application');
  });

  it('renders the actions slot', () => {
    expect(wrapper.text()).toContain('Create release');
  });

  it('shows the service and environment counts', () => {
    expect(findMeta().text()).toContain('2 services');
    expect(findMeta().text()).toContain('2 environments');
  });

  describe('last deployment', () => {
    it('renders the time as a tooltip', () => {
      expect(findTimeAgo().props('time')).toBe('2024-06-01T00:00:00Z');
    });

    it('is omitted when the application has never been deployed', () => {
      createComponent({ lastDeployedAt: null });

      expect(findLastDeployed().exists()).toBe(false);
    });
  });
});
