import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  CLIENT_BASE_URL,
  ORGANIZATION_GID,
  SLUG,
  mockArtifactRepository,
  mockRepository,
  mockRepositoryResponse,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from '../../../graphql/cache_config';
import { manifestLadderFor, mockArtifacts } from '../../../graphql/mock_artifacts';
import { mockResolvers } from '../../../graphql/mock_resolvers';
import getManifestQuery from '../../../graphql/queries/get_manifest.query.graphql';
import getManifestReferrersQuery from '../../../graphql/queries/get_manifest_referrers.query.graphql';
import { createRouter } from '../../../router';
import ManifestDetail from './manifest_detail.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

const OCI_IMAGE_INDEX = 'application/vnd.oci.image.index.v1+json';

const generatedImage = (format) => mockArtifacts(mockRepository.name, format)[0];

const repositoryHandler =
  (format, { kind = 'HOSTED', image } = {}) =>
  () => {
    const { id, name } = generatedImage(format);

    return Promise.resolve(
      mockRepositoryResponse({
        ...mockArtifactRepository(format, { kind }),
        image: image === undefined ? { __typename: 'ArtifactRegistryImage', id, name } : image,
      }),
    );
  };

const ladderOf = (format) => manifestLadderFor(generatedImage(format).id);

const indexManifest = (format) =>
  ladderOf(format).find(({ mediaType }) => mediaType === OCI_IMAGE_INDEX);

const childManifest = (format) => ladderOf(format).find(({ parentsCount }) => parentsCount > 0);

const referrerManifest = (format) => ladderOf(format).find(({ subjectDigest }) => subjectDigest);

const manifestThatIs = (format, predicate) => ladderOf(format).find(predicate) ?? {};

const attestedManifest = (format) => manifestThatIs(format, ({ referrersCount }) => referrersCount);

const unattestedManifest = (format) =>
  manifestThatIs(format, ({ referrersCount }) => !referrersCount);

export default {
  component: ManifestDetail,
  title: 'ee/artifact_registry/repositories/versions/detail/manifest_detail',
};

const Template =
  ({
    format = 'DOCKER',
    handler = repositoryHandler(format),
    artifactId = generatedImage(format).id,
    digest = indexManifest(format).digest,
    query = {},
    manifestResolver = mockResolvers.ArtifactRegistryRepositoryDetails.manifest,
    referrersHandler = handler,
    referrersResolver = mockResolvers.ArtifactRegistryManifestDetails.referrers,
  } = {}) =>
  () => {
    const router = createRouter(BASE_PATH);
    router.push({
      path: `/${mockRepository.name}/${artifactId}/manifests/${encodeURIComponent(digest)}`,
      query,
    });

    return {
      components: { ManifestDetail },
      router,
      apolloProvider: createMockApollo(
        [
          [getManifestQuery, handler],
          [getManifestReferrersQuery, referrersHandler],
        ],
        {
          ArtifactRegistryRepositoryDetails: { manifest: manifestResolver },
          ArtifactRegistryManifestDetails: { referrers: referrersResolver },
        },
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: {
        breadCrumbState: {
          artifactName: '',
          manifestName: '',
          updateArtifactName() {},
          updateManifestName() {},
        },
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
      },
      template: '<manifest-detail />',
    };
  };

export const Default = Template();

export const ManyTags = Template({
  manifestResolver: async (...args) => {
    const manifest = await mockResolvers.ArtifactRegistryRepositoryDetails.manifest(...args);

    return manifest && { ...manifest, tags: Array.from({ length: 40 }, (_, i) => `release-${i}`) };
  },
});

export const LongTagName = Template({
  manifestResolver: async (...args) => {
    const manifest = await mockResolvers.ArtifactRegistryRepositoryDetails.manifest(...args);

    return manifest && { ...manifest, tags: ['a'.repeat(128), 'latest'] };
  },
});

export const OciIndex = Template({ format: 'OCI' });

export const UntaggedOverview = Template({
  manifestResolver: async (...args) => {
    const manifest = await mockResolvers.ArtifactRegistryRepositoryDetails.manifest(...args);

    return manifest && { ...manifest, tags: [] };
  },
});

export const ReferrersTab = Template({
  digest: attestedManifest('DOCKER').digest,
  query: { tab: 'referrers' },
});

export const ReferrersTabLoading = Template({
  digest: attestedManifest('DOCKER').digest,
  query: { tab: 'referrers' },
  referrersHandler: () => new Promise(() => {}),
});

export const ReferrersTabUnavailable = Template({
  digest: attestedManifest('DOCKER').digest,
  query: { tab: 'referrers' },
  referrersHandler: () => Promise.reject(new Error('Unavailable')),
});

export const ReferrersTabNone = Template({
  digest: unattestedManifest('DOCKER').digest,
  query: { tab: 'referrers' },
});

export const SinglePlatformImage = Template({ digest: childManifest('DOCKER').digest });

export const Referrer = Template({ digest: referrerManifest('DOCKER').digest });

export const Loading = Template({ handler: () => new Promise(() => {}) });

export const ServiceUnavailable = Template({
  handler: () => Promise.reject(new Error('Unavailable')),
});

export const NotFound = Template({
  handler: () => Promise.resolve(mockRepositoryResponse(null)),
});

export const ImageUnnamed = Template({
  handler: repositoryHandler('DOCKER', { image: null }),
});

export const ManifestNotFound = Template({ digest: `sha256:${'0'.repeat(64)}` });

export const ManifestOfAnotherImage = Template({
  digest: manifestLadderFor(mockArtifacts(mockRepository.name, 'DOCKER')[1].id)[0].digest,
});
