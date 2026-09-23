import { GlTable } from '@gitlab/ui';
import upstreamFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.query.graphql.json';
import containerUpstreamFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.container.query.graphql.json';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import { UPSTREAM_REPOSITORIES_ORDER_HELP } from 'ee/packages_and_registries/artifact_registry/constants';
import UpstreamRepositoriesTable from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repositories_table.vue';
import UpstreamRepositoryActions from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repository_actions.vue';
import { mockFullUpstreamRepositories, mockUpstreamAssociation } from '../../mock_data';

const upstreamRepositoriesFrom = (fixture) =>
  fixture.data.organization.artifactRegistryRepository.upstreamRepositories;

const serverUpstreamList = upstreamRepositoriesFrom(upstreamFixture);
const serverContainerUpstreamList = upstreamRepositoriesFrom(containerUpstreamFixture);

describe('ArtifactRegistryUpstreamRepositoriesTable', () => {
  let wrapper;

  const findTable = () => wrapper.findComponent(GlTable);
  const findHeaders = () => wrapper.findAll('thead th');
  const findRows = () => wrapper.findAll('tbody tr');
  const findHelpPopover = () => wrapper.findComponent(HelpPopover);
  const findPositions = () =>
    wrapper.findAllByTestId('upstream-position').wrappers.map((cell) => cell.text());
  const findNames = () =>
    wrapper.findAllByTestId('upstream-name').wrappers.map((cell) => cell.text());
  const findKinds = () =>
    wrapper.findAllByTestId('upstream-kind').wrappers.map((cell) => cell.text());
  const findActions = () => wrapper.findAllComponents(UpstreamRepositoryActions);

  const createComponent = ({ upstreamRepositories = serverUpstreamList } = {}) => {
    wrapper = mountExtended(UpstreamRepositoriesTable, {
      propsData: { upstreamRepositories },
      stubs: { UpstreamRepositoryActions: stubComponent(UpstreamRepositoryActions) },
    });
  };

  describe('the columns', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders Order, Repository, Type, and Actions, and nothing else', () => {
      expect(findHeaders().wrappers.map((header) => header.text())).toEqual([
        expect.stringContaining('Order'),
        'Repository',
        'Type',
        'Actions',
      ]);
    });

    it('offers no sort control on any column, because the order carries meaning', () => {
      expect(wrapper.findAll('th[aria-sort]')).toHaveLength(0);
      expect(
        findTable()
          .props('fields')
          .every(({ sortable }) => !sortable),
      ).toBe(true);
    });
  });

  describe('the row actions', () => {
    beforeEach(() => {
      createComponent();
    });

    it('mounts one actions menu per upstream', () => {
      expect(findActions()).toHaveLength(serverUpstreamList.length);
    });

    it('hands each menu the row upstream it acts on, not the association around it', () => {
      expect(findActions().wrappers.map((menu) => menu.props('upstreamRepository'))).toEqual(
        serverUpstreamList.map(({ upstreamRepository }) => upstreamRepository),
      );
    });
  });

  describe.each([
    ['the package family', serverUpstreamList],
    ['the container family', serverContainerUpstreamList],
  ])('on %s', (_family, upstreamRepositories) => {
    beforeEach(() => {
      createComponent({ upstreamRepositories });
    });

    it('renders one row per upstream', () => {
      expect(findRows()).toHaveLength(upstreamRepositories.length);
    });

    it('renders the 1-based position in the Order cell, in the order received', () => {
      expect(findPositions()).toEqual(upstreamRepositories.map(({ position }) => String(position)));
    });

    it('renders the Order value as a badge, centred in a narrow column', () => {
      expect(
        wrapper
          .findAllByTestId('upstream-position')
          .wrappers.every((cell) => cell.element.classList.contains('gl-badge')),
      ).toBe(true);
      expect(findHeaders().at(0).classes()).toContain('gl-w-1/10');
      expect(findHeaders().at(0).find('span').classes()).toEqual(
        expect.arrayContaining(['gl-w-full', 'gl-justify-center']),
      );
      expect(findTable().props('fields')[0].tdClass).toContain('gl-text-center');
    });

    it('names the upstream repository, not the association', () => {
      expect(findNames()).toEqual(
        upstreamRepositories.map(({ upstreamRepository }) => upstreamRepository.name),
      );
    });

    it('renders the kind as a badge per row', () => {
      expect(findKinds()).toEqual(
        upstreamRepositories.map(({ upstreamRepository }) =>
          upstreamRepository.kind === 'REMOTE' ? 'Remote' : 'Hosted',
        ),
      );
      expect(
        wrapper
          .findAllByTestId('upstream-kind')
          .wrappers.every((cell) => cell.element.classList.contains('gl-badge')),
      ).toBe(true);
    });

    it('links no row anywhere, because navigating to an upstream is unspecified', () => {
      expect(findRows().wrappers.every((row) => row.findAll('a').length === 0)).toBe(true);
    });
  });

  describe('a mixed container-family list', () => {
    beforeEach(() => {
      createComponent({ upstreamRepositories: serverContainerUpstreamList });
    });

    it('is handed no format to render, because the document selects none', () => {
      expect(
        serverContainerUpstreamList.map(({ upstreamRepository }) =>
          Object.keys(upstreamRepository).sort(),
        ),
      ).toEqual([
        ['__typename', 'id', 'kind', 'name'],
        ['__typename', 'id', 'kind', 'name'],
      ]);
    });
  });

  describe('a mixed container-family list whose summaries carry a format anyway', () => {
    beforeEach(() => {
      const formats = ['DOCKER', 'OCI'];

      createComponent({
        upstreamRepositories: serverContainerUpstreamList.map((association, index) => ({
          ...association,
          upstreamRepository: { ...association.upstreamRepository, format: formats[index] },
        })),
      });
    });

    it('renders every row', () => {
      expect(findNames()).toEqual(['docker-hub-proxy', 'base-images']);
    });

    it('renders neither format anywhere in its rows, so the rows read alike', () => {
      const body = wrapper.find('tbody').text();

      expect(body).not.toContain('Docker');
      expect(body).not.toContain('DOCKER');
      expect(body).not.toContain('OCI');
    });
  });

  describe('at the 20-upstream cap', () => {
    beforeEach(() => {
      createComponent({ upstreamRepositories: mockFullUpstreamRepositories });
    });

    it('renders every row, because the resource is unpaginated', () => {
      expect(findRows()).toHaveLength(20);
    });

    it('renders the positions in ascending order', () => {
      expect(findPositions()).toEqual(Array.from({ length: 20 }, (_, index) => String(index + 1)));
    });
  });

  describe('the Order help affordance', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders in the Order header, not in a cell', () => {
      expect(findHeaders().at(0).findComponent(HelpPopover).exists()).toBe(true);
    });

    it('is not stranded by a stacked layout, which would hide the header that carries it', () => {
      const classes = wrapper.find('table').classes();

      expect(classes.some((name) => name.startsWith('b-table-stacked'))).toBe(false);
      expect(findHeaders()).toHaveLength(4);
    });

    it('states the resolution order and points at the Edit form', () => {
      expect(findHelpPopover().props('options')).toEqual({
        content: UPSTREAM_REPOSITORIES_ORDER_HELP,
      });
      expect(UPSTREAM_REPOSITORIES_ORDER_HELP).toBe(
        'Repositories are checked in this order when resolving an artifact. To reorder, edit this repository.',
      );
    });

    it('carries the information glyph the design names, not the help default', () => {
      expect(findHelpPopover().props('icon')).toBe('information-o');
    });
  });

  describe('when the list is empty', () => {
    beforeEach(() => {
      createComponent({ upstreamRepositories: [] });
    });

    it('says so, rather than leaving the headers standing over nothing', () => {
      expect(findNames()).toEqual([]);
      expect(wrapper.find('tbody').text()).toBe('There are no upstream repositories yet');
    });

    it('keeps the headers, so the empty list still reads as this table', () => {
      expect(findHeaders()).toHaveLength(4);
    });
  });

  // A null or blank kind never reaches the badge: the server resolves those alongside a
  // top-level error, which the page renders instead of this table. An unmapped kind does.
  describe('a kind the label map does not carry', () => {
    beforeEach(() => {
      createComponent({
        upstreamRepositories: [
          mockUpstreamAssociation({
            id: 'a1000000-0000-4000-8000-000000000009',
            upstreamId: 'd1000000-0000-4000-8000-000000000009',
            position: 1,
            name: 'future-kind-source',
            format: 'MAVEN',
            kind: 'PROXY',
          }),
        ],
      });
    });

    it('renders the raw kind rather than an empty badge', () => {
      expect(findKinds()).toEqual(['PROXY']);
    });

    it('still renders the row, so an unmapped kind does not cost the list', () => {
      expect(findNames()).toEqual(['future-kind-source']);
    });
  });
});
