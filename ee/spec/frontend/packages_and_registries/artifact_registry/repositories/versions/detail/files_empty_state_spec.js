import { GlButton, GlEmptyState } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import FilesEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/files_empty_state.vue';

describe('ArtifactRegistryFilesEmptyState', () => {
  let wrapper;

  const createComponent = ({ format = 'MAVEN', versionString = '3.2.1' } = {}) => {
    wrapper = mountExtended(FilesEmptyState, { propsData: { format, versionString } });
  };

  const findEmptyState = () => wrapper.findComponent(GlEmptyState);

  beforeEach(() => createComponent());

  it('names the version, so the state cannot be read as the whole page being empty', () => {
    expect(findEmptyState().props('title')).toBe('Version 3.2.1 stores no files');
  });

  it('says why the version holds none', () => {
    expect(findEmptyState().props('description')).toBe(
      'Its files may have been deleted from the registry.',
    );
  });

  describe('an npm version, which holds one file', () => {
    beforeEach(() => createComponent({ format: 'NPM' }));

    it('reads in the singular, matching the tab npm names "File"', () => {
      expect(findEmptyState().props('title')).toBe('Version 3.2.1 stores no file');
      expect(findEmptyState().props('description')).toBe(
        'Its file may have been deleted from the registry.',
      );
    });
  });

  it('renders an illustration', () => {
    expect(findEmptyState().props('svgPath')).toContain('empty-package');
  });

  it('offers no action, since there is nowhere to send the reader', () => {
    expect(wrapper.findComponent(GlButton).exists()).toBe(false);
    expect(wrapper.findAll('a')).toHaveLength(0);
  });
});
