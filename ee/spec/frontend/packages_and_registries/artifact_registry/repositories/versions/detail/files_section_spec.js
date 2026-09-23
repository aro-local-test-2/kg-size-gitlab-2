import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import mavenFilesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version_files.query.graphql.json';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FilesEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/files_empty_state.vue';
import FilesSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/files_section.vue';
import FilesTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/files_table.vue';

const mavenFiles =
  mavenFilesFixture.data.organization.artifactRegistryRepository.version.files.nodes;

describe('ArtifactRegistryFilesSection', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(FilesSection, {
      propsData: { format: 'MAVEN', files: mavenFiles, versionString: '3.2.1', ...props },
    });
  };

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findTable = () => wrapper.findComponent(FilesTable);
  const findEmptyState = () => wrapper.findComponent(FilesEmptyState);

  it('renders the table over the files it is given', () => {
    createComponent();

    expect(findTable().props()).toMatchObject({
      files: mavenFiles,
      format: 'MAVEN',
      isLoading: false,
    });
    expect(findSkeleton().exists()).toBe(false);
    expect(findAlert().exists()).toBe(false);
    expect(findEmptyState().exists()).toBe(false);
  });

  it('stands a skeleton in for the first read', () => {
    createComponent({ files: [], loading: true });

    expect(findSkeleton().exists()).toBe(true);
    expect(findTable().exists()).toBe(false);
  });

  it('marks the table busy for a re-read, rather than standing the skeleton in again', () => {
    createComponent({ loading: true });

    expect(findSkeleton().exists()).toBe(false);
    expect(findTable().props('isLoading')).toBe(true);
  });

  describe('when the version stores no files', () => {
    beforeEach(() => createComponent({ files: [] }));

    it('replaces the table with the empty state, naming the version', () => {
      expect(findEmptyState().props()).toMatchObject({ format: 'MAVEN', versionString: '3.2.1' });
      expect(findTable().exists()).toBe(false);
    });

    it('does not stand the skeleton in, since the read has settled', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  it('keeps the empty state out of a first read, which has no result yet', () => {
    createComponent({ files: [], loading: true });

    expect(findEmptyState().exists()).toBe(false);
  });

  it('prefers the alert to the empty state when a failed read returns no files', () => {
    createComponent({ files: [], hasError: true });

    expect(findAlert().exists()).toBe(true);
    expect(findEmptyState().exists()).toBe(false);
  });

  it('replaces the table with an alert when the read fails', () => {
    createComponent({ hasError: true });

    expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
    expect(findAlert().props()).toMatchObject({ variant: 'danger', dismissible: false });
    expect(findTable().exists()).toBe(false);
  });
});
