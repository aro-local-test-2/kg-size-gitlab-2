import { RouterLinkStub } from '@vue/test-utils';
import { GlBadge, GlLink, GlSprintf } from '@gitlab/ui';
import mavenVersionFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version.query.graphql.json';
import npmVersionFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version.npm.query.graphql.json';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import VersionSidebar from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/version_sidebar.vue';

const mavenRepository = mavenVersionFixture.data.organization.artifactRegistryRepository;
const npmRepository = npmVersionFixture.data.organization.artifactRegistryRepository;
const attributedVersion = mavenRepository.version;
const unattributedVersion = npmRepository.version;

const SHORT_SHA = 'f19ac02a';

describe('ArtifactRegistryVersionSidebar', () => {
  let wrapper;

  const createComponent = ({ repository = {}, version = attributedVersion } = {}) => {
    wrapper = shallowMountExtended(VersionSidebar, {
      propsData: {
        repository: { name: mavenRepository.name, kind: mavenRepository.kind, ...repository },
        version,
      },
      stubs: {
        GlSprintf,
        RouterLink: RouterLinkStub,
      },
    });
  };

  const findRepositoryLink = () => wrapper.findComponent(RouterLinkStub);
  const findKindBadge = () => wrapper.findComponent(GlBadge);
  const findRepositorySection = () => wrapper.findByTestId('version-repository');
  const findSize = () => wrapper.findByTestId('version-size');
  const findPublished = () => wrapper.findByTestId('version-published');
  const findUnknownPublished = () => wrapper.findByTestId('version-published-unknown');
  const findSourceSection = () => wrapper.findByTestId('version-source');
  const findCommit = () => wrapper.findByTestId('version-commit');
  const findPublishedBy = () => wrapper.findByTestId('version-published-by');
  const findAttribution = () => wrapper.findByTestId('version-attribution');
  const findUnknownSource = () => wrapper.findByTestId('version-source-unknown');

  describe('the repository section', () => {
    it('names the section with an h2, so the heading order does not skip a level', () => {
      createComponent();

      expect(findRepositorySection().find('h2').text()).toBe('Repository');
    });

    it('links the repository name to the repository it names', () => {
      createComponent();

      expect(findRepositoryLink().text()).toBe('maven-releases');
      expect(findRepositoryLink().props('to')).toEqual({
        name: 'repository_detail',
        params: { id: 'maven-releases' },
      });
    });

    it('names the repository kind', () => {
      createComponent({ repository: { kind: 'REMOTE' } });

      expect(findKindBadge().text()).toBe('Remote');
    });
  });

  describe('the size row', () => {
    it('labels the version size', () => {
      createComponent({ version: unattributedVersion });

      expect(findSize().text()).toMatchInterpolatedText('512.00 KiB Size');
    });

    it('renders a zero as a zero on a hosted repository', () => {
      createComponent({ version: { ...unattributedVersion, sizeBytes: '0' } });

      expect(findSize().text()).toMatchInterpolatedText('0 B Size');
    });

    it('hides when the version reports no size', () => {
      createComponent({ version: { ...attributedVersion, sizeBytes: null } });

      expect(findSize().exists()).toBe(false);
    });

    it('hides rather than rendering NaN when the size is not a number', () => {
      createComponent({ version: { ...unattributedVersion, sizeBytes: 'not-a-number' } });

      expect(findSize().exists()).toBe(false);
    });

    it('hides on a remote repository', () => {
      createComponent({ repository: { kind: 'REMOTE' }, version: unattributedVersion });

      expect(findSize().exists()).toBe(false);
    });
  });

  describe('the published section', () => {
    it('names the section with an h2, so the heading order does not skip a level', () => {
      createComponent();

      expect(findPublished().find('h2').text()).toBe('Published');
    });

    it('renders the date the version was published', () => {
      createComponent({ version: unattributedVersion });

      expect(findPublished().text()).toMatchInterpolatedText('Published Jun 10, 2026');
    });

    it('renders unknown, not an epoch date, when the version carries no timestamp', () => {
      createComponent({ version: { ...attributedVersion, createdAt: null } });

      expect(findUnknownPublished().text()).toBe('Unknown');
    });
  });

  describe('the source section', () => {
    it('names the section with an h2, so the heading order does not skip a level', () => {
      createComponent();

      expect(findSourceSection().find('h2').text()).toBe('Source');
    });

    const { project, createdBy } = attributedVersion;

    it('links the short commit sha to its commit', () => {
      createComponent();

      expect(findCommit().text()).toBe(SHORT_SHA);
      expect(findCommit().attributes('href')).toBe(
        `/${project.fullPath}/-/commit/f19ac02a8d3b41e57c9f0a4d2b8e6135ac97d40e`,
      );
    });

    it('names the project and the publisher', () => {
      createComponent();

      expect(findAttribution().text()).toBe(`Published to ${project.name} by ${createdBy.name}`);
      expect(findAttribution().findComponent(GlLink).attributes('href')).toBe(project.webPath);
    });

    it('leaves the sha unlinked when the project does not resolve', () => {
      createComponent({ version: { ...attributedVersion, project: null } });

      expect(findCommit().text()).toBe(SHORT_SHA);
      expect(findCommit().attributes('href')).toBeUndefined();
      expect(findAttribution().text()).toBe(`Published by ${createdBy.name}`);
    });

    it('names the project alone when there is no publisher', () => {
      createComponent({ version: { ...attributedVersion, createdBy: null } });

      expect(findAttribution().text()).toBe(`Published to ${project.name}`);
    });

    it('renders the commit alone when neither the project nor the publisher resolves', () => {
      createComponent({ version: { ...attributedVersion, project: null, createdBy: null } });

      expect(findCommit().text()).toBe(SHORT_SHA);
      expect(findCommit().attributes('href')).toBeUndefined();
      expect(findAttribution().exists()).toBe(false);
      expect(findUnknownSource().exists()).toBe(false);
    });

    describe('a version published without a commit', () => {
      it('names its author, not a commit, on the first line and renders nothing beneath it', () => {
        createComponent({ version: { ...attributedVersion, gitCommitSha: null, project: null } });

        expect(findCommit().exists()).toBe(false);
        expect(findPublishedBy().text()).toBe(`Published by ${createdBy.name}`);
        expect(findAttribution().exists()).toBe(false);
      });

      it('names the project beneath the publisher, without repeating the author', () => {
        createComponent({ version: { ...attributedVersion, gitCommitSha: null } });

        expect(findPublishedBy().text()).toBe(`Published by ${createdBy.name}`);
        expect(findAttribution().text()).toBe(`Published to ${project.name}`);
      });

      it('names the project alone when there is no publisher either', () => {
        createComponent({
          version: { ...attributedVersion, gitCommitSha: null, createdBy: null },
        });

        expect(findPublishedBy().text()).toBe('Published');
        expect(findAttribution().text()).toBe(`Published to ${project.name}`);
      });
    });

    it('renders unknown, not a publisher, for a version carrying no attribution', () => {
      createComponent({ version: unattributedVersion });

      expect(findUnknownSource().text()).toBe('Unknown');
      expect(findCommit().exists()).toBe(false);
      expect(findPublishedBy().exists()).toBe(false);
      expect(findAttribution().exists()).toBe(false);
    });
  });
});
