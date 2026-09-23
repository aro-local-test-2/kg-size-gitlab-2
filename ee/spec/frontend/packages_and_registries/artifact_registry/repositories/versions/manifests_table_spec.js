import {
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlLoadingIcon,
  GlTable,
  GlTruncate,
} from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeDate } from 'helpers/fake_date';
import waitForPromises from 'helpers/wait_for_promises';
import deleteManifestMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_manifest.mutation.graphql';
import getArtifactManifestsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_manifests.query.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';
import ManifestsTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/manifests_table.vue';
import PullCommandDrawer from 'ee/packages_and_registries/artifact_registry/repositories/versions/pull_command_drawer.vue';
import { createAlert } from '~/alert';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  CLIENT_BASE_URL,
  MOCK_RAW_ARTIFACT_TYPE,
  SLUG,
  mockDeniedRepositoryPermissions,
  mockLabelledManifests,
  mockManifests,
  mockRepository,
  mockRepositoryArtifacts,
  mockRepositoryPermissions,
} from '../../mock_data';

jest.mock('ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation');
jest.mock('~/alert');

Vue.use(VueApollo);

const DEFAULT_SORT = { sortBy: 'createdAt', sortDesc: true };

const DOCKER_IMAGE = mockRepositoryArtifacts('DOCKER').image;

describe('ArtifactRegistryManifestsTable', () => {
  let wrapper;
  let apolloProvider;

  const mockToast = { show: jest.fn() };

  useFakeDate(2026, 6, 15);

  // A sortable header carries its sort status as text beside the label, so the label is the
  // first line rather than the whole cell.
  const findHeaders = () =>
    wrapper.findAll('th').wrappers.map((th) => th.text().split('\n')[0].trim());
  const findDigestCells = () =>
    wrapper.findAllByTestId('manifest-digest').wrappers.map((cell) => cell.text());
  const findSizeCells = () =>
    wrapper.findAllByTestId('manifest-size').wrappers.map((cell) => cell.text());
  const findPublishedCells = () => wrapper.findAllComponents(TimeAgoTooltip);
  const findCopyButtons = () => wrapper.findAllComponents(ClipboardButton);
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findMenus = () => wrapper.findAllByTestId('manifest-actions');
  const findMenuComponents = () => wrapper.findAllComponents(GlDisclosureDropdown);
  const findDeleteItems = () => wrapper.findAllByTestId('delete-manifest');
  const findDeleteItemComponents = () =>
    findDeleteItems().wrappers.map((item) => item.findComponent(GlDisclosureDropdownItem));
  const findDeleteModal = () => wrapper.findComponent(DeleteConfirmationModal);
  const findPullCommandItems = () => wrapper.findAllByTestId('view-pull-command');
  const findDrawer = () => wrapper.findComponent(PullCommandDrawer);
  const findCloseButton = () => wrapper.find('.gl-drawer-close-button');

  const openPullCommandFor = async (index) => {
    await findMenus().at(index).find('button[aria-expanded]').trigger('click');

    findPullCommandItems().at(index).find('button').trigger('click');
    await nextTick();
  };

  const createComponent = ({
    manifests = mockManifests,
    sort = DEFAULT_SORT,
    permissions = mockRepositoryPermissions(),
    ...props
  } = {}) => {
    apolloProvider = createMockApollo();
    jest.spyOn(apolloProvider.defaultClient, 'refetchQueries').mockResolvedValue([]);

    wrapper = mountExtended(ManifestsTable, {
      propsData: {
        manifests,
        format: 'DOCKER',
        artifact: DOCKER_IMAGE,
        name: mockRepository.name,
        imageId: DOCKER_IMAGE.id,
        sort,
        permissions,
        ...props,
      },
      apolloProvider,
      mocks: { $toast: mockToast },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
      stubs: {
        MountingPortal: { name: 'MountingPortalStub', template: '<div><slot /></div>' },
      },
    });
  };

  const findRefetches = () => apolloProvider.defaultClient.refetchQueries;

  describe('when a column is hidden', () => {
    it('omits it from the table', () => {
      createComponent({ hiddenColumns: ['size'] });

      expect(findHeaders()).toEqual(['Digest', 'Type', 'Published', 'Actions']);
    });
  });

  // GlSprintf splices its slots with direction marks, which a text comparison would otherwise
  // read as characters of the label.
  const stripDirectionMarks = (text) => text.replace(/\u200e/g, '');

  const findTypeCell = (row) =>
    stripDirectionMarks(wrapper.findAllByTestId('manifest-type').at(row).text());

  it('renders the columns an Artifact Registry manifest can fill', () => {
    createComponent();

    expect(findHeaders()).toEqual(['Digest', 'Type', 'Size', 'Published', 'Actions']);
  });

  describe('the Type column', () => {
    beforeEach(() => {
      createComponent();
    });

    it.each`
      row  | manifest                      | label
      ${0} | ${'an index'}                 | ${'Index'}
      ${1} | ${'a platform image'}         | ${'Image'}
      ${2} | ${'a cosign signature'}       | ${'Signature for 111111111111'}
      ${3} | ${'an SBOM attestation'}      | ${'SBOM attestation for 222222222222'}
      ${4} | ${'a SLSA attestation'}       | ${'SLSA attestation for 222222222222'}
      ${5} | ${'an unrecognized referrer'} | ${`${MOCK_RAW_ARTIFACT_TYPE} for 222222222222`}
      ${6} | ${'a referrer with no type'}  | ${'Referrer for 222222222222'}
    `('names $manifest by what it is, and a referrer by what it attaches to', ({ row, label }) => {
      expect(findTypeCell(row)).toBe(label);
    });

    it('renders one truncation, for the referrer that carries an artifact type to truncate', () => {
      expect(wrapper.findAllComponents(GlTruncate)).toHaveLength(1);
    });

    it('renders an unrecognized artifact type through a truncation with its full value', () => {
      const truncate = wrapper.findComponent(GlTruncate);

      expect(truncate.props('text')).toBe(MOCK_RAW_ARTIFACT_TYPE);
      expect(truncate.props('withTooltip')).toBe(true);
    });

    it('renders no truncation for a page whose every type it recognizes', () => {
      createComponent({ manifests: mockLabelledManifests });

      expect(wrapper.findComponent(GlTruncate).exists()).toBe(false);
    });
  });

  it('shortens the digest to twelve characters and drops the algorithm prefix', () => {
    createComponent();

    expect(findDigestCells()).toEqual([
      '111111111111',
      '222222222222',
      '333333333333',
      '444444444444',
      '555555555555',
      '666666666666',
      '777777777777',
    ]);
  });

  it('offers the full canonical digest to copy, since the row renders only part of it', () => {
    createComponent();

    expect(findCopyButtons().wrappers.map((button) => button.props('text'))).toEqual(
      mockManifests.map(({ digest }) => digest),
    );
  });

  it('renders the size as a human-readable byte count', () => {
    createComponent();

    expect(findSizeCells()).toEqual([
      '3.07 MiB',
      '2.00 MiB',
      '3.37 KiB',
      '3.37 KiB',
      '3.37 KiB',
      '3.37 KiB',
      '3.37 KiB',
    ]);
  });

  it('renders the publication date as a relative time', () => {
    createComponent();

    expect(findPublishedCells().wrappers.map((cell) => cell.props('time'))).toEqual(
      mockManifests.map(({ createdAt }) => createdAt),
    );
  });

  it('renders the headers with no rows for an image carrying no manifests', () => {
    createComponent({ manifests: [] });

    expect(findHeaders()).toEqual(['Digest', 'Type', 'Size', 'Published', 'Actions']);
    expect(findDigestCells()).toEqual([]);
  });

  describe('the row actions menu', () => {
    beforeEach(() => createComponent());

    it('gives every row a menu offering the pull command', () => {
      expect(findMenus()).toHaveLength(mockManifests.length);
      expect(findPullCommandItems().at(0).text()).toBe('View pull command');
    });

    it('names the manifest each menu belongs to by its short digest, because its toggle renders as an icon', () => {
      expect(findMenus().at(0).text()).toContain('More actions for 111111111111');
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
        format: 'DOCKER',
        artifact: DOCKER_IMAGE,
        name: mockRepository.name,
        digest: mockManifests[1].digest,
      });
    });

    it('renders that row command through the shell, not only into its props', async () => {
      await openPullCommandFor(1);

      expect(wrapper.text()).toContain(
        `docker pull 'artifact-registry.example.com/acme/container/my-repository/payment-service@${mockManifests[1].digest}'`,
      );
    });

    it('reopens against a different row rather than keeping the first', async () => {
      await openPullCommandFor(1);
      await openPullCommandFor(0);

      expect(findDrawer().props('digest')).toBe(mockManifests[0].digest);
    });

    it('closes from the drawer close button, taking the rendered command with it', async () => {
      await openPullCommandFor(0);

      await findCloseButton().trigger('click');

      expect(findDrawer().props('open')).toBe(false);
      expect(wrapper.text()).not.toContain('docker pull');
    });

    it('renders one drawer for the table rather than one per row', () => {
      expect(wrapper.findAllComponents(PullCommandDrawer)).toHaveLength(1);
    });
  });

  describe('sorting', () => {
    const FIELD_KEYS = ['digest', 'type', 'size', 'createdAt', 'actions'];

    const findHeaderCells = () => wrapper.findAllByRole('columnheader');
    const findSortStates = () =>
      Object.fromEntries(
        findHeaderCells().wrappers.map((header, index) => [
          FIELD_KEYS[index],
          header.attributes('aria-sort'),
        ]),
      );
    const clickHeader = (key) => findHeaderCells().at(FIELD_KEYS.indexOf(key)).trigger('click');

    it.each([
      [false, 'ascending'],
      [true, 'descending'],
    ])('exposes the active column, reading a sortDesc of %s as %s', (sortDesc, ariaSort) => {
      createComponent({ sort: { sortBy: 'createdAt', sortDesc } });

      expect(findSortStates()).toEqual({
        digest: undefined,
        type: undefined,
        size: undefined,
        createdAt: ariaSort,
        actions: undefined,
      });
    });

    it('asks for Published ascending when its header is clicked, leaving the row order alone', async () => {
      createComponent();

      await clickHeader('createdAt');

      expect(wrapper.emitted('sort-changed')).toEqual([[{ sortBy: 'createdAt', sortDesc: false }]]);
      expect(findDigestCells()).toHaveLength(mockManifests.length);
    });

    it('follows a sort it did not ask for, so an externally applied sort reaches the header', async () => {
      createComponent({ sort: { sortBy: 'createdAt', sortDesc: false } });

      expect(findSortStates()).toMatchObject({ createdAt: 'ascending' });

      wrapper.setProps({ sort: { sortBy: 'createdAt', sortDesc: true } });
      await nextTick();

      expect(findSortStates()).toMatchObject({ createdAt: 'descending' });
    });

    it('does not remount when the sort it asked for comes back down', async () => {
      createComponent();

      const tableBefore = wrapper.findComponent(GlTable).vm;

      await clickHeader('createdAt');
      wrapper.setProps({ sort: { sortBy: 'createdAt', sortDesc: false } });
      await nextTick();

      expect(wrapper.findComponent(GlTable).vm).toBe(tableBefore);
      expect(findSortStates()).toMatchObject({ createdAt: 'ascending' });
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

  describe('deleting a manifest', () => {
    const index = mockManifests[0];

    const openDeleteFor = async (row) => {
      await findMenus().at(row).find('button[aria-expanded]').trigger('click');

      findDeleteItems().at(row).find('button').trigger('click');
      await nextTick();
    };

    const confirmDeletion = async () => {
      findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
      await waitForPromises();
    };

    beforeEach(() => {
      executeDeleteMutation.mockResolvedValue(true);
      createComponent();
    });

    it('offers a delete item on every row, marked destructive', () => {
      expect(findDeleteItemComponents()).toHaveLength(mockManifests.length);
      expect(findDeleteItemComponents()[0].props('item')).toMatchObject({
        text: 'Delete manifest',
        variant: 'danger',
      });
    });

    it('names the manifest in the menu toggle, which renders as an icon', () => {
      expect(findMenuComponents().at(0).props('toggleText')).toBe('More actions for 111111111111');
    });

    it('starts with the confirmation closed', () => {
      expect(findDeleteModal().props('target')).toBeNull();
    });

    describe('when a row is chosen', () => {
      beforeEach(async () => {
        await openDeleteFor(0);
      });

      it('opens the confirmation on that row and sends nothing', () => {
        expect(findDeleteModal().props()).toMatchObject({
          title: 'Delete manifest?',
          name: '111111111111',
          actionText: 'Delete manifest',
        });
        expect(findDeleteModal().props('target')).toMatchObject({ digest: index.digest });
        expect(executeDeleteMutation).not.toHaveBeenCalled();
      });

      it('closes again when the confirmation reports it was dismissed', async () => {
        findDeleteModal().vm.$emit('change', null);
        await nextTick();

        expect(findDeleteModal().props('target')).toBeNull();
        expect(executeDeleteMutation).not.toHaveBeenCalled();
      });
    });

    describe.each`
      row  | kind             | body
      ${0} | ${'an index'}    | ${'This action permanently deletes manifest %{name} and any tags pointing to it. Its child manifests are not deleted and will remain in Artifact Registry as untagged, standalone manifests. This action cannot be undone.'}
      ${1} | ${'an image'}    | ${'This action permanently deletes manifest %{name} and any tags pointing to it. This action cannot be undone.'}
      ${2} | ${'a signature'} | ${'This action permanently deletes signature %{name} and any tags pointing to it. The image it signs will then verify as unsigned. This action cannot be undone.'}
    `('when the chosen row is $kind', ({ row, body }) => {
      beforeEach(async () => {
        await openDeleteFor(row);
      });

      it('spells out what the delete costs for that kind', () => {
        expect(findDeleteModal().props('body')).toBe(body);
      });
    });

    describe('when the confirmation is accepted', () => {
      beforeEach(async () => {
        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('addresses the manifest by digest within its image, sending no refetch of its own', () => {
        expect(executeDeleteMutation).toHaveBeenCalledWith(expect.anything(), {
          mutation: deleteManifestMutation,
          input: {
            name: mockRepository.name,
            imageId: DOCKER_IMAGE.id,
            digest: index.digest,
          },
        });
      });

      it('re-reads the manifest list', () => {
        expect(findRefetches()).toHaveBeenCalledWith({
          include: [getArtifactManifestsQuery],
        });
      });

      it('reports the delete as scheduled rather than done', () => {
        expect(mockToast.show).toHaveBeenCalledWith(
          'Manifest successfully scheduled for deletion.',
        );
      });

      it('releases the row once the request settles', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });
    });

    describe('when the delete is refused', () => {
      beforeEach(async () => {
        executeDeleteMutation.mockResolvedValue(false);

        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('claims nothing', () => {
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('leaves the list alone, because nothing was deleted', () => {
        expect(findRefetches()).not.toHaveBeenCalled();
      });

      it('releases the row rather than leaving it pending', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });

      it('accepts a new request for the same row', async () => {
        await openDeleteFor(0);
        await confirmDeletion();

        expect(executeDeleteMutation).toHaveBeenCalledTimes(2);
      });
    });

    describe('when the re-read fails after an accepted delete', () => {
      beforeEach(async () => {
        findRefetches().mockRejectedValue(new Error('network'));

        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('surfaces the failure rather than swallowing it', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong. Please try again.',
          error: expect.any(Error),
          captureError: true,
        });
      });

      it('does not claim the delete as scheduled', () => {
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('releases the row rather than leaving it pending', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });
    });

    describe('when it is confirmed twice while the first is in flight', () => {
      let release;

      beforeEach(async () => {
        executeDeleteMutation.mockReturnValue(
          new Promise((resolve) => {
            release = () => resolve(true);
          }),
        );

        await openDeleteFor(0);
        findDeleteModal().vm.$emit('confirm', index);
        findDeleteModal().vm.$emit('confirm', index);
        await nextTick();
      });

      it('sends one mutation', () => {
        expect(executeDeleteMutation).toHaveBeenCalledTimes(1);
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
        expect(findDeleteItems()).toHaveLength(mockManifests.length);
      });
    });

    describe('when it denies', () => {
      beforeEach(() => createComponent({ permissions: mockDeniedRepositoryPermissions() }));

      it('offers the delete item on no row', () => {
        expect(findDeleteItems()).toHaveLength(0);
      });

      it('keeps every row menu and its pull command, which no verdict gates', () => {
        expect(findMenuComponents()).toHaveLength(mockManifests.length);
        expect(findPullCommandItems()).toHaveLength(mockManifests.length);
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
        expect(findDeleteItems()).toHaveLength(mockManifests.length);
      });
    });
  });
});
