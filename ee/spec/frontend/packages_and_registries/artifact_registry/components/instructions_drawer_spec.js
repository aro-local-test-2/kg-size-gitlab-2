import { GlDrawer } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import InstructionsDrawer from 'ee/packages_and_registries/artifact_registry/components/instructions_drawer.vue';

jest.mock('~/lib/utils/dom_utils', () => ({
  getContentWrapperHeight: () => '123',
}));

describe('ArtifactRegistryInstructionsDrawer', () => {
  let wrapper;

  const MountingPortalStub = {
    name: 'MountingPortalStub',
    props: { mountTo: { type: String }, append: { type: Boolean } },
    template: '<div><slot /></div>',
  };

  // Focus only moves for an element the document holds, so the focus cases mount into it.
  const createComponent = ({ props = {}, slots = {}, attachTo } = {}) => {
    wrapper = mountExtended(InstructionsDrawer, {
      propsData: { title: 'Pull command', open: true, ...props },
      slots,
      stubs: { MountingPortal: MountingPortalStub },
      attachTo,
    });
  };

  const findDrawer = () => wrapper.findComponent(GlDrawer);
  const findTitle = () => wrapper.find('h2');

  describe('the drawer it renders', () => {
    beforeEach(() => createComponent());

    it('wires the drawer the way the layout requires', () => {
      expect(findDrawer().props()).toMatchObject({
        open: true,
        headerHeight: '123',
        headerSticky: true,
        zIndex: 252,
      });
    });

    it('mounts at the body, so the panel cannot clip a fixed drawer', () => {
      expect(wrapper.findComponent(MountingPortalStub).props()).toMatchObject({
        mountTo: 'body',
        append: true,
      });
    });

    it('names itself, because a drawer carries no accessible name of its own', () => {
      expect(findTitle().text()).toBe('Pull command');
      expect(findDrawer().attributes('aria-labelledby')).toBe(findTitle().attributes('id'));
    });

    it('closes when the drawer asks to be closed', () => {
      findDrawer().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('accessible title', () => {
    it('splits the heading into a hidden visible title and a screen-reader-only accessible title, when one is given', () => {
      createComponent({ props: { accessibleTitle: 'Pull command for 3.2.1' } });

      expect(findTitle().find('[aria-hidden="true"]').text()).toBe('Pull command');
      expect(findTitle().find('.gl-sr-only').text()).toBe('Pull command for 3.2.1');
    });

    it('renders the title alone, when no accessible title is given', () => {
      createComponent();

      expect(findTitle().text()).toBe('Pull command');
      expect(findTitle().find('.gl-sr-only').exists()).toBe(false);
    });
  });

  it('stays closed until it is opened', () => {
    createComponent({ props: { open: false } });

    expect(findDrawer().props('open')).toBe(false);
  });

  describe('two drawers on one page', () => {
    let firstTitleId;

    beforeEach(() => {
      createComponent();
      firstTitleId = findTitle().attributes('id');

      createComponent();
    });

    it('gives each a distinct title id, so neither names the other', () => {
      expect(findTitle().attributes('id')).not.toBe(firstTitleId);
    });
  });

  it('renders whatever body it is handed', () => {
    createComponent({ slots: { default: '<p data-testid="body">Install by version</p>' } });

    expect(wrapper.findByTestId('body').text()).toBe('Install by version');
  });

  describe('focus', () => {
    let trigger;

    beforeEach(() => {
      trigger = document.createElement('button');
      document.body.appendChild(trigger);
      trigger.focus();
    });

    afterEach(() => {
      trigger.remove();
    });

    it('takes focus once the drawer has finished opening', async () => {
      createComponent({ props: { open: false }, attachTo: document.body });

      await wrapper.setProps({ open: true });
      findDrawer().vm.$emit('opened');

      expect(document.activeElement).toBe(findDrawer().element);
    });

    it('hands focus back to whatever opened it, rather than dropping it on the body', async () => {
      createComponent({ props: { open: false }, attachTo: document.body });

      await wrapper.setProps({ open: true });
      findDrawer().vm.$emit('opened');
      await wrapper.setProps({ open: false });

      expect(document.activeElement).toBe(trigger);
    });
  });
});
