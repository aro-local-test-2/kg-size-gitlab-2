import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import {
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_REMOTE,
} from 'ee/packages_and_registries/artifact_registry/constants';
import ArtifactsEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/detail/artifacts_empty_state.vue';
import ArtifactsSection from 'ee/packages_and_registries/artifact_registry/repositories/detail/artifacts_section.vue';
import ArtifactsTable from 'ee/packages_and_registries/artifact_registry/repositories/detail/artifacts_table.vue';
import { mockImagePage, mockRepository, mockRepositoryPermissions } from '../../mock_data';

describe('ArtifactRegistryArtifactsSection', () => {
  let wrapper;

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findTable = () => wrapper.findComponent(ArtifactsTable);
  const findEmptyState = () => wrapper.findComponent(ArtifactsEmptyState);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(ArtifactsSection, {
      propsData: {
        name: mockRepository.name,
        format: 'DOCKER',
        kind: REPOSITORY_KIND_HOSTED,
        ...props,
      },
    });
  };

  describe('while the read is in flight', () => {
    beforeEach(() => createComponent({ loading: true }));

    it('renders a loading affordance', () => {
      expect(findSkeleton().exists()).toBe(true);
    });

    it('renders nothing else, so an in-flight read is not mistaken for an empty repository', () => {
      expect(findTable().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the read failed', () => {
    beforeEach(() => createComponent({ hasError: true }));

    it('reports the failure in this region', () => {
      expect(wrapper.findByTestId('artifacts-error').text()).toBe(
        'The Artifact Registry service is unavailable.',
      );
    });

    it('renders no table and no empty state', () => {
      expect(findTable().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
      expect(findSkeleton().exists()).toBe(false);
    });

    it('reports the failure ahead of an empty page, which it cannot vouch for', () => {
      createComponent({ hasError: true, artifacts: [] });

      expect(findAlert().exists()).toBe(true);
      expect(findEmptyState().exists()).toBe(false);
    });

    it('reports it ahead of a remote repository’s empty table, for the same reason', () => {
      createComponent({ kind: REPOSITORY_KIND_REMOTE, hasError: true, artifacts: [] });

      expect(findAlert().exists()).toBe(true);
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('when the repository holds artifacts', () => {
    beforeEach(() => createComponent({ artifacts: mockImagePage.nodes }));

    it('renders them in the table', () => {
      expect(findTable().props()).toEqual({
        name: mockRepository.name,
        format: 'DOCKER',
        kind: REPOSITORY_KIND_HOSTED,
        artifacts: mockImagePage.nodes,
        permissions: null,
      });
    });

    it('renders no empty state', () => {
      expect(findEmptyState().exists()).toBe(false);
    });

    // The kind decides the table's columns and whether a row links, so a section that kept the
    // hosted shape would render a remote repository as a hosted one.
    it('hands the table a remote repository’s kind', () => {
      createComponent({ kind: REPOSITORY_KIND_REMOTE, artifacts: mockImagePage.nodes });

      expect(findTable().props('kind')).toBe(REPOSITORY_KIND_REMOTE);
    });
  });

  describe('when the repository holds artifacts and the verdicts have resolved', () => {
    const permissions = mockRepositoryPermissions();

    beforeEach(() => createComponent({ artifacts: mockImagePage.nodes, permissions }));

    it('hands the table the verdicts it was given', () => {
      expect(findTable().props('permissions')).toEqual(permissions);
    });
  });

  describe('when a hosted repository holds no artifacts', () => {
    beforeEach(() => createComponent({ artifacts: [] }));

    it('shows the empty state', () => {
      expect(findEmptyState().props()).toEqual({
        name: mockRepository.name,
        format: 'DOCKER',
      });
    });

    it('renders no table', () => {
      expect(findTable().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when a remote repository holds no artifacts', () => {
    beforeEach(() => createComponent({ kind: REPOSITORY_KIND_REMOTE, artifacts: [] }));

    it('renders the table', () => {
      expect(findTable().props()).toEqual({
        name: mockRepository.name,
        format: 'DOCKER',
        kind: REPOSITORY_KIND_REMOTE,
        artifacts: [],
        permissions: null,
      });
    });

    it('renders no empty state', () => {
      expect(findEmptyState().exists()).toBe(false);
    });
  });
});
