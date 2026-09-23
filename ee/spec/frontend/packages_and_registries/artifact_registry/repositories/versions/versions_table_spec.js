import {
  GlBadge,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlLoadingIcon,
  GlTable,
} from '@gitlab/ui';
import { RouterLinkStub } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeDate } from 'helpers/fake_date';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import deleteVersionMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_version.mutation.graphql';
import getArtifactVersionsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_versions.query.graphql';
import { typePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';
import PullCommandDrawer from 'ee/packages_and_registries/artifact_registry/repositories/versions/pull_command_drawer.vue';
import VersionsTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/versions_table.vue';
import { VERSION_DETAIL_ROUTE_NAME } from 'ee/packages_and_registries/artifact_registry/constants';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  CLIENT_BASE_URL,
  MOCK_COMMIT_SHA,
  ORGANIZATION_GID,
  SLUG,
  REPOSITORY_ID,
  mockAttributedVersions,
  mockDeleteVersionResponse,
  mockDeniedRepositoryPermissions,
  mockPublishingProject,
  mockRepository,
  mockRepositoryArtifacts,
  mockRepositoryPermissions,
  mockVersionPage,
  mockVersions,
} from '../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

const collapseWhitespace = (text) => text.replace(/\s+/g, ' ').trim();

const MAVEN_PACKAGE = mockRepositoryArtifacts('MAVEN').package;

const NPM_PACKAGE = mockRepositoryArtifacts('NPM').package;

const DEFAULT_SORT = { sortBy: 'createdAt', sortDesc: true };

describe('ArtifactRegistryVersionsTable', () => {
  let wrapper;
  let mockApollo;

  const mockToast = { show: jest.fn() };

  useFakeDate(2026, 6, 15);

  // A sortable header carries its sort status as text beside the label, so the label is the
  // first line rather than the whole cell.
  const findHeaders = () =>
    wrapper.findAll('th').wrappers.map((th) => th.text().split('\n')[0].trim());
  const findVersionCells = () =>
    wrapper.findAllByTestId('version-name').wrappers.map((cell) => cell.text());
  const findPublishedCells = () => wrapper.findAllComponents(TimeAgoTooltip);
  const findMenus = () => wrapper.findAllByTestId('version-actions');
  const findPullCommandItems = () => wrapper.findAllByTestId('view-pull-command');
  const findDeleteItems = () => wrapper.findAllByTestId('delete-version');
  const findMenuComponents = () => wrapper.findAllComponents(GlDisclosureDropdown);
  const findDeleteItemComponents = () =>
    findDeleteItems().wrappers.map((item) => item.findComponent(GlDisclosureDropdownItem));
  const findDrawer = () => wrapper.findComponent(PullCommandDrawer);
  const findDeleteModal = () => wrapper.findComponent(DeleteConfirmationModal);

  // The panel is in the DOM whether or not the menu is open, so the toggle has to be driven
  // first for the click to be the one a user can actually make.
  const openPullCommandFor = async (index) => {
    await findMenus().at(index).find('button[aria-expanded]').trigger('click');

    findPullCommandItems().at(index).find('button').trigger('click');
    await nextTick();
  };

  const findCloseButton = () => wrapper.find('.gl-drawer-close-button');
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);

  const createComponent = ({
    versions = mockVersions,
    sort = DEFAULT_SORT,
    handlers = [],
    permissions = mockRepositoryPermissions(),
    ...props
  } = {}) => {
    mockApollo = createMockApollo(
      handlers,
      {},
      {
        typePolicies: { ...globalTypePolicies, ...typePolicies },
      },
    );

    wrapper = mountExtended(VersionsTable, {
      propsData: {
        versions,
        format: 'MAVEN',
        artifact: MAVEN_PACKAGE,
        name: mockRepository.name,
        sort,
        permissions,
        ...props,
      },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
      stubs: {
        MountingPortal: { name: 'MountingPortalStub', template: '<div><slot /></div>' },
        RouterLink: RouterLinkStub,
      },
      apolloProvider: mockApollo,
      mocks: { $toast: mockToast },
    });
  };

  const findVersionRoutes = () =>
    wrapper.findAllComponents(RouterLinkStub).wrappers.map((link) => link.props('to'));

  it('renders the columns an Artifact Registry version can fill', () => {
    createComponent();

    expect(findHeaders()).toEqual(['Version', 'Size', 'Published', 'Source', 'Actions']);
  });

  it('renders the version string of every row, in the order it was given', () => {
    createComponent();

    expect(findVersionCells()).toEqual(['3.2.1', '2.0.0']);
  });

  it('links every row to the version it names, under its artifact and repository', () => {
    createComponent();

    expect(findVersionRoutes()).toEqual(
      mockVersions.map((version) => ({
        name: VERSION_DETAIL_ROUTE_NAME,
        params: {
          id: mockRepository.name,
          artifactId: MAVEN_PACKAGE.id,
          versionId: version.id,
        },
      })),
    );
  });

  it('renders the publication date as a relative time', () => {
    createComponent();

    expect(findPublishedCells().wrappers.map((cell) => cell.props('time'))).toEqual([
      '2026-06-10T00:00:00Z',
      '2026-04-02T00:00:00Z',
    ]);
  });

  describe('when a column is hidden', () => {
    it('omits it from the table', () => {
      createComponent({ hiddenColumns: ['source'] });

      expect(findHeaders()).toEqual(['Version', 'Size', 'Published', 'Actions']);
    });
  });

  it('renders the headers with no rows for a version-less package', () => {
    createComponent({ versions: [] });

    expect(findHeaders()).toEqual(['Version', 'Size', 'Published', 'Source', 'Actions']);
    expect(findVersionCells()).toEqual([]);
  });

  describe('the Tags column', () => {
    const findRow = (row) => wrapper.findAll('tbody tr').at(row);
    const findTagsIn = (row) =>
      findRow(row)
        .findAllComponents(GlBadge)
        .wrappers.map((badge) => badge.text());
    const findUntaggedIn = (row) => findRow(row).find('[data-testid="version-untagged"]');

    describe('for an npm package', () => {
      beforeEach(() => createComponent({ format: 'NPM', artifact: NPM_PACKAGE }));

      it('renders it after the Version column', () => {
        expect(findHeaders()).toEqual([
          'Version',
          'Tags',
          'Size',
          'Published',
          'Source',
          'Actions',
        ]);
      });

      it('renders one badge per dist-tag, in the order given', () => {
        expect(findTagsIn(0)).toEqual(['latest', 'stable']);
        expect(findRow(0).findComponent(GlBadge).props('variant')).toBe('info');
        expect(findUntaggedIn(0).exists()).toBe(false);
      });

      it('reads a version with no dist-tag as untagged', () => {
        expect(findTagsIn(1)).toEqual([]);
        expect(findUntaggedIn(1).text()).toBe('untagged');
      });
    });

    it('is omitted when hidden', () => {
      createComponent({ format: 'NPM', artifact: NPM_PACKAGE, hiddenColumns: ['tags'] });

      expect(findHeaders()).toEqual(['Version', 'Size', 'Published', 'Source', 'Actions']);
      expect(wrapper.findAllComponents(GlBadge)).toHaveLength(0);
    });

    it('never renders for a Maven package, which has no tags', () => {
      createComponent();

      expect(findHeaders()).not.toContain('Tags');
      expect(wrapper.findAllComponents(GlBadge)).toHaveLength(0);
    });
  });

  describe('the Size column', () => {
    const findSizeIn = (row) =>
      wrapper.findAll('tbody tr').at(row).find('[data-testid="version-size"]');

    beforeEach(() => createComponent());

    it('renders the size as a human-readable byte count', () => {
      expect(findSizeIn(0).text()).toBe('15.64 MiB');
    });

    it('renders nothing for a version with no size', () => {
      expect(findSizeIn(1).exists()).toBe(false);
    });

    describe('when hidden', () => {
      beforeEach(() => createComponent({ hiddenColumns: ['sizeBytes'] }));

      it('is omitted from the table', () => {
        expect(findHeaders()).toEqual(['Version', 'Published', 'Source', 'Actions']);
        expect(wrapper.findAllByTestId('version-size')).toHaveLength(0);
      });
    });
  });

  describe('the Source column', () => {
    const findInRow = (row, testId) =>
      wrapper.findAll('tbody tr').at(row).find(`[data-testid="${testId}"]`);
    const findCommit = (row) => findInRow(row, 'version-commit');
    const findPublishedBy = (row) => findInRow(row, 'version-published-by');
    const findAttribution = (row) => findInRow(row, 'version-attribution');

    beforeEach(() => {
      createComponent({ versions: mockAttributedVersions });
    });

    it.each`
      row  | version                            | sha
      ${0} | ${'published from a commit'}       | ${'f19ac02a'}
      ${1} | ${'published with no publisher'}   | ${'ecea8971'}
      ${2} | ${'whose project did not resolve'} | ${'b7d4e920'}
    `('shortens the sha of the version $version', ({ row, sha }) => {
      expect(findCommit(row).text()).toBe(sha);
    });

    it('links the sha to the commit under the project the version was published from', () => {
      expect(findCommit(0).attributes('href')).toBe(
        `${mockPublishingProject.webPath}/-/commit/${MOCK_COMMIT_SHA}`,
      );
    });

    // Which is what a viewer without access to the publishing project sees.
    it('leaves the sha unlinked when the project did not resolve', () => {
      expect(findCommit(2).exists()).toBe(true);
      expect(findCommit(2).attributes('href')).toBeUndefined();
    });

    // The publisher goes on this line rather than the attribution line below, so it does not
    // repeat as "Published by Maria Santos" twice.
    it('names the publisher on the first line for a version published from no commit', () => {
      expect(findCommit(3).exists()).toBe(false);
      expect(collapseWhitespace(findPublishedBy(3).text())).toBe('Published by Maria Santos');
    });

    it.each`
      row  | version                            | attribution
      ${0} | ${'published from a commit'}       | ${'Published to payments-svc by Alex Turner'}
      ${1} | ${'published with no publisher'}   | ${'Published to payments-svc'}
      ${2} | ${'whose project did not resolve'} | ${'Published by Alex Turner'}
    `('attributes the version $version to what resolved', ({ row, attribution }) => {
      expect(collapseWhitespace(findAttribution(row).text())).toBe(attribution);
    });

    it('links the project to itself', () => {
      expect(findAttribution(0).find('a').attributes('href')).toBe(mockPublishingProject.webPath);
    });

    it('repeats the publisher nowhere for a version published from no commit', () => {
      expect(findAttribution(3).exists()).toBe(false);
    });

    it('renders the publish line alone for a version carrying no attribution at all', () => {
      expect(findCommit(4).exists()).toBe(false);
      expect(findAttribution(4).exists()).toBe(false);
      expect(findPublishedBy(4).text()).toBe('Published');
    });
  });

  describe('the row actions menu', () => {
    beforeEach(() => createComponent());

    it('gives every row a menu offering the pull command', () => {
      expect(findMenus()).toHaveLength(2);
      expect(findPullCommandItems().at(0).text()).toBe('View pull command');
    });

    it('names the version each menu belongs to, because its toggle renders as an icon', () => {
      expect(findMenus().at(0).text()).toContain('More actions for 3.2.1');
    });
  });

  describe('the pull command drawer', () => {
    beforeEach(() => createComponent());

    it('stays closed until a row asks for it', () => {
      expect(findDrawer().props('open')).toBe(false);
    });

    it('opens against the row it was asked from', async () => {
      await openPullCommandFor(1);

      expect(findDrawer().props()).toMatchObject({
        open: true,
        format: 'MAVEN',
        artifact: MAVEN_PACKAGE,
        version: '2.0.0',
        tags: [],
      });
    });

    it('hands the drawer the dist-tags of the row it was asked from', async () => {
      await openPullCommandFor(0);

      expect(findDrawer().props('tags')).toEqual(['latest', 'stable']);
    });

    it('renders that row command through the shell, not only into its props', async () => {
      await openPullCommandFor(1);

      expect(wrapper.text()).toContain("-Dversion='2.0.0'");
    });

    it('reopens against a different row rather than keeping the first', async () => {
      await openPullCommandFor(1);
      await openPullCommandFor(0);

      expect(findDrawer().props('version')).toBe('3.2.1');
    });

    it('closes from the drawer close button, taking the rendered command with it', async () => {
      await openPullCommandFor(0);

      await findCloseButton().trigger('click');

      expect(findDrawer().props('open')).toBe(false);
      expect(wrapper.text()).not.toContain("-Dversion='3.2.1'");
    });

    it('renders one drawer for the table rather than one per row', () => {
      expect(wrapper.findAllComponents(PullCommandDrawer)).toHaveLength(1);
    });
  });
  describe('sorting', () => {
    const FIELD_KEYS = ['version', 'sizeBytes', 'createdAt', 'source', 'actions'];

    const findHeaderCells = () => wrapper.findAllByRole('columnheader');
    const findSortStates = () =>
      Object.fromEntries(
        findHeaderCells().wrappers.map((header, index) => [
          FIELD_KEYS[index],
          header.attributes('aria-sort'),
        ]),
      );
    const clickHeader = (key) => findHeaderCells().at(FIELD_KEYS.indexOf(key)).trigger('click');
    const findSortHint = () => wrapper.findByTestId('version-sort-hint');

    it.each([
      [false, 'ascending'],
      [true, 'descending'],
    ])('exposes the active column, reading a sortDesc of %s as %s', (sortDesc, ariaSort) => {
      createComponent({ sort: { sortBy: 'version', sortDesc } });

      expect(findSortStates()).toEqual({
        version: ariaSort,
        sizeBytes: undefined,
        createdAt: 'none',
        source: undefined,
        actions: undefined,
      });
    });

    it.each(['version', 'createdAt'])(
      'asks for the %s column ascending when its header is clicked, leaving the row order alone',
      async (key) => {
        createComponent();

        await clickHeader(key);

        expect(wrapper.emitted('sort-changed')).toEqual([[{ sortBy: key, sortDesc: false }]]);
        expect(findVersionCells()).toEqual(mockVersions.map(({ version }) => version));
      },
    );

    it('reverses the direction when the header of the active column is clicked', async () => {
      createComponent();

      await clickHeader('createdAt');

      expect(wrapper.emitted('sort-changed')).toEqual([[{ sortBy: 'createdAt', sortDesc: false }]]);
    });

    it('follows a sort it did not ask for, so an externally applied sort reaches the header', async () => {
      createComponent({ sort: { sortBy: 'version', sortDesc: false } });

      expect(findSortStates()).toMatchObject({ version: 'ascending', createdAt: 'none' });

      wrapper.setProps({ sort: { sortBy: 'createdAt', sortDesc: true } });
      await nextTick();

      expect(findSortStates()).toMatchObject({ version: 'none', createdAt: 'descending' });
    });

    it('does not remount when the sort it asked for comes back down', async () => {
      createComponent();

      const tableBefore = wrapper.findComponent(GlTable).vm;

      await clickHeader('version');
      wrapper.setProps({ sort: { sortBy: 'version', sortDesc: false } });
      await nextTick();

      expect(wrapper.findComponent(GlTable).vm).toBe(tableBefore);
      expect(findSortStates()).toMatchObject({ version: 'ascending' });
    });

    // A tooltip alone never reaches a screen reader, so the same sentence is the icon's
    // accessible name.
    it('names the Version sort as alphabetical, so its order is not read as version precedence', () => {
      createComponent();

      const hint =
        'Sorts alphabetically, not by version order. Ascending puts 1.10.0 before 1.9.0.';

      expect(findSortHint().attributes('title')).toBe(hint);
      expect(findSortHint().attributes('aria-label')).toBe(hint);
      expect(findSortHint().attributes('aria-hidden')).toBeUndefined();
    });
  });
  describe('when a re-read for a new sort or page is in flight', () => {
    beforeEach(() => createComponent({ isLoading: true }));

    it('marks the table busy, so the rows it still renders are not read as the new order', () => {
      expect(wrapper.find('table').attributes('aria-busy')).toBe('true');
    });

    it('renders a loading affordance over the rows it keeps', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });
  });

  describe('when no read is in flight', () => {
    beforeEach(() => createComponent());

    it('leaves the table unbusy and renders no loading affordance', () => {
      expect(wrapper.find('table').attributes('aria-busy')).toBe('false');
      expect(findLoadingIcon().exists()).toBe(false);
    });
  });

  describe('deleting a version', () => {
    const version = mockVersions[0];

    let deleteHandler;
    let versionsHandler;

    // The document names the package by id, so the read the mutation refetches is keyed on
    // this artifact rather than on whichever versions read happened to be active.
    const versionsResponse = (versions = mockVersionPage) => ({
      data: {
        organization: {
          __typename: 'Organization',
          id: ORGANIZATION_GID,
          artifactRegistryRepository: {
            __typename: 'ArtifactRegistryRepositoryDetails',
            id: REPOSITORY_ID,
            name: mockRepository.name,
            format: 'MAVEN',
            package: {
              __typename: 'ArtifactRegistryMavenPackage',
              id: MAVEN_PACKAGE.id,
              versions,
            },
          },
        },
      },
    });

    // The table takes its rows as a prop, so the versions read is not one it runs. Watching it
    // here puts an active instance in the cache for the delete's `refetchQueries` to re-read,
    // which is what the row waits on before it stops showing as pending.
    const watchVersionsQuery = () => {
      mockApollo.defaultClient
        .watchQuery({
          query: getArtifactVersionsQuery,
          variables: {
            organizationId: ORGANIZATION_GID,
            name: mockRepository.name,
            artifactId: MAVEN_PACKAGE.id,
            first: 20,
          },
        })
        .subscribe(() => {});

      return waitForPromises();
    };

    const openDeleteFor = async (index) => {
      await findMenus().at(index).find('button[aria-expanded]').trigger('click');

      findDeleteItems().at(index).find('button').trigger('click');
      await nextTick();
    };

    const confirmDeletion = async () => {
      findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
      await waitForPromises();
    };

    beforeEach(() => {
      deleteHandler = jest.fn().mockResolvedValue(mockDeleteVersionResponse());
      versionsHandler = jest.fn().mockResolvedValue(versionsResponse());
      createComponent({
        handlers: [
          [deleteVersionMutation, deleteHandler],
          [getArtifactVersionsQuery, versionsHandler],
        ],
      });
    });

    it('offers a delete item on every row, marked destructive', () => {
      expect(findDeleteItemComponents()).toHaveLength(2);
      expect(findDeleteItemComponents()[0].props('item')).toMatchObject({
        text: 'Delete version',
        variant: 'danger',
      });
    });

    it('starts with the confirmation closed', () => {
      expect(findDeleteModal().props('target')).toBeNull();
    });

    describe('when a row is chosen', () => {
      beforeEach(async () => {
        await openDeleteFor(1);
      });

      it('opens the confirmation on that row and sends nothing', () => {
        expect(findDeleteModal().props()).toMatchObject({
          target: mockVersions[1],
          title: 'Delete version?',
          name: '2.0.0',
          actionText: 'Delete version',
        });
        expect(deleteHandler).not.toHaveBeenCalled();
      });

      it('spells out what the delete does, naming that version', () => {
        expect(findDeleteModal().props()).toMatchObject({
          body: 'This action permanently deletes version %{name} and all of its files. This action cannot be undone.',
          name: '2.0.0',
        });
      });

      it('closes again when the confirmation reports it was dismissed', async () => {
        findDeleteModal().vm.$emit('change', null);
        await nextTick();

        expect(findDeleteModal().props('target')).toBeNull();
        expect(deleteHandler).not.toHaveBeenCalled();
      });

      it('names the newly chosen row when it reopens on another', async () => {
        findDeleteModal().vm.$emit('change', null);
        await nextTick();
        await openDeleteFor(0);

        expect(findDeleteModal().props('name')).toBe(version.version);
      });
    });

    describe('when the confirmation is accepted', () => {
      beforeEach(async () => {
        await watchVersionsQuery();
        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('addresses the version by id within its repository', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
        expect(deleteHandler).toHaveBeenCalledWith({
          input: { name: mockRepository.name, id: version.id },
        });
      });

      it('re-reads the version list once the delete lands', () => {
        expect(versionsHandler).toHaveBeenCalledTimes(2);
      });

      it('reports the delete as scheduled rather than done', () => {
        expect(mockToast.show).toHaveBeenCalledWith('Version successfully scheduled for deletion.');
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('releases the row once the request settles', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });
    });

    describe('while the re-read after a delete is in flight', () => {
      let resolveRefetch;

      beforeEach(async () => {
        versionsHandler.mockResolvedValueOnce(versionsResponse()).mockReturnValueOnce(
          new Promise((resolve) => {
            resolveRefetch = () => resolve(versionsResponse());
          }),
        );
        await watchVersionsQuery();

        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('keeps the row pending until the re-read lands', async () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(true);
        expect(mockToast.show).not.toHaveBeenCalled();

        resolveRefetch();
        await waitForPromises();

        expect(findMenuComponents().at(0).props('loading')).toBe(false);
        expect(mockToast.show).toHaveBeenCalledWith('Version successfully scheduled for deletion.');
      });
    });

    describe('when the delete is refused', () => {
      beforeEach(async () => {
        deleteHandler.mockResolvedValue(
          mockDeleteVersionResponse({ errors: ['Version not found.'] }),
        );
        await watchVersionsQuery();

        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('surfaces the refusal and claims nothing', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Version not found.' });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('releases the row rather than leaving it pending', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });

      it('accepts a new request for the same row', async () => {
        await openDeleteFor(0);
        await confirmDeletion();

        expect(deleteHandler).toHaveBeenCalledTimes(2);
      });
    });

    describe('when it is confirmed twice while the first is in flight', () => {
      let release;

      beforeEach(async () => {
        deleteHandler.mockReturnValue(
          new Promise((resolve) => {
            release = () => resolve(mockDeleteVersionResponse());
          }),
        );
        await watchVersionsQuery();

        await openDeleteFor(0);
        findDeleteModal().vm.$emit('confirm', version);
        findDeleteModal().vm.$emit('confirm', version);
        await nextTick();
      });

      it('sends one mutation', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
      });

      it('marks only the row being deleted as pending', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(true);
        expect(findMenuComponents().at(1).props('loading')).toBe(false);
      });

      it('releases the row once the request settles', async () => {
        release();
        await waitForPromises();

        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });
    });
  });

  describe('the artifact delete verdict', () => {
    describe('when it allows', () => {
      beforeEach(() => createComponent({ permissions: mockRepositoryPermissions() }));

      it('offers the delete item on every row', () => {
        expect(findDeleteItems()).toHaveLength(2);
      });
    });

    describe('when it denies', () => {
      beforeEach(() => createComponent({ permissions: mockDeniedRepositoryPermissions() }));

      it('offers the delete item on no row', () => {
        expect(findDeleteItems()).toHaveLength(0);
      });

      it('keeps every row menu and its pull command, which no verdict gates', () => {
        expect(findMenuComponents()).toHaveLength(2);
        expect(findPullCommandItems()).toHaveLength(2);
      });

      it('keeps the confirmation closed rather than unmounting it', () => {
        expect(findDeleteModal().props('target')).toBeNull();
      });
    });

    describe('when the read carrying it has not answered', () => {
      beforeEach(() => createComponent({ permissions: null }));

      it('offers the delete item on no row, so nothing is offered optimistically', () => {
        expect(findDeleteItems()).toHaveLength(0);
      });
    });

    describe('when the artifact delete action alone denies', () => {
      beforeEach(() =>
        createComponent({ permissions: mockRepositoryPermissions({ deleteArtifact: false }) }),
      );

      it('offers the delete item on no row, because that action answers it', () => {
        expect(findDeleteItems()).toHaveLength(0);
      });
    });

    describe('when the artifact delete action alone allows', () => {
      beforeEach(() =>
        createComponent({ permissions: mockDeniedRepositoryPermissions({ deleteArtifact: true }) }),
      );

      it('offers the delete item on every row, because that action answers it', () => {
        expect(findDeleteItems()).toHaveLength(2);
      });
    });
  });
});
