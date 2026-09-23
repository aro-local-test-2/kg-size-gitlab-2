import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import SnippetCodeBlock from 'ee/packages_and_registries/artifact_registry/components/snippet_code_block.vue';
import ManifestOverview from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_overview.vue';
import {
  CLIENT_BASE_URL,
  MANIFEST_DIGEST,
  SLUG,
  mockManifestDetails,
  mockRepository,
} from '../../../mock_data';

const IMAGE_NAME = 'payment-service';

// Docker and OCI share the `container` path segment.
const IMAGE_URL = `artifact-registry.example.com/${SLUG}/container/${mockRepository.name}`;

describe('ArtifactRegistryManifestOverview', () => {
  let wrapper;

  const createComponent = ({
    format = 'DOCKER',
    manifest = mockManifestDetails(),
    ...props
  } = {}) => {
    wrapper = shallowMountExtended(ManifestOverview, {
      propsData: {
        format,
        name: mockRepository.name,
        imageName: IMAGE_NAME,
        manifest,
        ...props,
      },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
    });
  };

  const findBlocks = () => wrapper.findAllComponents(SnippetCodeBlock);
  const findSnippets = () => findBlocks().wrappers.map((block) => block.props('snippet'));
  const findLabels = () =>
    wrapper.findAllComponents(CrudComponent).wrappers.map((panel) => panel.props('title'));

  describe('a tagged manifest', () => {
    beforeEach(() => createComponent());

    it('offers pull by tag and pull by digest, in that order', () => {
      expect(findLabels()).toEqual(['Pull by tag', 'Pull by digest']);
    });

    it('addresses the image under the repository the manifest belongs to', () => {
      expect(findSnippets()).toEqual([
        `docker pull ${IMAGE_URL}/${IMAGE_NAME}:latest`,
        `docker pull ${IMAGE_URL}/${IMAGE_NAME}@${MANIFEST_DIGEST}`,
      ]);
    });

    it('gives each block its own copy label', () => {
      expect(findBlocks().wrappers.map((block) => block.props('copyText'))).toEqual([
        'Copy the pull-by-tag command',
        'Copy the pull-by-digest command',
      ]);
    });
  });

  describe('a manifest carrying several tags', () => {
    beforeEach(() => createComponent({ manifest: mockManifestDetails({ tags: ['rc1', 'v1'] }) }));

    it('names the first tag as served, rather than picking one of its own', () => {
      expect(findSnippets()[0]).toContain(':rc1');
    });
  });

  describe('an untagged manifest', () => {
    beforeEach(() => createComponent({ manifest: mockManifestDetails({ tags: [] }) }));

    it('offers pull by digest alone', () => {
      expect(findLabels()).toEqual(['Pull by digest']);
    });

    it('does not pull a literal tag placeholder', () => {
      expect(findSnippets()[0]).not.toContain(':tag');
    });
  });

  describe('when no pull command can be built', () => {
    const findUnavailable = () => wrapper.findByTestId('pull-commands-unavailable');

    it.each`
      case                                   | props
      ${'the image did not resolve'}         | ${{ imageName: '' }}
      ${'the manifest carries no digest'}    | ${{ manifest: { ...mockManifestDetails(), digest: null } }}
      ${'the digest is not a sha256'}        | ${{ manifest: { ...mockManifestDetails(), digest: 'sha512:abc' } }}
      ${'a tag carries an unsafe character'} | ${{ manifest: { ...mockManifestDetails(), tags: ['v1;id'] } }}
    `('says so rather than offering a command when $case', ({ props }) => {
      createComponent(props);

      expect(findSnippets()).toEqual([]);
      expect(findUnavailable().text()).toBe('Pull commands are unavailable for this manifest.');
    });
  });

  // Spread, not the fixture call: `tags: undefined` would take the fixture's own default.
  describe.each([null, undefined])('when tags are %s', (tags) => {
    beforeEach(() => createComponent({ manifest: { ...mockManifestDetails(), tags } }));

    it('offers pull by digest alone', () => {
      expect(findLabels()).toEqual(['Pull by digest']);
    });
  });

  describe.each`
    format      | client
    ${'DOCKER'} | ${'docker'}
    ${'OCI'}    | ${'oras'}
  `('a $format manifest', ({ format, client }) => {
    beforeEach(() => createComponent({ format }));

    it(`pulls with ${client}`, () => {
      expect(findSnippets()).toEqual([
        expect.stringMatching(new RegExp(`^${client} pull `)),
        expect.stringMatching(new RegExp(`^${client} pull `)),
      ]);
    });
  });

  it('renders the pull commands alone, with no registry sign-in block', () => {
    createComponent();

    expect(findBlocks()).toHaveLength(2);
    expect(findSnippets().join('\n')).not.toContain('glab artifact-registry login');
  });
});
