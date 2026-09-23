import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { RouterLinkStub } from '@vue/test-utils';
import { GlAlert, GlSkeletonLoader, GlTab, GlTabs } from '@gitlab/ui';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import waitForPromises from 'helpers/wait_for_promises';
import BaseLayout from '~/vue_shared/components/base_layout.vue';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import NotFound from 'ee/packages_and_registries/artifact_registry/components/not_found.vue';
import FormatLogo from 'ee/packages_and_registries/artifact_registry/repositories/components/format_logo.vue';
import ManifestDetail from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_detail.vue';
import ManifestOverview from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_overview.vue';
import ManifestSidebar from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_sidebar.vue';
import ReferrersSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/referrers_section.vue';
import getManifestQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest.query.graphql';
import getManifestReferrersQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest_referrers.query.graphql';
import {
  ARTIFACT_ID_FOR,
  CLIENT_BASE_URL,
  MANIFEST_DIGEST,
  MOCK_IMAGE_MEDIA_TYPE,
  MOCK_INDEX_MEDIA_TYPE,
  ORGANIZATION_GID,
  SLUG,
  mockManifestDetails,
  mockManifestReferrersRepository,
  mockManifestRepository,
  mockRepository,
  mockRepositoryResponse,
} from '../../../mock_data';

Vue.use(VueApollo);

const ARTIFACT_ID = ARTIFACT_ID_FOR.DOCKER;

const MANIFEST_PATH = `/${mockRepository.name}/${ARTIFACT_ID}/manifests/${MANIFEST_DIGEST}`;

const OTHER_DIGEST = `sha256:${'f0e1d2c3'.repeat(8)}`;

const successHandler = (repository = mockManifestRepository()) =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(repository));

const failingHandler = () => jest.fn().mockRejectedValue(new Error('Unavailable'));

const referrersHandler = () =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(mockManifestReferrersRepository()));

describe('ArtifactRegistryManifestDetail', () => {
  let wrapper;

  const updateArtifactName = jest.fn();
  const updateManifestName = jest.fn();

  const push = jest.fn();

  let referrersRequest;

  const createComponent = ({
    handler = successHandler(),
    digest = MANIFEST_DIGEST,
    query = {},
    mountFn = shallowMountExtended,
  } = {}) => {
    referrersRequest = referrersHandler();

    wrapper = mountFn(ManifestDetail, {
      apolloProvider: createMockApollo(
        [
          [getManifestQuery, handler],
          [getManifestReferrersQuery, referrersRequest],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: {
        breadCrumbState: { updateArtifactName, updateManifestName },
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
      },
      mocks: {
        $route: {
          path: MANIFEST_PATH,
          params: { id: mockRepository.name, artifactId: ARTIFACT_ID, digest },
          query,
        },
        $router: { push },
      },
      stubs: { BaseLayout, DetailLayout, PageHeading, RouterLink: RouterLinkStub },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findNotFound = () => wrapper.findComponent(NotFound);
  const findLogo = () => wrapper.findComponent(FormatLogo);
  const findAnnouncement = () => wrapper.findByTestId('manifest-announcement');
  const findHeading = () => wrapper.findByTestId('page-heading');
  const findDigest = () => wrapper.findByTestId('manifest-digest');
  const findKind = () => wrapper.findByTestId('manifest-kind');
  const findMediaType = () => wrapper.findByTestId('manifest-media-type');
  const findArtifactType = () => wrapper.findByTestId('manifest-artifact-type');
  const findSubjectDigest = () => wrapper.findByTestId('manifest-subject-digest');
  const findFullDigest = () => wrapper.findByTestId('manifest-full-digest');
  const findCopyButton = () => wrapper.findComponent(ClipboardButton);
  const findFormatName = () => wrapper.findByTestId('manifest-format-name');
  const findImageName = () => wrapper.findByTestId('image-name');
  const findTagList = () => wrapper.findByTestId('manifest-tags');
  const findTags = () => wrapper.findAllByTestId('manifest-tag');
  const findTagNames = () => findTags().wrappers.map((tag) => tag.text());
  const findSidebar = () => wrapper.findComponent(ManifestSidebar);
  const findOverview = () => wrapper.findComponent(ManifestOverview);
  const findReferrersSection = () => wrapper.findComponent(ReferrersSection);
  const findTabs = () => wrapper.findComponent(GlTabs);
  const findAllTabs = () => wrapper.findAllComponents(GlTab);
  const findTabTitles = () => findAllTabs().wrappers.map((tab) => tab.attributes('title'));
  const findCountBadge = () => wrapper.findByTestId('tab-counter-badge');
  const findCountSrText = () => findCountBadge().element.nextElementSibling;
  const findTabTexts = () => wrapper.findAllByRole('tab').wrappers.map((tab) => tab.text());

  describe('the read this page is about', () => {
    it('asks for the manifest the route names, within the image the route names', async () => {
      const handler = successHandler();

      createComponent({ handler });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        organizationId: ORGANIZATION_GID,
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
      });
    });
  });

  describe('while the read is in flight', () => {
    it('renders a skeleton rather than an empty page', () => {
      createComponent();

      expect(findSkeleton().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findDigest().exists()).toBe(false);
    });

    it('announces that the page is loading', () => {
      createComponent();

      expect(findAnnouncement().text()).toBe('Loading manifest details.');
    });
  });

  describe('when the registry cannot be reached', () => {
    it('renders the service-unavailable alert', async () => {
      createComponent({ handler: failingHandler() });
      await waitForPromises();

      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findHeading().exists()).toBe(false);
    });

    it('leaves no header standing over the alert when a refetch fails', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(mockRepositoryResponse(mockManifestRepository()))
          .mockRejectedValue(new Error('Unavailable')),
      });
      await waitForPromises();

      wrapper.vm.$apollo.queries.repository.refetch().catch(() => {});
      await waitForPromises();

      expect(findAlert().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
    });

    it('leaves the live region silent, because the alert announces itself', async () => {
      createComponent({ handler: failingHandler() });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe('');
    });
  });

  describe('when the digest names no manifest of this image', () => {
    it.each`
      case                   | repository
      ${'a null manifest'}   | ${mockManifestRepository({ manifest: null })}
      ${'a null repository'} | ${null}
    `('renders the not-found view for $case', async ({ repository }) => {
      createComponent({ handler: successHandler(repository) });
      await waitForPromises();

      expect(findNotFound().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findDigest().exists()).toBe(false);
    });

    it('announces the not-found state', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ manifest: null })) });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe('Page not found');
    });
  });

  describe('the header', () => {
    it('names the manifest by its short digest, not the whole one', async () => {
      createComponent();
      await waitForPromises();

      expect(findDigest().text()).toBe('a1b2c3d4a1b2');
    });

    it.each`
      format      | label
      ${'DOCKER'} | ${'Docker'}
      ${'OCI'}    | ${'OCI'}
    `(
      'renders the $format logo beside it, named for a reader who cannot see it',
      async ({ format, label }) => {
        createComponent({ handler: successHandler(mockManifestRepository({ format })) });
        await waitForPromises();

        expect(findLogo().props('format')).toBe(format);
        expect(findFormatName().text()).toBe(label);
      },
    );

    it('renders the kind as a badge beside the heading rather than inside it', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      expect(findKind().classes()).toContain('gl-badge');
      expect(findHeading().element.contains(findKind().element)).toBe(false);
    });

    it('names the media type, which is what tells one manifest kind from another', async () => {
      createComponent();
      await waitForPromises();

      expect(findMediaType().text()).toBe(`Media type: ${MOCK_INDEX_MEDIA_TYPE}`);
    });

    it('renders the whole digest, which the short one cannot be expanded back into', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      expect(findFullDigest().text()).toBe(`Index digest: ${MANIFEST_DIGEST}`);
    });

    it('offers the whole digest to the clipboard, not the shortened one', async () => {
      createComponent();
      await waitForPromises();

      expect(findCopyButton().props('text')).toBe(MANIFEST_DIGEST);
    });

    it('names what the copy button copies', async () => {
      createComponent();
      await waitForPromises();

      expect(findCopyButton().props('title')).toBe('Copy digest');
    });

    it('names the image the manifest belongs to, not only in the trail', async () => {
      createComponent();
      await waitForPromises();

      expect(findImageName().text()).toBe('payment-service');
    });

    it('renders no image line when the image did not resolve', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ image: null })) });
      await waitForPromises();

      expect(findImageName().exists()).toBe(false);
    });

    it('renders the populated state alone, with no state left over beside it', async () => {
      createComponent();
      await waitForPromises();

      expect(findSkeleton().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
    });
  });

  describe('a referrer manifest, which the list reaches this page from', () => {
    const referrer = (overrides = {}) =>
      successHandler(
        mockManifestRepository({
          manifest: mockManifestDetails({
            mediaType: MOCK_IMAGE_MEDIA_TYPE,
            subjectDigest: `sha256:${'b2c3d4e5'.repeat(8)}`,
            artifactType: 'application/vnd.dev.cosign.artifact.sig.v1+json',
            ...overrides,
          }),
        }),
      );

    it('calls a cosign signature a signature, the same name the manifests list gives it', async () => {
      createComponent({ handler: referrer() });
      await waitForPromises();

      expect(findKind().text()).toBe('Signature');
    });

    it('names the raw artifact type in the description, where there is room for it', async () => {
      createComponent({ handler: referrer(), mountFn: mountExtended });
      await waitForPromises();

      expect(findArtifactType().text()).toBe(
        'Artifact type: application/vnd.dev.cosign.artifact.sig.v1+json',
      );
    });

    it('names the manifest it attests to, which is the point of a referrer', async () => {
      createComponent({ handler: referrer(), mountFn: mountExtended });
      await waitForPromises();

      expect(findSubjectDigest().text()).toBe(`Subject digest: sha256:${'b2c3d4e5'.repeat(8)}`);
    });

    it('labels the digest neutrally, because it is neither an index nor a plain image', async () => {
      createComponent({ handler: referrer() });
      await waitForPromises();

      expect(findFullDigest().text()).toBe(`Manifest digest: ${MANIFEST_DIGEST}`);
    });

    it('falls back to naming it a referrer when it declares no artifact type', async () => {
      createComponent({ handler: referrer({ artifactType: null }), mountFn: mountExtended });
      await waitForPromises();

      expect(findKind().text()).toBe('Referrer');
      expect(findArtifactType().exists()).toBe(false);
    });

    it('names an unrecognised artifact type a referrer, and still prints the type', async () => {
      createComponent({
        handler: referrer({ artifactType: 'application/vnd.acme.custom+json' }),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findKind().text()).toBe('Referrer');
      expect(findArtifactType().text()).toBe('Artifact type: application/vnd.acme.custom+json');
    });
  });

  describe('what the header calls the manifest', () => {
    const withManifest = (overrides) =>
      successHandler(mockManifestRepository({ manifest: mockManifestDetails(overrides) }));

    it.each`
      childrenCount | label
      ${3}          | ${'Index · 3 platforms'}
      ${1}          | ${'Index · 1 platform'}
    `('reads an index of $childrenCount as $label', async ({ childrenCount, label }) => {
      createComponent({ handler: withManifest({ childrenCount }) });
      await waitForPromises();

      expect(findKind().text()).toBe(label);
    });

    it('reads a single-platform manifest as an image, with no platform count', async () => {
      createComponent({ handler: withManifest({ mediaType: MOCK_IMAGE_MEDIA_TYPE }) });
      await waitForPromises();

      expect(findKind().text()).toBe('Image');
    });

    it('reads an index of no platforms as an index, not as an image', async () => {
      createComponent({ handler: withManifest({ childrenCount: 0 }) });
      await waitForPromises();

      expect(findKind().text()).toBe('Index · 0 platforms');
    });

    it('labels the digest line by kind, so the two reads are distinguishable', async () => {
      createComponent({
        handler: withManifest({ mediaType: MOCK_IMAGE_MEDIA_TYPE }),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findFullDigest().text()).toBe(`Image digest: ${MANIFEST_DIGEST}`);
    });
  });

  describe('the live region', () => {
    it('announces politely and whole, and is reachable only to a screen reader', async () => {
      createComponent();
      await waitForPromises();

      expect(findAnnouncement().attributes()).toMatchObject({
        'aria-live': 'polite',
        'aria-atomic': 'true',
      });
      expect(findAnnouncement().classes()).toContain('gl-sr-only');
    });
  });

  describe('the breadcrumb trail', () => {
    it('publishes both names once, not an empty pair then the resolved one', async () => {
      createComponent();
      await waitForPromises();

      expect(updateArtifactName.mock.calls).toEqual([['payment-service']]);
      expect(updateManifestName.mock.calls).toEqual([['a1b2c3d4a1b2']]);
    });

    it('publishes nothing while the read is in flight, so a resolved name is not blanked', () => {
      createComponent();

      expect(updateArtifactName).not.toHaveBeenCalled();
      expect(updateManifestName).not.toHaveBeenCalled();
    });

    // The page is reachable from a sibling manifest now, and the component instance is reused
    // across that navigation, so a name read off the payload would lag a route change.
    it('names the manifest the route asks for, not the one still loaded', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ digest: OTHER_DIGEST }) }),
        ),
      });
      await waitForPromises();

      expect(updateManifestName.mock.calls).toEqual([['a1b2c3d4a1b2']]);
    });

    it('publishes an empty image name once the read settles without one', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ image: null })) });
      await waitForPromises();

      expect(updateArtifactName).toHaveBeenCalledWith('');
      expect(updateArtifactName).not.toHaveBeenCalledWith('payment-service');
    });
  });

  describe('when the organization itself does not resolve', () => {
    it('reads it as not found rather than throwing on the way in', async () => {
      const handler = jest.fn().mockResolvedValue({ data: { organization: null } });

      createComponent({ handler });
      await waitForPromises();

      expect(findNotFound().exists()).toBe(true);
    });
  });

  describe('the tag badges', () => {
    const tagged = (tags) =>
      successHandler(mockManifestRepository({ manifest: mockManifestDetails({ tags }) }));

    it('renders them in the order served, without sorting them itself', async () => {
      createComponent({ handler: tagged(['v2', 'latest', 'alpha']), mountFn: mountExtended });
      await waitForPromises();

      expect(findTagNames()).toEqual(['v2', 'latest', 'alpha']);
    });

    it('renders them between the digest and the kind, as the design orders them', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      const order = wrapper
        .findAll(
          '[data-testid="manifest-digest"], [data-testid="manifest-tag"], [data-testid="manifest-kind"]',
        )
        .wrappers.map((node) => node.attributes('data-testid'));

      expect(order).toEqual([
        'manifest-digest',
        'manifest-tag',
        'manifest-tag',
        'manifest-tag',
        'manifest-kind',
      ]);
    });

    it('distinguishes a tag from the kind by variant, not by position alone', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      expect(findTags().at(0).classes()).toContain('badge-info');
      expect(findKind().classes()).toContain('badge-neutral');
    });

    it('names the row for a screen reader, which cannot tell a tag from the kind badge', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      expect(findTagList().attributes('aria-label')).toBe('Tags');
      expect(findTagList().element.tagName).toBe('UL');
      expect(findTags().at(0).element.tagName).toBe('LI');
    });

    it.each`
      case               | tags
      ${'an empty list'} | ${[]}
      ${'a null list'}   | ${null}
    `('renders no row at all for $case', async ({ tags }) => {
      createComponent({ handler: tagged(tags), mountFn: mountExtended });
      await waitForPromises();

      expect(findTags()).toHaveLength(0);
      expect(findTagList().exists()).toBe(false);
    });
  });

  describe('a tag name longer than the header can carry', () => {
    const LONG_TAG = 'a'.repeat(128);

    beforeEach(async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ tags: [LONG_TAG] }) }),
        ),
        mountFn: mountExtended,
      });
      await waitForPromises();
    });

    it('truncates it rather than letting it overflow the row', () => {
      expect(findTagNames()[0]).toHaveLength(32);
      expect(findTagNames()[0]).not.toBe(LONG_TAG);
    });

    it('keeps the whole name reachable in a tooltip', () => {
      expect(getBinding(findTags().at(0).element, 'gl-tooltip').value).toBe(LONG_TAG);
    });

    it('leaves a short name untouched, with no tooltip to dismiss', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ tags: ['latest'] }) }),
        ),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findTagNames()).toEqual(['latest']);
      expect(getBinding(findTags().at(0).element, 'gl-tooltip').value).toBe(null);
    });
  });

  describe('when a manifest carries more tags than the header shows', () => {
    const MANY = Array.from({ length: 12 }, (_, index) => `v${index}`);

    beforeEach(async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ tags: MANY }) }),
        ),
        mountFn: mountExtended,
      });
      await waitForPromises();
    });

    // The contract caps the payload at 1,000 tags, which is a payload bound and not a display
    // one: rendering them all would push the whole page below the fold.
    it('renders only the first five in the header', () => {
      expect(findTagNames()).toEqual(['v0', 'v1', 'v2', 'v3', 'v4']);
    });

    it('counts the rest rather than dropping them silently', () => {
      expect(wrapper.findByTestId('manifest-more-tags').text()).toBe('+7 more');
    });

    it('keeps every remaining tag reachable', () => {
      expect(wrapper.findAllByTestId('manifest-collapsed-tag')).toHaveLength(7);
    });

    it('renders no overflow affordance when every tag fits', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ tags: ['a', 'b'] }) }),
        ),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(wrapper.findByTestId('manifest-more-tags').exists()).toBe(false);
    });
  });

  describe('the sidebar', () => {
    it('hands it the repository, the manifest, and the image the route names', async () => {
      createComponent();
      await waitForPromises();

      expect(findSidebar().props()).toMatchObject({
        repository: expect.objectContaining({ name: mockRepository.name }),
        manifest: expect.objectContaining({ digest: MANIFEST_DIGEST }),
        artifactId: ARTIFACT_ID,
      });
    });

    it.each([
      ['the read is in flight', () => jest.fn().mockReturnValue(new Promise(() => {}))],
      ['the registry cannot be reached', () => jest.fn().mockRejectedValue(new Error('nope'))],
      [
        'the digest names no manifest',
        () => successHandler(mockManifestRepository({ manifest: null })),
      ],
    ])('renders no sidebar when %s', async (_, handler) => {
      createComponent({ handler: handler() });
      await waitForPromises();

      expect(findSidebar().exists()).toBe(false);
    });
  });

  describe('the result announcement', () => {
    it('names the tab, the manifest and the image it belongs to', async () => {
      createComponent();
      await waitForPromises();

      expect(findAnnouncement().text()).toBe(
        'Overview tab for manifest a1b2c3d4a1b2 of payment-service.',
      );
    });

    it('names the manifest alone when the image did not resolve', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ image: null })) });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe('Overview tab for manifest a1b2c3d4a1b2.');
    });

    it('names the tab the query asks for, so a switch is announced', async () => {
      createComponent({ query: { tab: 'referrers' } });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe(
        'Referrers tab for manifest a1b2c3d4a1b2 of payment-service.',
      );
    });
  });

  describe('the tabs', () => {
    it('renders Overview and Referrers only', async () => {
      createComponent();
      await waitForPromises();

      expect(findTabTitles()).toEqual(['Overview', 'Referrers']);
    });

    it('renders no tabs while the read is still in flight', async () => {
      createComponent({ handler: jest.fn(() => new Promise(() => {})) });
      await waitForPromises();

      expect(findTabs().exists()).toBe(false);
    });

    it.each([
      ['the registry cannot be reached', () => failingHandler()],
      [
        'the digest names no manifest',
        () => successHandler(mockManifestRepository({ manifest: null })),
      ],
    ])('renders no tabs when %s', async (_, handler) => {
      createComponent({ handler: handler() });
      await waitForPromises();

      expect(findTabs().exists()).toBe(false);
    });

    it('counts the referrers on the Referrers tab alone', async () => {
      createComponent();
      await waitForPromises();

      expect(findAllTabs().wrappers.map((tab) => tab.props('tabCount'))).toEqual([null, 2]);
    });
  });

  describe('the overview panel', () => {
    const mountTab = async (query = {}) => {
      createComponent({ query, mountFn: mountExtended });
      await waitForPromises();
    };

    it('mounts the overview on the Overview tab, which is the default', async () => {
      await mountTab();

      expect(findOverview().props()).toMatchObject({
        format: 'DOCKER',
        name: mockRepository.name,
        imageName: 'payment-service',
      });
      expect(findOverview().props('manifest').digest).toBe(MANIFEST_DIGEST);
    });

    it('mounts no overview while the Referrers tab is the active one', async () => {
      await mountTab({ tab: 'referrers' });

      expect(findOverview().exists()).toBe(false);
    });

    it('mounts no overview when the digest names no manifest', async () => {
      createComponent({
        handler: successHandler(mockManifestRepository({ manifest: null })),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findOverview().exists()).toBe(false);
    });

    it('hands the overview an empty name when the image did not resolve', async () => {
      createComponent({
        handler: successHandler(mockManifestRepository({ image: null })),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findOverview().props('imageName')).toBe('');
    });
  });

  describe('the referrers panel', () => {
    const mountTab = async (query) => {
      createComponent({ query, mountFn: mountExtended });
      await waitForPromises();
    };

    it('mounts the referrers section when the Referrers tab is the active one', async () => {
      await mountTab({ tab: 'referrers' });

      expect(findReferrersSection().props()).toStrictEqual({
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
      });
    });

    it.each([{}, { tab: 'overview' }, { tab: 'nonsense' }])(
      'asks Artifact Registry for no referrers while the query reads %p',
      async (query) => {
        await mountTab(query);

        expect(findReferrersSection().exists()).toBe(false);
        expect(referrersRequest).not.toHaveBeenCalled();
      },
    );

    it('issues the referrers read once the Referrers tab is selected', async () => {
      await mountTab({ tab: 'referrers' });

      expect(referrersRequest).toHaveBeenCalledTimes(1);
    });

    it('hands the section the digest the read resolved, not the one in the route', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ digest: OTHER_DIGEST }) }),
        ),
        query: { tab: 'referrers' },
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findReferrersSection().props('digest')).toBe(OTHER_DIGEST);
    });

    it('mounts no referrers section when the digest names no manifest', async () => {
      createComponent({
        handler: successHandler(mockManifestRepository({ manifest: null })),
        query: { tab: 'referrers' },
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findReferrersSection().exists()).toBe(false);
    });
  });

  describe('the referrers count as it reaches the page', () => {
    const withCount = (referrersCount) =>
      successHandler(mockManifestRepository({ manifest: mockManifestDetails({ referrersCount }) }));

    const mountWith = async (handler) => {
      createComponent({ handler, mountFn: mountExtended });
      await waitForPromises();
    };

    it('renders the count in a badge, hidden from a screen reader', async () => {
      await mountWith(successHandler());

      expect(findCountBadge().text()).toBe('2');
      expect(findCountBadge().attributes('aria-hidden')).toBe('true');
    });

    it('names the count for a screen reader instead, since the badge is hidden', async () => {
      await mountWith(successHandler());

      expect(findCountSrText().textContent).toBe('2 referrers');
    });

    it('names a single referrer in the singular', async () => {
      await mountWith(withCount(1));

      expect(findCountBadge().text()).toBe('1');
      expect(findCountSrText().textContent).toBe('1 referrer');
    });

    // The count is exact by contract, and a remote repository serves zero, so a zero is a
    // reading rather than an absence.
    it('renders an exact zero rather than hiding the badge', async () => {
      await mountWith(withCount(0));

      expect(findCountBadge().text()).toBe('0');
      expect(findCountSrText().textContent).toBe('0 referrers');
    });

    it('renders no badge at all when the count did not resolve', async () => {
      await mountWith(withCount(null));

      expect(findCountBadge().exists()).toBe(false);
      expect(findTabTexts()).toEqual(['Overview', 'Referrers']);
    });
  });

  describe('which tab the query parameter selects', () => {
    it.each`
      query                   | index | outcome
      ${{}}                   | ${0}  | ${'an absent value lands on Overview'}
      ${{ tab: 'overview' }}  | ${0}  | ${'overview selects Overview'}
      ${{ tab: 'referrers' }} | ${1}  | ${'referrers selects Referrers'}
      ${{ tab: 'manifest' }}  | ${0}  | ${'an unrecognized value lands on Overview'}
      ${{ tab: '' }}          | ${0}  | ${'an empty value lands on Overview'}
    `('$outcome', async ({ query, index }) => {
      createComponent({ query });
      await waitForPromises();

      expect(findTabs().props('value')).toBe(index);
    });
  });

  describe('when a tab is selected', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('records the tab in the query rather than in component state', () => {
      findTabs().vm.$emit('input', 1);

      expect(push).toHaveBeenCalledWith({
        path: MANIFEST_PATH,
        query: { tab: 'referrers' },
      });
    });

    it('does not push when the tab is already active', () => {
      findTabs().vm.$emit('input', 0);

      expect(push).not.toHaveBeenCalled();
    });
  });

  describe('when a tab is selected with something else already in the query', () => {
    it('keeps the rest of the query, so another page-level selection survives', async () => {
      createComponent({ query: { sort: 'created_desc' } });
      await waitForPromises();

      findTabs().vm.$emit('input', 1);

      expect(push).toHaveBeenCalledWith({
        path: MANIFEST_PATH,
        query: { sort: 'created_desc', tab: 'referrers' },
      });
    });
  });
});
