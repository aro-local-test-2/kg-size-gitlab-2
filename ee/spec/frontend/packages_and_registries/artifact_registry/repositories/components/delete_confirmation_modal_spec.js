import { GlModal, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { RENDER_ALL_SLOTS_TEMPLATE, stubComponent } from 'helpers/stub_component';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';

describe('ArtifactRegistryDeleteConfirmationModal', () => {
  let wrapper;

  const target = { id: 'gid://version/1' };
  const copy = {
    title: 'Delete version?',
    body: 'This permanently deletes %{name}. This action cannot be undone.',
    name: '3.2.1',
    actionText: 'Delete version',
  };

  const findModal = () => wrapper.findComponent(GlModal);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(DeleteConfirmationModal, {
      propsData: { target, ...copy, ...props },
      stubs: {
        GlModal: stubComponent(GlModal, { template: RENDER_ALL_SLOTS_TEMPLATE }),
        GlSprintf,
      },
    });
  };

  it('stays closed while no target is set', () => {
    createComponent({ target: null });

    expect(findModal().props('visible')).toBe(false);
  });

  it('opens once a target is set', () => {
    createComponent();

    expect(findModal().props('visible')).toBe(true);
  });

  describe('the copy', () => {
    it('renders what the caller supplied, with the name interpolated', () => {
      createComponent();

      expect(findModal().props('title')).toBe('Delete version?');
      expect(findModal().text()).toBe(
        'This permanently deletes 3.2.1. This action cannot be undone.',
      );
      expect(findModal().props('actionPrimary')).toEqual({
        text: 'Delete version',
        attributes: { variant: 'danger', category: 'primary' },
      });
    });

    it('offers a plain cancel', () => {
      createComponent();

      expect(findModal().props('actionCancel')).toEqual({ text: 'Cancel' });
    });

    it('holds the copy after the target is cleared, so the body survives the fade', async () => {
      createComponent();

      await wrapper.setProps({ target: null, title: '', body: '', name: '', actionText: '' });

      expect(findModal().props('visible')).toBe(false);
      expect(findModal().props('title')).toBe('Delete version?');
      expect(findModal().text()).toBe(
        'This permanently deletes 3.2.1. This action cannot be undone.',
      );
    });

    it('carries an accessible name before it has ever opened', () => {
      createComponent({ target: null });

      expect(findModal().props('visible')).toBe(false);
      expect(findModal().props('title')).toBe('Delete version?');
    });

    it('re-snapshots the copy when it opens on a different target', async () => {
      createComponent();

      await wrapper.setProps({ target: null, name: '' });
      await wrapper.setProps({ target: { id: 'gid://version/2' }, name: '4.0.0' });

      expect(findModal().text()).toBe(
        'This permanently deletes 4.0.0. This action cannot be undone.',
      );
    });
  });

  describe('what it emits', () => {
    beforeEach(() => {
      createComponent();
    });

    it('asks for no typed confirmation', () => {
      expect(wrapper.find('input').exists()).toBe(false);
    });

    it('emits the target on confirm', () => {
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('confirm')).toEqual([[target]]);
    });

    it('clears the target when it closes', () => {
      findModal().vm.$emit('change', false);

      expect(wrapper.emitted('change')).toEqual([[null]]);
    });

    it('emits nothing when it opens', () => {
      findModal().vm.$emit('change', true);

      expect(wrapper.emitted('change')).toBeUndefined();
      expect(wrapper.emitted('confirm')).toBeUndefined();
    });
  });
});
