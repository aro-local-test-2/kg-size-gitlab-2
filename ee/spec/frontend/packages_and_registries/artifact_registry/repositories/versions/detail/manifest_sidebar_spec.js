import { GlBadge } from '@gitlab/ui';
import { RouterLinkStub } from '@vue/test-utils';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ManifestSidebar from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_sidebar.vue';
import {
  ARTIFACT_ID_FOR,
  MANIFEST_PARENT_DIGEST,
  mockManifestDetails,
  mockManifestImageDetails,
  mockManifestRepository,
  mockRepository,
} from '../../../mock_data';

const ARTIFACT_ID = ARTIFACT_ID_FOR.DOCKER;

describe('ArtifactRegistryManifestSidebar', () => {
  let wrapper;

  const createComponent = ({
    repository = mockManifestRepository(),
    manifest = mockManifestDetails(),
  } = {}) => {
    wrapper = mountExtended(ManifestSidebar, {
      propsData: { repository, manifest, artifactId: ARTIFACT_ID },
      stubs: { RouterLink: RouterLinkStub },
    });
  };

  const findRepository = () => wrapper.findByTestId('manifest-repository');
  const findImage = () => wrapper.findByTestId('manifest-image');
  const findPlatforms = () => wrapper.findByTestId('manifest-platforms');
  const findPlatformChildren = () => wrapper.findAllByTestId('manifest-platform-child');
  const findPlatform = () => wrapper.findByTestId('manifest-platform');
  const findReferencedBy = () => wrapper.findByTestId('manifest-referenced-by');
  const findParents = () => wrapper.findAllByTestId('manifest-referenced-by-parent');
  const findSize = () => wrapper.findByTestId('manifest-size');
  const findPublished = () => wrapper.findByTestId('manifest-published');
  const findHeadings = () => wrapper.findAll('h2').wrappers.map((h) => h.text());
  const routeOf = (link) => link.props('to');

  describe('the repository block', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the repository and links back to it', () => {
      const link = findRepository().findComponent(RouterLinkStub);

      expect(link.text()).toBe(mockRepository.name);
      expect(routeOf(link)).toMatchObject({
        name: 'repository_detail',
        params: { id: mockRepository.name },
      });
    });

    it('badges the repository kind', () => {
      expect(findRepository().findComponent(GlBadge).text()).toBe('Hosted');
    });
  });

  describe('the image block', () => {
    it('names the image the manifest belongs to', () => {
      createComponent();

      expect(findImage().text()).toContain('payment-service');
    });

    it('renders no image block when the image did not resolve', () => {
      createComponent({ repository: mockManifestRepository({ image: null }) });

      expect(findImage().exists()).toBe(false);
    });
  });

  describe('when the manifest is an index', () => {
    beforeEach(() => {
      createComponent();
    });

    it('lists one row per child platform', () => {
      expect(findPlatformChildren()).toHaveLength(3);
    });

    it('labels each row by its platform triple', () => {
      expect(findPlatformChildren().wrappers.map((row) => row.text())).toEqual([
        expect.stringContaining('linux/amd64'),
        expect.stringContaining('linux/arm64/v8'),
        expect.stringContaining('linux/386'),
      ]);
    });

    it('links each child to its own manifest page, scoped to this image', () => {
      const links = findPlatformChildren().wrappers.map((row) => row.findComponent(RouterLinkStub));

      expect(links.map((link) => link.text())).toEqual([
        '111111111111',
        '222222222222',
        '333333333333',
      ]);
      expect(links.map(routeOf)).toEqual(
        [1, 2, 3].map((marker) => ({
          name: 'manifest_detail',
          params: {
            id: mockRepository.name,
            artifactId: ARTIFACT_ID,
            digest: `sha256:${String(marker).repeat(64)}`,
          },
        })),
      );
    });

    it('states no platform of its own, because an index has none', () => {
      expect(findPlatform().exists()).toBe(false);
    });

    it('renders no referenced-by block, because nothing references it', () => {
      expect(findReferencedBy().exists()).toBe(false);
    });
  });

  describe('when a child carries no platform triple at all', () => {
    beforeEach(() => {
      createComponent({
        manifest: mockManifestDetails({
          children: [
            {
              __typename: 'ArtifactRegistryManifestPlatform',
              digest: `sha256:${'9'.repeat(64)}`,
              architecture: null,
              os: null,
              osVariant: null,
            },
          ],
        }),
      });
    });

    it('keeps the row and renders its digest alone', () => {
      expect(findPlatformChildren()).toHaveLength(1);
      expect(findPlatformChildren().at(0).text()).toBe('999999999999');
    });
  });

  describe('when the manifest is a single image', () => {
    beforeEach(() => {
      createComponent({ manifest: mockManifestImageDetails() });
    });

    it('states its own platform in the singular', () => {
      expect(findPlatform().text()).toContain('linux/amd64');
    });

    it('lists no platforms block, because it has no children', () => {
      expect(findPlatforms().exists()).toBe(false);
    });

    it('links back to the index that references it', () => {
      const link = findReferencedBy().findComponent(RouterLinkStub);

      expect(link.text()).toBe('b2c3d4e5b2c3');
      expect(routeOf(link)).toMatchObject({
        name: 'manifest_detail',
        params: {
          id: mockRepository.name,
          artifactId: ARTIFACT_ID,
          digest: MANIFEST_PARENT_DIGEST,
        },
      });
    });
  });

  describe('when more than one index references the image', () => {
    const OTHER_PARENT = `sha256:${'c3d4e5f6'.repeat(8)}`;

    beforeEach(() => {
      createComponent({
        manifest: mockManifestImageDetails({
          parentDigests: [MANIFEST_PARENT_DIGEST, OTHER_PARENT],
        }),
      });
    });

    it('renders a row per index rather than only the first', () => {
      expect(findParents()).toHaveLength(2);
    });

    it('links each one to its own manifest page', () => {
      expect(
        findParents().wrappers.map(
          (row) => routeOf(row.findComponent(RouterLinkStub)).params.digest,
        ),
      ).toEqual([MANIFEST_PARENT_DIGEST, OTHER_PARENT]);
    });
  });

  describe('the accessible names of the digest links', () => {
    it('names a child by its platform, so the link reads in isolation', () => {
      createComponent();

      expect(
        findPlatformChildren().at(0).findComponent(RouterLinkStub).attributes('aria-label'),
      ).toBe('Manifest 111111111111 for linux/amd64');
    });

    it('names a child carrying no platform by its digest alone', () => {
      createComponent({
        manifest: mockManifestDetails({
          children: [
            {
              __typename: 'ArtifactRegistryManifestPlatform',
              digest: `sha256:${'9'.repeat(64)}`,
              architecture: null,
              os: null,
              osVariant: null,
            },
          ],
        }),
      });

      expect(
        findPlatformChildren().at(0).findComponent(RouterLinkStub).attributes('aria-label'),
      ).toBe('Manifest 999999999999');
    });

    it('names a parent, which otherwise reads as a bare hex string', () => {
      createComponent({ manifest: mockManifestImageDetails() });

      expect(findReferencedBy().findComponent(RouterLinkStub).attributes('aria-label')).toBe(
        'Manifest b2c3d4e5b2c3',
      );
    });
  });

  describe('when the children array is null rather than empty', () => {
    it('renders no platforms block rather than throwing', () => {
      createComponent({ manifest: mockManifestDetails({ children: null }) });

      expect(findPlatforms().exists()).toBe(false);
      expect(findPlatform().exists()).toBe(false);
    });
  });

  describe('when the parent digests are null rather than empty', () => {
    it('renders no referenced-by block rather than throwing', () => {
      createComponent({ manifest: mockManifestImageDetails({ parentDigests: null }) });

      expect(findReferencedBy().exists()).toBe(false);
    });
  });

  describe('when a single image carries no platform triple', () => {
    it('renders neither block rather than an empty heading', () => {
      createComponent({
        manifest: mockManifestImageDetails({ architecture: null, os: null }),
      });

      expect(findPlatform().exists()).toBe(false);
      expect(findPlatforms().exists()).toBe(false);
    });
  });

  describe('the size', () => {
    it('renders it in human units', () => {
      createComponent();

      expect(findSize().text()).toContain('3.07 MiB');
    });

    it('renders it on a remote repository too', () => {
      createComponent({ repository: mockManifestRepository({ kind: 'REMOTE' }) });

      expect(findSize().exists()).toBe(true);
    });

    it('renders an exact zero, which is a real size for an empty layer set', () => {
      createComponent({ manifest: mockManifestDetails({ size: '0' }) });

      expect(findSize().text()).toContain('0 B');
    });

    it('withholds the block when no size arrived', () => {
      createComponent({ manifest: mockManifestDetails({ size: null }) });

      expect(findSize().exists()).toBe(false);
    });
  });

  describe('the published date', () => {
    it('renders the date the manifest was created', () => {
      createComponent();

      expect(findPublished().text()).toContain('Jun 10, 2026');
    });

    it('reads a null timestamp as unknown rather than as the epoch', () => {
      createComponent({ manifest: mockManifestDetails({ createdAt: null }) });

      expect(findPublished().text()).toContain('Unknown');
      expect(wrapper.findByTestId('manifest-published-unknown').exists()).toBe(true);
    });
  });

  describe('what the sidebar deliberately does not render', () => {
    beforeEach(() => {
      createComponent();
    });

    it.each(['Downloads', 'Source'])('renders no %s block', (heading) => {
      expect(findHeadings()).not.toContain(heading);
    });
  });

  describe('the order of the headed blocks', () => {
    it('follows the design for a single image', () => {
      createComponent({ manifest: mockManifestImageDetails() });

      expect(findHeadings()).toEqual([
        'Repository',
        'Image',
        'Platform',
        'Referenced by',
        'Published',
      ]);
    });

    it('follows the design for an index', () => {
      createComponent();

      expect(findHeadings()).toEqual(['Repository', 'Image', 'Platforms', 'Published']);
    });
  });
});
