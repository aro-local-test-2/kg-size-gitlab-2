import { GlDisclosureDropdown } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import DashboardsListItemActions from 'ee/vue_shared/components/dashboards_list/dashboards_list_item_actions.vue';
import DashboardDeleteModal from 'ee/vue_shared/components/dashboards_list/dashboard_delete_modal.vue';

describe('DashboardsListItemActions (EE)', () => {
  let wrapper;

  const mockToastShow = jest.fn();

  const defaultProps = {
    id: 'gid://gitlab/Analytics::CustomDashboard/1',
    name: 'My dashboard',
    system: false,
    dashboardUrl: '/dashboards/my-dashboard',
    actionLabel: 'More actions for My dashboard',
  };

  const createWrapper = (props = {}, mountFn = shallowMountExtended) => {
    wrapper = mountFn(DashboardsListItemActions, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      mocks: {
        $toast: { show: mockToastShow },
      },
    });
  };

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findOpenAction = () => wrapper.findComponentByTestId('dashboard-open-action');
  const findCopyLinkAction = () => wrapper.findComponentByTestId('dashboard-copy-link-action');
  const findDeleteAction = () => wrapper.findComponentByTestId('dashboard-delete-action');
  const findDeleteModal = () => wrapper.findComponent(DashboardDeleteModal);

  describe('rendering', () => {
    beforeEach(() => {
      createWrapper({}, mountExtended);
    });

    it('renders the actions dropdown with the accessible name as sr-only toggle text', () => {
      expect(findDropdown().props()).toMatchObject({
        icon: 'ellipsis_v',
        category: 'tertiary',
        textSrOnly: true,
        noCaret: true,
        toggleText: 'More actions for My dashboard',
      });
    });

    it('renders all action items for custom dashboards', () => {
      expect(findOpenAction().text()).toBe('Open dashboard');
      expect(findCopyLinkAction().text()).toBe('Copy link');
      expect(findDeleteAction().text()).toBe('Delete dashboard');
    });

    it('renders an icon on each action', () => {
      expect(findOpenAction().props('icon')).toBe('dashboard');
      expect(findCopyLinkAction().props('icon')).toBe('link');
      expect(findDeleteAction().props('icon')).toBe('remove');
    });

    it('renders delete action with danger variant', () => {
      expect(findDeleteAction().props('variant')).toBe('danger');
    });
  });

  describe('for system dashboards', () => {
    beforeEach(() => {
      createWrapper({ system: true }, mountExtended);
    });

    it('does not render the delete action or its modal', () => {
      expect(findDeleteAction().exists()).toBe(false);
      expect(findDeleteModal().exists()).toBe(false);
    });

    it('still renders the other actions', () => {
      expect(findOpenAction().exists()).toBe(true);
      expect(findCopyLinkAction().exists()).toBe(true);
    });
  });

  describe('open dashboard action', () => {
    beforeEach(() => {
      createWrapper({}, mountExtended);
    });

    it('renders a link to the dashboard URL', () => {
      expect(findOpenAction().find('a').attributes('href')).toBe('/dashboards/my-dashboard');
    });
  });

  describe('copy link action', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('copies the absolute dashboard URL to the clipboard', () => {
      expect(findCopyLinkAction().attributes('data-clipboard-text')).toBe(
        'http://test.host/dashboards/my-dashboard',
      );
    });

    it('shows a toast when clicked', () => {
      findCopyLinkAction().vm.$emit('action');

      expect(mockToastShow).toHaveBeenCalledWith('Link copied to clipboard.');
    });
  });

  describe('delete action', () => {
    beforeEach(() => {
      createWrapper({}, mountExtended);
    });

    it('shows the delete modal when clicked', async () => {
      const showSpy = jest.spyOn(findDeleteModal().vm, 'show');
      findDeleteAction().vm.$emit('action');
      await nextTick();
      expect(showSpy).toHaveBeenCalled();
    });

    it('passes correct dashboard ID to the modal', () => {
      expect(findDeleteModal().props('dashboardId')).toBe(defaultProps.id);
    });

    it('passes the dashboard name to the modal so the confirmation can name it', () => {
      expect(findDeleteModal().props('dashboardName')).toBe(defaultProps.name);
    });

    it('hides the modal when delete is successful', async () => {
      const hideSpy = jest.spyOn(findDeleteModal().vm, 'hide');
      findDeleteModal().vm.$emit('delete');
      await nextTick();
      expect(hideSpy).toHaveBeenCalled();
    });

    it('shows a toast naming the deleted dashboard when delete is successful', async () => {
      findDeleteModal().vm.$emit('delete');
      await nextTick();
      expect(mockToastShow).toHaveBeenCalledWith('My dashboard deleted');
    });
  });

  describe('tooltip', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('renders with a generic tooltip title', () => {
      expect(findDropdown().attributes('title')).toBe('More actions');
    });
  });
});
