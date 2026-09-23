import { GlButton } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import { stubComponent } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import ManageAccessPanel from 'ee/cd/components/manage_access_panel.vue';
import { makeApplication } from './mock_data';

describe('ManageAccessPanel', () => {
  let wrapper;

  const application = makeApplication({ name: 'acme-platform' });

  const findMountingPortal = () => wrapper.findComponent(MountingPortal);
  const findDynamicPanel = () => wrapper.findComponent(DynamicPanel);
  const findCrudComponents = () => wrapper.findAllComponents(CrudComponent);
  const findDirectMembersCrud = () => findCrudComponents().at(0);
  const findInheritedMembersCrud = () => findCrudComponents().at(1);

  const createComponent = ({ open = true, props = {} } = {}) => {
    wrapper = shallowMountExtended(ManageAccessPanel, {
      propsData: {
        open,
        application,
        ...props,
      },
      stubs: {
        DynamicPanel,
        MountingPortal: stubComponent(MountingPortal, { name: 'MountingPortal' }),
      },
    });
  };

  describe('when open is false', () => {
    beforeEach(() => {
      createComponent({ open: false });
    });

    it('does not render the panel', () => {
      expect(findMountingPortal().exists()).toBe(false);
    });
  });

  describe('when open is true', () => {
    beforeEach(() => {
      createComponent({ open: true });
    });

    it('renders the application name as heading', () => {
      expect(wrapper.find('h2').text()).toBe('acme-platform');
    });

    it('renders a "Direct members" crud component with an "Add members" action', () => {
      expect(findDirectMembersCrud().props('title')).toBe('Direct members');
      expect(findDirectMembersCrud().findComponent(GlButton).text()).toBe('Add members');
    });

    it('renders an "Inherited members" crud component with a "Manage access" action', () => {
      expect(findInheritedMembersCrud().props('title')).toBe('Inherited members');
      expect(findInheritedMembersCrud().findComponent(GlButton).text()).toBe('Manage access');
    });

    it('emits close when the panel emits close', () => {
      findDynamicPanel().vm.$emit('close');

      expect(wrapper.emitted('close')).toEqual([[]]);
    });
  });
});
