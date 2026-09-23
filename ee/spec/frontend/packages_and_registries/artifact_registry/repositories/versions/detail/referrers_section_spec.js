import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import getManifestReferrersQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest_referrers.query.graphql';
import ReferrersSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/referrers_section.vue';
import ReferrersTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/referrers_table.vue';
import {
  ARTIFACT_ID_FOR,
  MANIFEST_DIGEST,
  ORGANIZATION_GID,
  mockManifestReferrer,
  mockManifestReferrers,
  mockManifestReferrersRepository,
  mockRepository,
  mockRepositoryResponse,
} from '../../../mock_data';

Vue.use(VueApollo);

const ARTIFACT_ID = ARTIFACT_ID_FOR.DOCKER;

const successHandler = (repository = mockManifestReferrersRepository()) =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(repository));

describe('ArtifactRegistryReferrersSection', () => {
  let wrapper;
  let handler;

  const createComponent = ({ requestHandler = successHandler(), ...props } = {}) => {
    handler = requestHandler;

    wrapper = shallowMountExtended(ReferrersSection, {
      apolloProvider: createMockApollo(
        [[getManifestReferrersQuery, handler]],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: { organizationGid: ORGANIZATION_GID },
      propsData: {
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
        ...props,
      },
    });
  };

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findTable = () => wrapper.findComponent(ReferrersTable);

  afterEach(() => {
    handler = null;
  });

  describe('the read', () => {
    it('asks for the referrers of this manifest, under this repository and image', async () => {
      createComponent();
      await waitForPromises();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler).toHaveBeenCalledWith({
        organizationId: ORGANIZATION_GID,
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
        first: 20,
      });
    });

    it('issues the read on mount, which is what the lazy tab panel defers', () => {
      createComponent();

      expect(handler).toHaveBeenCalledTimes(1);
    });
  });

  describe('while the first read is in flight', () => {
    beforeEach(() => createComponent());

    it('stands a skeleton in for the table', () => {
      expect(findSkeleton().exists()).toBe(true);
      expect(findTable().exists()).toBe(false);
    });

    it('renders no alert, since nothing has failed', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the read resolves', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the table over the referrers it read', () => {
      expect(findTable().props('referrers')).toEqual([mockManifestReferrer()]);
    });

    it('hands the table what it needs to address each row own page', () => {
      expect(findTable().props()).toMatchObject({
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        subjectDigest: MANIFEST_DIGEST,
        isLoading: false,
      });
    });

    it('replaces the skeleton', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  describe('when the manifest has no referrers', () => {
    beforeEach(async () => {
      createComponent({
        requestHandler: successHandler(
          mockManifestReferrersRepository({ referrers: mockManifestReferrers([]) }),
        ),
      });
      await waitForPromises();
    });

    it('renders the table with no rows rather than an alert', () => {
      expect(findTable().props('referrers')).toEqual([]);
      expect(findAlert().exists()).toBe(false);
    });

    it('does not stand the skeleton in, since the read has settled', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  describe('when the read fails', () => {
    beforeEach(async () => {
      createComponent({ requestHandler: jest.fn().mockRejectedValue(new Error('Unavailable')) });
      await waitForPromises();
    });

    it('replaces the table with an alert', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findAlert().props()).toMatchObject({ variant: 'danger', dismissible: false });
      expect(findTable().exists()).toBe(false);
    });

    it('renders no skeleton once the failure has settled', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  // A manifest that stopped resolving is a failure, not a manifest nothing attests to, and the
  // two must not present alike.
  describe.each`
    case                | repository
    ${'the repository'} | ${null}
    ${'the manifest'}   | ${mockManifestReferrersRepository({ manifest: null })}
    ${'the connection'} | ${mockManifestReferrersRepository({ referrers: null })}
  `('when $case does not resolve', ({ repository }) => {
    beforeEach(async () => {
      createComponent({ requestHandler: successHandler(repository) });
      await waitForPromises();
    });

    it('renders the alert rather than an empty table', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findTable().exists()).toBe(false);
    });
  });
});
