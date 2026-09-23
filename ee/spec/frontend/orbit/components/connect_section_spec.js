import { GlButton } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import ConnectSection from 'ee/orbit/components/connect_section.vue';
import ConnectCollapsibleSection from 'ee/orbit/components/connect_collapsible_section.vue';
import * as orbitApi from 'ee/orbit/api/orbit_api';

jest.mock('ee/orbit/api/orbit_api');

describe('ConnectSection', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = shallowMount(ConnectSection, {
      propsData: props,
    });
  };

  const findSectionTitles = () =>
    wrapper.findAllComponents(ConnectCollapsibleSection).wrappers.map((s) => s.props('title'));
  const findCodeNavigationSection = () =>
    wrapper
      .findAllComponents(ConnectCollapsibleSection)
      .wrappers.find((s) => s.props('title') === 'Use Orbit in your repositories');

  beforeEach(() => {
    orbitApi.fetchOrbitTools.mockResolvedValue({ data: [] });
  });

  describe('code navigation section', () => {
    describe('when code navigation is available', () => {
      beforeEach(async () => {
        createWrapper({ codeNavigationAvailable: true });
        await waitForPromises();
      });

      it('renders the section', () => {
        expect(findCodeNavigationSection().exists()).toBe(true);
      });

      it('uses the Orbit icon', () => {
        expect(findCodeNavigationSection().props('icon')).toBe('orbit');
      });

      it('links to the code navigation documentation in a new tab', () => {
        const button = findCodeNavigationSection().findComponent(GlButton);

        expect(button.attributes('href')).toBe('/help/user/project/code_navigation');
        expect(button.attributes('target')).toBe('_blank');
        // Distinguishes it from the page-level "Learn more" link for screen readers.
        expect(button.attributes('aria-label')).toBe('Learn more about code navigation');
      });

      it('renders as its own section, after GitLab Duo', () => {
        expect(findSectionTitles()).toEqual([
          'Use GitLab Orbit with GitLab Duo',
          'Use Orbit in your repositories',
          'Connect GitLab Orbit to your tools',
        ]);
      });
    });

    describe('when code navigation is not available', () => {
      beforeEach(async () => {
        createWrapper({ codeNavigationAvailable: false });
        await waitForPromises();
      });

      it('does not render the section', () => {
        expect(findCodeNavigationSection()).toBeUndefined();
      });

      it('still renders the other sections', () => {
        expect(findSectionTitles()).toContain('Use GitLab Orbit with GitLab Duo');
      });
    });
  });
});
