import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ManifestsTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/manifests_table.vue';
import VersionListEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/versions/version_list_empty_state.vue';
import VersionsSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/versions_section.vue';
import VersionsTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/versions_table.vue';
import {
  mockManifests,
  mockRepositoryArtifacts,
  mockRepositoryPermissions,
  mockVersions,
} from '../../mock_data';

const artifactFor = (format) => {
  const { image, package: pkg } = mockRepositoryArtifacts(format);

  return pkg ?? image;
};

const DEFAULT_SORT = { sortBy: 'createdAt', sortDesc: true };

describe('ArtifactRegistryVersionsSection', () => {
  let wrapper;

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findTable = () => wrapper.findComponent(VersionsTable);
  const findManifestsTable = () => wrapper.findComponent(ManifestsTable);
  const findEmptyState = () => wrapper.findComponent(VersionListEmptyState);

  const createComponent = ({ format = 'MAVEN', sort = DEFAULT_SORT, ...props } = {}) => {
    wrapper = shallowMountExtended(VersionsSection, {
      propsData: { format, artifact: artifactFor(format), name: 'my-repository', sort, ...props },
    });
  };

  describe('while the first read is in flight', () => {
    beforeEach(() => createComponent({ loading: true }));

    it('renders a loading affordance', () => {
      expect(findSkeleton().exists()).toBe(true);
    });

    it('renders no table, so an in-flight read is not mistaken for a version-less package', () => {
      expect(findTable().exists()).toBe(false);
      expect(findManifestsTable().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the read failed', () => {
    beforeEach(() => createComponent({ hasError: true }));

    it('reports the failure in this region', () => {
      expect(wrapper.findByTestId('versions-error').text()).toBe(
        'The Artifact Registry service is unavailable.',
      );
    });

    it('renders no table and no skeleton', () => {
      expect(findTable().exists()).toBe(false);
      expect(findSkeleton().exists()).toBe(false);
    });

    it('reports the failure ahead of an empty page, which it cannot vouch for', () => {
      createComponent({ hasError: true, rows: [] });

      expect(findAlert().exists()).toBe(true);
      expect(findEmptyState().exists()).toBe(false);
      expect(findTable().exists()).toBe(false);
    });
  });

  describe.each(['MAVEN', 'NPM'])('for a %s artifact', (format) => {
    beforeEach(() => createComponent({ format, rows: mockVersions }));

    it('renders the rows as versions', () => {
      expect(findTable().props('versions')).toBe(mockVersions);
    });

    it('hands the table the artifact its row actions compose a command from', () => {
      expect(findTable().props()).toMatchObject({ format, artifact: artifactFor(format) });
    });

    it('hands the table the repository name, which the row link addresses', () => {
      expect(findTable().props('name')).toBe('my-repository');
    });

    it('renders no manifests table, no empty state, no skeleton, and no alert', () => {
      expect(findManifestsTable().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
      expect(findSkeleton().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe.each(['DOCKER', 'OCI'])('for a %s artifact', (format) => {
    beforeEach(() => createComponent({ format, rows: mockManifests }));

    it('renders the rows as manifests, which is what a container version is', () => {
      expect(findManifestsTable().props('manifests')).toBe(mockManifests);
    });

    it('hands the table the image and repository its row actions compose a command from', () => {
      expect(findManifestsTable().props()).toMatchObject({
        format,
        artifact: artifactFor(format),
        name: 'my-repository',
      });
    });

    it('threads the repository name and the image id the row delete needs', () => {
      expect(findManifestsTable().props()).toMatchObject({
        name: 'my-repository',
        imageId: artifactFor(format).id,
      });
    });

    it('renders no versions table, no empty state, no skeleton, and no alert', () => {
      expect(findTable().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
      expect(findSkeleton().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe.each`
    format      | holds
    ${'MAVEN'}  | ${'versions'}
    ${'NPM'}    | ${'versions'}
    ${'DOCKER'} | ${'manifests'}
    ${'OCI'}    | ${'manifests'}
  `('when a $format artifact holds no $holds', ({ format }) => {
    beforeEach(() => createComponent({ format, rows: [] }));

    it('renders the empty state, which words itself from the format', () => {
      expect(findEmptyState().props()).toStrictEqual({ format, name: 'my-repository' });
    });

    it('renders neither table, so no column headers stand over nothing', () => {
      expect(findTable().exists()).toBe(false);
      expect(findManifestsTable().exists()).toBe(false);
    });
  });

  describe.each`
    format      | rows             | table
    ${'MAVEN'}  | ${mockVersions}  | ${VersionsTable}
    ${'DOCKER'} | ${mockManifests} | ${ManifestsTable}
  `('the $format sort', ({ format, rows, table }) => {
    beforeEach(() =>
      createComponent({ format, rows, sort: { sortBy: 'version', sortDesc: false } }),
    );

    it('hands the table the active sort, so the header renders the order the page read', () => {
      expect(wrapper.findComponent(table).props('sort')).toEqual({
        sortBy: 'version',
        sortDesc: false,
      });
    });

    it('passes a header sort request up, because the page owns the route query it lands in', () => {
      wrapper
        .findComponent(table)
        .vm.$emit('sort-changed', { sortBy: 'createdAt', sortDesc: true });

      expect(wrapper.emitted('sort-changed')).toEqual([[{ sortBy: 'createdAt', sortDesc: true }]]);
    });
  });
  describe.each`
    format      | rows             | table
    ${'MAVEN'}  | ${mockVersions}  | ${VersionsTable}
    ${'DOCKER'} | ${mockManifests} | ${ManifestsTable}
  `('while a re-read of a $format artifact is in flight', ({ format, rows, table }) => {
    beforeEach(() => createComponent({ format, rows, loading: true }));

    it('keeps the table it already has rows for, rather than standing the skeleton in for it', () => {
      expect(wrapper.findComponent(table).exists()).toBe(true);
      expect(findSkeleton().exists()).toBe(false);
    });

    it('marks the table loading, so the rows it holds are not read as the arriving page', () => {
      expect(wrapper.findComponent(table).props('isLoading')).toBe(true);
    });
  });

  describe.each`
    format      | rows             | table
    ${'MAVEN'}  | ${mockVersions}  | ${VersionsTable}
    ${'DOCKER'} | ${mockManifests} | ${ManifestsTable}
  `('the $format table', ({ format, rows, table }) => {
    const findRenderedTable = () => wrapper.findComponent(table);

    describe('when the page carries the repository verdicts', () => {
      const permissions = mockRepositoryPermissions();

      beforeEach(() => createComponent({ format, rows, permissions }));

      it('hands them down, because the row delete reads them', () => {
        expect(findRenderedTable().props('permissions')).toBe(permissions);
      });
    });

    describe('when the page carries no verdict yet', () => {
      beforeEach(() => createComponent({ format, rows }));

      it('hands the table none, so no row delete renders optimistically', () => {
        expect(findRenderedTable().props('permissions')).toBeNull();
      });
    });
  });
});
