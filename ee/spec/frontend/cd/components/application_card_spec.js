import { GlDisclosureDropdown, GlSprintf } from '@gitlab/ui';
import { RouterLinkStub } from '@vue/test-utils';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ProjectAvatar from '~/vue_shared/components/project_avatar.vue';
import ApplicationCard from 'ee/cd/components/application_card.vue';
import { makeApplication as makeSharedApplication } from './mock_data';

describe('ApplicationCard', () => {
  let wrapper;

  const makeApplication = (config = {}) =>
    makeSharedApplication({
      id: 'gid://gitlab/Cd::Application/1',
      name: 'My App',
      lastDeployedAt: '2024-01-15T10:00:00Z',
      services: { count: 2 },
      ...config,
    });

  const findCardLink = () => wrapper.findComponentByTestId('application-card-link');
  const findHeading = () => wrapper.find('h2');
  const findProjectAvatar = () => wrapper.findComponent(ProjectAvatar);
  const findDisclosureDropdown = () => wrapper.findComponent(GlDisclosureDropdown);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(ApplicationCard, {
      propsData: {
        application: {},
        ...props,
      },
      stubs: {
        RouterLink: RouterLinkStub,
        GlSprintf,
        TimeAgo,
      },
    });
  };

  describe('default', () => {
    const application = makeApplication({
      id: 'gid://gitlab/Cd::Application/1',
      name: 'Alpha',
      lastDeployedAt: '2020-04-01T00:00:00Z',
    });

    beforeEach(() => {
      createComponent({ application });
    });

    it('renders project avatar', () => {
      expect(findProjectAvatar().props('projectName')).toBe('Alpha');
    });

    it('renders the application name', () => {
      expect(findHeading().text()).toBe('Alpha');
    });

    it('renders the formatted last-deployed time', () => {
      expect(wrapper.text()).toContain('3 months ago');
    });

    it('sets the correct route for each link', () => {
      expect(findCardLink().props('to')).toEqual({
        name: 'applications_show_route',
        params: { id: '1' },
      });
    });
  });

  describe('manage access dropdown', () => {
    beforeEach(() => {
      createComponent({ application: makeApplication() });
    });

    it('renders a "Manage access" dropdown item', () => {
      expect(findDisclosureDropdown().props('items')).toMatchObject([{ text: 'Manage access' }]);
    });

    it('emits manage-access when the item is clicked', () => {
      findDisclosureDropdown().props('items')[0].action();

      expect(wrapper.emitted('manage-access')).toEqual([[]]);
    });
  });

  describe('services text', () => {
    it('renders the singular form when there is one service', () => {
      createComponent({ application: makeApplication({ services: { count: 1 } }) });

      expect(wrapper.text()).toContain('1 service');
    });

    it('renders the plural form when there are multiple services', () => {
      createComponent({ application: makeApplication({ services: { count: 4 } }) });

      expect(wrapper.text()).toContain('4 services');
    });
  });

  describe('with null lastDeployedAt', () => {
    beforeEach(() => {
      createComponent({ application: makeApplication({ lastDeployedAt: null }) });
    });

    it('does not render the last-deployed text when lastDeployedAt is null', () => {
      expect(wrapper.text()).not.toContain('Last deployed');
    });
  });
});
