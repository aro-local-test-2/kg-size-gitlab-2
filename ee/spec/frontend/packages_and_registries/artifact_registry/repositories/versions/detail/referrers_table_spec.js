import { RouterLinkStub } from '@vue/test-utils';
import { GlLoadingIcon, GlTable, GlTruncate } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import ReferrersTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/referrers_table.vue';
import {
  ARTIFACT_ID_FOR,
  MANIFEST_DIGEST,
  MOCK_IMAGE_MEDIA_TYPE,
  MOCK_SIGNATURE_ARTIFACT_TYPE,
  mockManifestReferrer,
  mockRepository,
} from '../../../mock_data';

const ARTIFACT_ID = ARTIFACT_ID_FOR.DOCKER;

const referrer = mockManifestReferrer();

describe('ArtifactRegistryReferrersTable', () => {
  let wrapper;

  const createComponent = ({ referrers = [referrer], ...props } = {}) => {
    wrapper = mountExtended(ReferrersTable, {
      propsData: {
        referrers,
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        subjectDigest: MANIFEST_DIGEST,
        ...props,
      },
      stubs: { RouterLink: RouterLinkStub },
    });
  };

  const findTable = () => wrapper.findComponent(GlTable);
  const findHeaders = () => wrapper.findAll('th').wrappers.map((th) => th.text());
  const findCells = (testId) => wrapper.findAllByTestId(testId).wrappers.map((cell) => cell.text());
  const findLinks = () => wrapper.findAllComponents(RouterLinkStub);
  const findKinds = () => findCells('referrer-kind');
  // Read off the component: the rendered text carries GlTruncate's zero-width marks.
  const findTypeLabels = () =>
    wrapper.findAllComponents(GlTruncate).wrappers.map((label) => label.props('text'));
  const findPublished = () => wrapper.findAllComponents(TimeAgoTooltip);

  it('renders a column for the digest, the artifact type, and the published date', () => {
    createComponent();

    expect(findHeaders()).toEqual(['Digest', 'Artifact type', 'Published']);
  });

  it('renders no actions column, since every row action is a write', () => {
    createComponent();

    expect(findHeaders()).not.toContain('Actions');
  });

  describe('the digest cell', () => {
    beforeEach(() => createComponent());

    it('shortens the digest', () => {
      expect(findLinks().at(0).text()).toBe('cccccccccccc');
    });

    it('links it to that manifest own page, under the same repository and image', () => {
      expect(findLinks().at(0).props('to')).toEqual({
        name: 'manifest_detail',
        params: {
          id: mockRepository.name,
          artifactId: ARTIFACT_ID,
          digest: referrer.digest,
        },
      });
    });

    it('names the link, since a shortened digest does not describe itself', () => {
      expect(findLinks().at(0).attributes('aria-label')).toBe('Manifest cccccccccccc');
    });

    it('offers no copy button, since the row links to the digest it shortens', () => {
      expect(wrapper.findByTestId('referrer-digest').text()).toBe('cccccccccccc');
    });
  });

  describe('the artifact type cell', () => {
    it('renders the declared artifact type', () => {
      createComponent();

      expect(findTypeLabels()).toEqual([MOCK_SIGNATURE_ARTIFACT_TYPE]);
    });

    it.each`
      artifactType                                     | badge
      ${MOCK_SIGNATURE_ARTIFACT_TYPE}                  | ${'Signature'}
      ${'application/spdx+json'}                       | ${'SBOM attestation'}
      ${'application/vnd.in-toto.provenance+json'}     | ${'SLSA attestation'}
      ${'application/vnd.example.attestation.v1+json'} | ${'Referrer'}
    `('badges $artifactType as $badge', ({ artifactType, badge }) => {
      createComponent({ referrers: [mockManifestReferrer({ artifactType })] });

      expect(findKinds()).toEqual([badge]);
    });

    it('falls back to the media type when the referrer declares no artifact type', () => {
      createComponent({ referrers: [mockManifestReferrer({ artifactType: null })] });

      expect(findTypeLabels()).toEqual([MOCK_IMAGE_MEDIA_TYPE]);
      expect(findKinds()).toEqual(['Referrer']);
    });

    it('still reads a row as a referrer when it arrives without its own subject digest', () => {
      createComponent({ referrers: [mockManifestReferrer({ subjectDigest: null })] });

      expect(findKinds()).toEqual(['Signature']);
    });
  });

  describe('the published cell', () => {
    it('renders the push time', () => {
      createComponent();

      expect(findPublished().at(0).props('time')).toBe(referrer.createdAt);
    });

    it.each([null, undefined])(
      'renders nothing rather than a placeholder when the push time is %s',
      (createdAt) => {
        createComponent({ referrers: [mockManifestReferrer({ createdAt })] });

        expect(findPublished()).toHaveLength(0);
      },
    );
  });

  it('renders a row per referrer', () => {
    createComponent({
      referrers: [mockManifestReferrer({ marker: 'a' }), mockManifestReferrer({ marker: 'b' })],
    });

    expect(findCells('referrer-digest')).toHaveLength(2);
  });

  describe('while a re-read is in flight', () => {
    beforeEach(() => createComponent({ isLoading: true }));

    it('marks the table busy', () => {
      expect(findTable().attributes('aria-busy')).toBe('true');
    });

    it('stands a spinner over the outgoing rows, so they do not read as current', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    });
  });

  describe('a manifest nothing refers to', () => {
    beforeEach(() => createComponent({ referrers: [] }));

    it('says so rather than rendering an empty table body', () => {
      expect(wrapper.text()).toContain('Nothing refers to this manifest.');
    });

    it('renders no rows', () => {
      expect(findCells('referrer-digest')).toEqual([]);
    });
  });

  it('does not mark the table busy once the read has settled', () => {
    createComponent();

    expect(findTable().attributes('aria-busy')).toBe('false');
  });
});
