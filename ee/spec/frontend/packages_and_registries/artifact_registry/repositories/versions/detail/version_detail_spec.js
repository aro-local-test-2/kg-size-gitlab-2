import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { RouterLinkStub } from '@vue/test-utils';
import {
  GlAlert,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlKeysetPagination,
  GlSkeletonLoader,
  GlTab,
  GlTabs,
} from '@gitlab/ui';
import mavenVersionFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version.query.graphql.json';
import npmVersionFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version.npm.query.graphql.json';
import mavenFilesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version_files.query.graphql.json';
import npmFilesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version_files.npm.query.graphql.json';
import { createAlert } from '~/alert';
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
import NotFound from 'ee/packages_and_registries/artifact_registry/components/not_found.vue';
import FormatLogo from 'ee/packages_and_registries/artifact_registry/repositories/components/format_logo.vue';
import VersionSidebar from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/version_sidebar.vue';
import VersionDetail from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/version_detail.vue';
import VersionOverview from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/version_overview.vue';
import getVersionQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_version.query.graphql';
import getVersionFilesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_version_files.query.graphql';
import deleteVersionMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_version.mutation.graphql';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';
import FilesEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/files_empty_state.vue';
import FilesSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/files_section.vue';
import FilesTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/files_table.vue';
import {
  CLIENT_BASE_URL,
  FIRST_PAGE_END_CURSOR,
  SECOND_PAGE_START_CURSOR,
  ORGANIZATION_GID,
  SLUG,
  mockRepositoryResponse,
  mockDeleteVersionResponse,
} from '../../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

const VERSION_FIXTURE = { MAVEN: mavenVersionFixture, NPM: npmVersionFixture };
const FILES_FIXTURE = { MAVEN: mavenFilesFixture, NPM: npmFilesFixture };

const fixtureRepository = (fixture) => fixture.data.organization.artifactRegistryRepository;

const MAVEN_FILES = fixtureRepository(mavenFilesFixture).version.files;

const MAVEN_VERSION = fixtureRepository(mavenVersionFixture).version;

const versionRepository = ({ format = 'MAVEN', ...overrides } = {}) => ({
  ...fixtureRepository(VERSION_FIXTURE[format]),
  ...overrides,
});

const filePage = ({ nodes = MAVEN_FILES.nodes, ...pageInfo } = {}) => ({
  ...MAVEN_FILES,
  nodes,
  pageInfo: { ...MAVEN_FILES.pageInfo, ...pageInfo },
});

const filesRepository = ({ format = 'MAVEN', files, ...overrides } = {}) => {
  const repository = fixtureRepository(FILES_FIXTURE[format]);

  return {
    ...repository,
    version: files ? { ...repository.version, files } : repository.version,
    ...overrides,
  };
};

const routeParams = (format) => {
  const { name, package: artifact, version } = fixtureRepository(VERSION_FIXTURE[format]);

  return { id: name, artifactId: artifact.id, versionId: version.id };
};

const versionPath = (format) => {
  const { id, artifactId, versionId } = routeParams(format);

  return `/${id}/${artifactId}/versions/${versionId}`;
};

const VERSION_PATH = versionPath('MAVEN');

const successHandler = (repository = versionRepository()) =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(repository));

const filesHandler = (repository = filesRepository()) =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(repository));

describe('ArtifactRegistryVersionDetail', () => {
  let wrapper;
  let mockApollo;

  const updateArtifactName = jest.fn();
  const updateVersionName = jest.fn();

  const push = jest.fn();
  const mockToast = { show: jest.fn() };

  const createComponent = ({
    format = 'MAVEN',
    handler = successHandler(versionRepository({ format })),
    files = filesHandler(filesRepository({ format })),
    deleteHandler = jest.fn().mockResolvedValue(mockDeleteVersionResponse()),
    query = {},
    mountFn = shallowMountExtended,
  } = {}) => {
    mockApollo = createMockApollo(
      [
        [getVersionQuery, handler],
        [getVersionFilesQuery, files],
        [deleteVersionMutation, deleteHandler],
      ],
      {},
      {
        possibleTypes,
        typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
      },
    );

    wrapper = mountFn(VersionDetail, {
      apolloProvider: mockApollo,
      provide: {
        breadCrumbState: { updateArtifactName, updateVersionName },
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
      },
      mocks: {
        $route: {
          path: versionPath(format),
          params: routeParams(format),
          query,
        },
        $router: { push },
        $toast: mockToast,
      },
      stubs: { BaseLayout, DetailLayout, PageHeading, RouterLink: RouterLinkStub },
    });
  };

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findNotFound = () => wrapper.findComponent(NotFound);
  const findFormatLogo = () => wrapper.findComponent(FormatLogo);
  const findHeading = () => wrapper.findByTestId('page-heading');
  const findVersionName = () => wrapper.findByTestId('version-name');
  const findArtifactName = () => wrapper.findByTestId('artifact-name');
  const findFormatName = () => wrapper.findByTestId('version-format-name');
  const findAnnouncement = () => wrapper.findByTestId('version-announcement');
  const findSidebar = () => wrapper.findComponent(VersionSidebar);
  const findSidebarRegion = () => wrapper.findByRole('region', { name: 'Sidebar' });

  afterEach(() => {
    mockApollo = null;
  });

  describe('the query it issues', () => {
    it('names the repository, the artifact, and the version the route addresses', async () => {
      const handler = successHandler();
      createComponent({ handler });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        organizationId: ORGANIZATION_GID,
        name: 'maven-releases',
        artifactId: 'e5f6a7b8-0000-0000-0000-000000000000',
        versionId: 'b8c9d0e1-0000-0000-0000-000000000000',
      });
    });

    it('issues the version read once and no files read when it lands on Overview', async () => {
      const handler = successHandler();
      const files = filesHandler();
      createComponent({ handler, files });
      await waitForPromises();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(files).not.toHaveBeenCalled();
    });
  });

  describe('while the read is in flight', () => {
    beforeEach(() => createComponent({ handler: jest.fn(() => new Promise(() => {})) }));

    it('renders a loading affordance', () => {
      expect(findSkeleton().exists()).toBe(true);
    });

    it('renders no sidebar while loading', () => {
      expect(findSidebar().exists()).toBe(false);
    });

    it('renders neither the header nor an outcome state', () => {
      expect(findHeading().exists()).toBe(false);
      expect(findVersionName().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
    });

    it('announces that the read is in flight', () => {
      expect(findAnnouncement().text()).toBe('Loading version details.');
    });
  });

  describe('when the version loads', () => {
    it.each`
      format     | formatName | artifactName
      ${'MAVEN'} | ${'Maven'} | ${'com.example.tools:payment-core'}
      ${'NPM'}   | ${'npm'}   | ${'@acme/ui-components'}
    `(
      'names the $format version, its format, and its artifact in the heading',
      async ({ format, formatName, artifactName }) => {
        createComponent({ format });
        await waitForPromises();

        expect(findVersionName().text()).toBe('3.2.1');
        expect(findFormatLogo().props('format')).toBe(format);
        expect(findFormatName().text()).toBe(formatName);
        expect(findArtifactName().text()).toBe(artifactName);
      },
    );
  });

  describe('when the Maven version loads', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders no loading, error, or not-found affordance', () => {
      expect(findSkeleton().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
    });

    it('announces the active tab, the version, and the artifact it belongs to', () => {
      expect(findAnnouncement().text()).toBe(
        'Overview tab for version 3.2.1 of com.example.tools:payment-core.',
      );
    });

    it('publishes both the artifact name and the version into the breadcrumb slots', () => {
      expect(updateArtifactName).toHaveBeenCalledWith('com.example.tools:payment-core');
      expect(updateVersionName).toHaveBeenCalledWith('3.2.1');
    });

    it('renders the sidebar inside the layout sidebar region', () => {
      expect(findSidebarRegion().element.contains(findSidebar().element)).toBe(true);
    });

    it('passes the resolved version to the sidebar', () => {
      expect(findSidebar().props('version')).toEqual(versionRepository().version);
    });

    it('passes the repository the version belongs to', () => {
      expect(findSidebar().props('repository')).toMatchObject({
        name: 'maven-releases',
        kind: 'HOSTED',
      });
    });
  });

  describe('when a refetch fails after the version loaded', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(mockRepositoryResponse(versionRepository()))
          .mockRejectedValue(new Error('Unavailable')),
      });
      await waitForPromises();

      wrapper.vm.$apollo.queries.repository.refetch().catch(() => {});
      await waitForPromises();
    });

    it('renders the alert without the stale header, sidebar, or actions', () => {
      expect(findAlert().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findSidebar().exists()).toBe(false);
      expect(wrapper.findComponent(GlDisclosureDropdown).exists()).toBe(false);
    });
  });

  describe('when the read fails', () => {
    beforeEach(async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('Unavailable')) });
      await waitForPromises();
    });

    it('renders a service-unavailable alert that cannot be dismissed', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findAlert().props('dismissible')).toBe(false);
    });

    it('renders no header and no not-found state', () => {
      expect(findHeading().exists()).toBe(false);
      expect(findVersionName().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
    });

    it('leaves the live region silent, because the alert announces the failure itself', () => {
      expect(findAlert().props('variant')).toBe('danger');
      expect(findAnnouncement().text()).toBe('');
    });

    it('renders no sidebar, because there is no version to describe', () => {
      expect(findSidebar().exists()).toBe(false);
    });
  });

  describe.each`
    outcome                              | repository
    ${'the repository does not resolve'} | ${null}
    ${'the version does not resolve'}    | ${versionRepository({ version: null })}
  `('when $outcome', ({ repository }) => {
    beforeEach(async () => {
      createComponent({ handler: successHandler(repository) });
      await waitForPromises();
    });

    it('renders the not-found state', () => {
      expect(findNotFound().exists()).toBe(true);
    });

    it('renders no header and no alert', () => {
      expect(findHeading().exists()).toBe(false);
      expect(findVersionName().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });

    it('announces the not-found outcome', () => {
      expect(findAnnouncement().text()).toBe('Page not found');
    });

    it('renders no sidebar, because there is no version to describe', () => {
      expect(findSidebar().exists()).toBe(false);
    });

    describe('with the Files tab selected and a files read that comes back empty', () => {
      beforeEach(async () => {
        createComponent({
          handler: successHandler(repository),
          files: filesHandler(filesRepository({ files: filePage({ nodes: [] }) })),
          query: { tab: 'files' },
        });
        await waitForPromises();
      });

      it('announces the not-found outcome, rather than an empty Files tab', () => {
        expect(findAnnouncement().text()).toBe('Page not found');
      });
    });
  });

  describe('the tab set', () => {
    const findTabs = () => wrapper.findComponent(GlTabs);
    const findTabTitles = () =>
      wrapper.findAllComponents(GlTab).wrappers.map((tab) => tab.attributes('title'));

    const createWithFormat = async (format, query = {}) => {
      createComponent({ format, query });
      await waitForPromises();
    };

    it('renders the Maven tabs', async () => {
      await createWithFormat('MAVEN');

      expect(findTabTitles()).toEqual(['Overview', 'Files']);
    });

    it('renders the npm tabs', async () => {
      await createWithFormat('NPM');

      expect(findTabTitles()).toEqual(['Overview', 'File']);
    });

    it('renders no tabs until the version resolves', async () => {
      createComponent({ handler: jest.fn(() => new Promise(() => {})) });
      await waitForPromises();

      expect(findTabs().exists()).toBe(false);
    });

    describe('the tab the route selects', () => {
      it.each`
        query                  | index | outcome
        ${{}}                  | ${0}  | ${'an absent value lands on Overview'}
        ${{ tab: 'overview' }} | ${0}  | ${'overview selects Overview'}
        ${{ tab: 'files' }}    | ${1}  | ${'files selects Files'}
        ${{ tab: 'nonsense' }} | ${0}  | ${'an unrecognized value lands on Overview'}
      `('$outcome', async ({ query, index }) => {
        await createWithFormat('MAVEN', query);

        expect(findTabs().props('value')).toBe(index);
      });

      it('selects the npm files tab, which the format names in the singular', async () => {
        await createWithFormat('NPM', { tab: 'files' });

        expect(findTabs().props('value')).toBe(1);
      });
    });

    describe('the Files tab', () => {
      const findFilesSection = () => wrapper.findComponent(FilesSection);
      const findFilesCount = () => wrapper.findByTestId('tab-counter-badge');
      const findCountSrText = () => findFilesCount().element.nextElementSibling;
      const findFileNames = () =>
        findFilesSection()
          .props('files')
          .map(({ fileName }) => fileName);

      it('issues no files read while Overview is the tab on screen', async () => {
        const files = filesHandler();
        createComponent({ files, mountFn: mountExtended });
        await waitForPromises();

        expect(files).not.toHaveBeenCalled();
        expect(findFilesSection().exists()).toBe(false);
      });

      it('issues the version read and the files read once each when it lands on the tab', async () => {
        const handler = successHandler();
        const files = filesHandler();
        createComponent({ handler, files, query: { tab: 'files' } });
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(files).toHaveBeenCalledTimes(1);
      });

      it('reads the files the version holds once the tab is on screen', async () => {
        const files = filesHandler();
        createComponent({ files, query: { tab: 'files' } });
        await waitForPromises();

        expect(files).toHaveBeenCalledWith({
          organizationId: ORGANIZATION_GID,
          name: 'maven-releases',
          artifactId: 'e5f6a7b8-0000-0000-0000-000000000000',
          versionId: 'b8c9d0e1-0000-0000-0000-000000000000',
          first: 20,
        });
        expect(findFileNames()).toEqual(MAVEN_FILES.nodes.map(({ fileName }) => fileName));
      });

      it('renders the one file an npm version holds', async () => {
        createComponent({ format: 'NPM', query: { tab: 'files' } });
        await waitForPromises();

        expect(findFileNames()).toEqual(
          fixtureRepository(npmFilesFixture).version.files.nodes.map(({ fileName }) => fileName),
        );
      });

      it('carries the statistics count on the Maven tab, naming the unit beside it', async () => {
        createComponent({ mountFn: mountExtended });
        await waitForPromises();

        expect(findFilesCount().text()).toBe('2');
        expect(findFilesCount().attributes('aria-hidden')).toBe('true');
        expect(findCountSrText()).toHaveClass('gl-sr-only');
        expect(findCountSrText().textContent).toBe('2 files');
      });

      it('carries no count on the npm tab', async () => {
        createComponent({ format: 'NPM', mountFn: mountExtended });
        await waitForPromises();

        expect(findFilesCount().exists()).toBe(false);
      });

      const statisticsHandler = (filesCount) =>
        successHandler(
          versionRepository({
            version: { ...MAVEN_VERSION, statistics: { ...MAVEN_VERSION.statistics, filesCount } },
          }),
        );

      describe('when the statistics resolve without a count', () => {
        beforeEach(async () => {
          createComponent({ handler: statisticsHandler(null), mountFn: mountExtended });
          await waitForPromises();
        });

        it('carries no count on the Maven tab', () => {
          expect(findFilesCount().exists()).toBe(false);
        });
      });

      it('carries a zero as a zero, rather than dropping the badge', async () => {
        createComponent({ handler: statisticsHandler('0'), mountFn: mountExtended });
        await waitForPromises();

        expect(findFilesCount().text()).toBe('0');
        expect(findCountSrText().textContent).toBe('0 files');
      });

      it('carries no count when the statistics answer something that is not a number', async () => {
        createComponent({ handler: statisticsHandler('many'), mountFn: mountExtended });
        await waitForPromises();

        const filesTab = wrapper.findAllComponents(GlTab).at(1);

        expect(filesTab.props('tabCount')).toBe(null);
        expect(findFilesCount().exists()).toBe(false);
      });

      describe('paging', () => {
        const findPager = () => wrapper.findComponent(GlKeysetPagination);

        const pagedFiles = (pageInfo) =>
          filesHandler(filesRepository({ files: filePage(pageInfo) }));

        const onFirstPage = () =>
          createComponent({
            files: pagedFiles({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
            query: { tab: 'files' },
          });

        it('hands the pager the connection’s own page info', async () => {
          onFirstPage();
          await waitForPromises();

          expect(findPager().props()).toMatchObject({
            hasNextPage: true,
            hasPreviousPage: false,
            endCursor: FIRST_PAGE_END_CURSOR,
          });
        });

        it('reads the first page with no cursor at all', async () => {
          const files = pagedFiles({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR });
          createComponent({ files, query: { tab: 'files' } });
          await waitForPromises();

          expect(files).toHaveBeenCalledWith({
            organizationId: ORGANIZATION_GID,
            name: 'maven-releases',
            artifactId: 'e5f6a7b8-0000-0000-0000-000000000000',
            versionId: 'b8c9d0e1-0000-0000-0000-000000000000',
            first: 20,
          });
        });

        it('carries the forward cursor into the route, so a page survives a reload', async () => {
          onFirstPage();
          await waitForPromises();

          findPager().vm.$emit('next', FIRST_PAGE_END_CURSOR);

          expect(push).toHaveBeenCalledWith({
            path: VERSION_PATH,
            query: { tab: 'files', after: FIRST_PAGE_END_CURSOR },
          });
        });

        it('replaces the forward cursor with the backward one, never carrying both', async () => {
          createComponent({
            files: pagedFiles({ hasPreviousPage: true, startCursor: SECOND_PAGE_START_CURSOR }),
            query: { tab: 'files', after: FIRST_PAGE_END_CURSOR },
          });
          await waitForPromises();

          findPager().vm.$emit('prev', SECOND_PAGE_START_CURSOR);

          expect(push).toHaveBeenCalledWith({
            path: VERSION_PATH,
            query: { tab: 'files', before: SECOND_PAGE_START_CURSOR },
          });
        });

        it('asks for a forward page when the route names a forward cursor', async () => {
          const files = pagedFiles({ hasPreviousPage: true });
          createComponent({ files, query: { tab: 'files', after: FIRST_PAGE_END_CURSOR } });
          await waitForPromises();

          expect(files).toHaveBeenCalledWith(
            expect.objectContaining({ first: 20, after: FIRST_PAGE_END_CURSOR, last: undefined }),
          );
        });

        it('asks for a backward page, dropping first, when the route names a backward cursor', async () => {
          const files = pagedFiles({ hasNextPage: true });
          createComponent({ files, query: { tab: 'files', before: SECOND_PAGE_START_CURSOR } });
          await waitForPromises();

          expect(files).toHaveBeenCalledWith(
            expect.objectContaining({
              first: undefined,
              last: 20,
              before: SECOND_PAGE_START_CURSOR,
            }),
          );
        });

        it('offers previous and next alone, since the list carries no total', async () => {
          createComponent({
            files: pagedFiles({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
            query: { tab: 'files' },
            mountFn: mountExtended,
          });
          await waitForPromises();

          expect(
            findPager()
              .findAll('button')
              .wrappers.map((b) => b.text()),
          ).toEqual(['Previous', 'Next']);
        });

        it('announces the read in flight, rather than leaving the page silent', async () => {
          createComponent({
            files: jest.fn(() => new Promise(() => {})),
            query: { tab: 'files' },
          });
          await waitForPromises();

          expect(findAnnouncement().text()).toBe('Loading files.');
        });
      });

      describe('a version that stores no files', () => {
        const emptyFiles = () =>
          createComponent({
            files: filesHandler(filesRepository({ files: filePage({ nodes: [] }) })),
            query: { tab: 'files' },
            mountFn: mountExtended,
          });

        it('hands the section the version string, so the empty state can name it', async () => {
          emptyFiles();
          await waitForPromises();

          expect(findFilesSection().props('versionString')).toBe('3.2.1');
        });

        it('renders the empty state in place of the table', async () => {
          emptyFiles();
          await waitForPromises();

          expect(wrapper.findComponent(FilesEmptyState).exists()).toBe(true);
          expect(wrapper.findComponent(FilesTable).exists()).toBe(false);
        });

        it('keeps the header and the whole tab set rendered around it', async () => {
          emptyFiles();
          await waitForPromises();

          expect(findVersionName().text()).toBe('3.2.1');
          expect(findArtifactName().text()).toBe('com.example.tools:payment-core');
          expect(wrapper.findAllComponents(GlTab)).toHaveLength(2);
        });

        it('announces the empty result rather than leaving it a visual change', async () => {
          emptyFiles();
          await waitForPromises();

          expect(findAnnouncement().text()).toBe('Version 3.2.1 stores no files');
        });

        it('says nothing about files while Overview is the tab on screen', async () => {
          createComponent({
            files: filesHandler(filesRepository({ files: filePage({ nodes: [] }) })),
            mountFn: mountExtended,
          });
          await waitForPromises();

          expect(findAnnouncement().text()).toBe(
            'Overview tab for version 3.2.1 of com.example.tools:payment-core.',
          );
        });
      });

      it('hands the section a loading state while the files read is in flight', async () => {
        createComponent({
          files: jest.fn(() => new Promise(() => {})),
          query: { tab: 'files' },
        });
        await waitForPromises();

        expect(findFilesSection().props('loading')).toBe(true);
      });

      describe('when the files read resolves the version to null', () => {
        beforeEach(async () => {
          createComponent({
            files: filesHandler(filesRepository({ version: null })),
            query: { tab: 'files' },
            mountFn: mountExtended,
          });
          await waitForPromises();
        });

        it('marks the section errored, since the version went away between the two reads', () => {
          expect(findFilesSection().props('hasError')).toBe(true);
          expect(wrapper.findComponent(FilesEmptyState).exists()).toBe(false);
        });

        it('leaves the live region silent rather than stating a cause it cannot know', () => {
          expect(findAnnouncement().text()).toBe('');
        });
      });

      it('keeps the header when the files read fails, and marks the section errored', async () => {
        createComponent({
          files: jest.fn().mockRejectedValue(new Error('Unavailable')),
          query: { tab: 'files' },
        });
        await waitForPromises();

        expect(findFilesSection().props('hasError')).toBe(true);
        expect(findVersionName().text()).toBe('3.2.1');
        expect(findAlert().exists()).toBe(false);
      });

      it('leaves the failed tab to its own alert rather than announcing it loaded', async () => {
        createComponent({
          files: jest.fn().mockRejectedValue(new Error('Unavailable')),
          query: { tab: 'files' },
        });
        await waitForPromises();

        expect(findAnnouncement().text()).toBe('');
      });
    });

    describe('selecting a tab', () => {
      it('writes the tab into the query without touching the path', async () => {
        await createWithFormat('MAVEN');

        findTabs().vm.$emit('input', 1);

        expect(push).toHaveBeenCalledWith({ path: VERSION_PATH, query: { tab: 'files' } });
      });

      it('keeps the rest of the query, so another page-level selection survives', async () => {
        await createWithFormat('MAVEN', { some_other: 'value' });

        findTabs().vm.$emit('input', 1);

        expect(push).toHaveBeenCalledWith({
          path: VERSION_PATH,
          query: { some_other: 'value', tab: 'files' },
        });
      });

      it('pushes nothing when the tab selected is the one already active', async () => {
        await createWithFormat('MAVEN', { tab: 'files' });

        findTabs().vm.$emit('input', 1);

        expect(push).not.toHaveBeenCalled();
      });

      it('announces the Files tab when the route selects it', async () => {
        await createWithFormat('MAVEN', { tab: 'files' });

        expect(findAnnouncement().text()).toBe(
          'Files tab for version 3.2.1 of com.example.tools:payment-core.',
        );
      });
    });
  });

  describe('when the package does not resolve beside a resolved version', () => {
    beforeEach(async () => {
      createComponent({ handler: successHandler(versionRepository({ package: null })) });
      await waitForPromises();
    });

    it('still renders the version, because the page is the version rather than its parent', () => {
      expect(findVersionName().text()).toBe('3.2.1');
      expect(findNotFound().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });

    it('renders no artifact name rather than an empty one', () => {
      expect(findArtifactName().exists()).toBe(false);
    });

    it('still renders the sidebar, which describes the version rather than the package', () => {
      expect(findSidebar().exists()).toBe(true);
    });

    it('announces the version alone, with no empty gap where the artifact would be', () => {
      expect(findAnnouncement().text()).toBe('Overview tab for version 3.2.1.');
    });

    it('publishes an empty artifact name, so the crumb falls back to the id', () => {
      expect(updateArtifactName).toHaveBeenCalledWith('');
      expect(updateVersionName).toHaveBeenCalledWith('3.2.1');
    });

    it('hands the Overview tab a null artifact, which is what its guard reads', () => {
      expect(wrapper.findComponent(VersionOverview).props('artifact')).toBe(null);
    });
  });

  describe('what it publishes into the breadcrumb slots', () => {
    it('publishes nothing in flight, so the name the version list set stands', async () => {
      createComponent({ handler: jest.fn(() => new Promise(() => {})) });
      await waitForPromises();

      expect(updateArtifactName).not.toHaveBeenCalled();
      expect(updateVersionName).not.toHaveBeenCalled();
    });

    it('publishes an empty version name once the read settles without one', async () => {
      createComponent({ handler: successHandler(versionRepository({ version: null })) });
      await waitForPromises();

      expect(updateVersionName).toHaveBeenCalledWith('');
      expect(updateVersionName).not.toHaveBeenCalledWith('3.2.1');
    });

    it('publishes both names once, not an empty pair then the resolved one', async () => {
      createComponent();
      await waitForPromises();

      expect(updateArtifactName.mock.calls).toEqual([['com.example.tools:payment-core']]);
      expect(updateVersionName.mock.calls).toEqual([['3.2.1']]);
    });
  });

  describe('the Overview tab', () => {
    const findOverview = () => wrapper.findComponent(VersionOverview);

    it.each`
      format     | name                | artifactId
      ${'MAVEN'} | ${'maven-releases'} | ${'e5f6a7b8-0000-0000-0000-000000000000'}
      ${'NPM'}   | ${'npm-releases'}   | ${'f6a7b8c9-0000-0000-0000-000000000000'}
    `('renders the install panel for a $format version', async ({ format, name, artifactId }) => {
      createComponent({ format });
      await waitForPromises();

      expect(findOverview().props()).toMatchObject({
        format,
        name,
        artifact: expect.objectContaining({ id: artifactId }),
        version: expect.objectContaining({ version: '3.2.1' }),
      });
    });

    it('renders it once, in the Overview panel and in no other', async () => {
      createComponent();
      await waitForPromises();

      const [overview] = wrapper.findAllComponents(GlTab).wrappers;

      expect(wrapper.findAllComponents(VersionOverview)).toHaveLength(1);
      expect(overview.findComponent(VersionOverview).exists()).toBe(true);
    });
  });

  describe('deleting the version', () => {
    const VERSION_ID = 'b8c9d0e1-0000-0000-0000-000000000000';
    const ARTIFACT_ID = 'e5f6a7b8-0000-0000-0000-000000000000';

    const findActions = () => wrapper.findComponent(GlDisclosureDropdown);
    const findDeleteItem = () => wrapper.findComponent(GlDisclosureDropdownItem);
    const findDeleteButton = () => wrapper.findByTestId('delete-version');
    const findDeleteModal = () => wrapper.findComponent(DeleteConfirmationModal);

    const mountLoaded = async (options = {}) => {
      createComponent({ mountFn: mountExtended, ...options });
      await waitForPromises();
    };

    const openConfirmation = async () => {
      await findActions().find('button[aria-expanded]').trigger('click');
      findDeleteButton().find('button').trigger('click');
      await nextTick();
    };

    const confirmDeletion = async () => {
      findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
      await waitForPromises();
    };

    it('offers a delete action in the kebab, marked destructive', async () => {
      await mountLoaded();

      expect(findActions().props('toggleText')).toBe('More actions for 3.2.1');
      expect(findDeleteItem().props('item')).toMatchObject({
        text: 'Delete version',
        variant: 'danger',
      });
    });

    it('starts with the confirmation closed', async () => {
      await mountLoaded();

      expect(findDeleteModal().props('target')).toBeNull();
    });

    describe.each`
      outcome                           | handler
      ${'the read is still loading'}    | ${() => new Promise(() => {})}
      ${'the read fails'}               | ${() => Promise.reject(new Error('Unavailable'))}
      ${'the version does not resolve'} | ${successHandler(versionRepository({ version: null }))}
    `('when $outcome', ({ handler }) => {
      it('offers no actions', async () => {
        await mountLoaded({ handler });

        expect(findActions().exists()).toBe(false);
      });
    });

    describe('when the delete action is chosen', () => {
      let deleteHandler;

      beforeEach(async () => {
        deleteHandler = jest.fn().mockResolvedValue(mockDeleteVersionResponse());
        await mountLoaded({ deleteHandler });
        await openConfirmation();
      });

      it('opens the confirmation on this version and sends nothing yet', () => {
        expect(findDeleteModal().props()).toMatchObject({
          title: 'Delete version?',
          name: '3.2.1',
          actionText: 'Delete version',
          body: 'This action permanently deletes version %{name} and all of its files. This action cannot be undone.',
        });
        expect(findDeleteModal().props('target')).toMatchObject({ id: VERSION_ID });
        expect(deleteHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the confirmation is accepted', () => {
      let deleteHandler;

      beforeEach(async () => {
        deleteHandler = jest.fn().mockResolvedValue(mockDeleteVersionResponse());
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        await confirmDeletion();
      });

      it('addresses the version by id within its repository', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
        expect(deleteHandler).toHaveBeenCalledWith({
          input: { name: 'maven-releases', id: VERSION_ID },
        });
      });

      it('reports the delete as scheduled rather than done', () => {
        expect(mockToast.show).toHaveBeenCalledWith('Version successfully scheduled for deletion.');
      });

      it('navigates to the version list', () => {
        expect(push).toHaveBeenCalledWith({
          name: 'artifact_versions',
          params: { id: 'maven-releases', artifactId: ARTIFACT_ID },
        });
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when the delete is refused', () => {
      beforeEach(async () => {
        const deleteHandler = jest
          .fn()
          .mockResolvedValue(mockDeleteVersionResponse({ errors: ['Version not found.'] }));
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        await confirmDeletion();
      });

      it('surfaces the refusal and claims nothing', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Version not found.' });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('keeps the user on the page', () => {
        expect(push).not.toHaveBeenCalled();
      });

      it('releases the menu rather than leaving it pending', () => {
        expect(findActions().props('loading')).toBe(false);
      });
    });

    describe('when it is confirmed twice while the first is in flight', () => {
      let release;
      let deleteHandler;

      beforeEach(async () => {
        deleteHandler = jest.fn().mockReturnValue(
          new Promise((resolve) => {
            release = () => resolve(mockDeleteVersionResponse());
          }),
        );
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
        findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
        await nextTick();
      });

      it('sends one mutation', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
      });

      it('marks the menu as pending until the request settles', async () => {
        expect(findActions().props('loading')).toBe(true);

        release();
        await waitForPromises();

        expect(findActions().props('loading')).toBe(false);
      });
    });
  });
});
