import { nextTick } from 'vue';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import UpstreamRepositoriesOrderTable from 'ee/packages_and_registries/artifact_registry/repositories/components/upstream_repositories_order_table.vue';
import UpstreamRepositoriesSection from 'ee/packages_and_registries/artifact_registry/repositories/components/upstream_repositories_section.vue';
import UpstreamRepositoryPicker from 'ee/packages_and_registries/artifact_registry/repositories/components/upstream_repository_picker.vue';
import { mockUpstreamSources } from '../../mock_data';

describe('ArtifactRegistryUpstreamRepositoriesSection', () => {
  let wrapper;

  const findCrud = () => wrapper.findComponent(CrudComponent);
  const findTitle = () => wrapper.findByTestId('crud-title');
  const findCounter = () => wrapper.findByTestId('crud-count');
  const findOrderInstruction = () => wrapper.findByTestId('crud-description');
  const findToggle = () => wrapper.findByTestId('crud-form-toggle');
  const findForm = () => wrapper.findByTestId('crud-form');
  const findEmptyBody = () => wrapper.findByTestId('crud-empty');
  const findTable = () => wrapper.findComponent(UpstreamRepositoriesOrderTable);
  const findBody = () => wrapper.findByTestId('crud-body');
  const findCapMessage = () => wrapper.findByTestId('upstream-repositories-cap-reached');
  const findAnnouncement = () => wrapper.findByTestId('upstream-repositories-announcement');
  const findPicker = () => wrapper.findComponent(UpstreamRepositoryPicker);

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(UpstreamRepositoriesSection, {
      propsData: {
        format: 'MAVEN',
        sources: mockUpstreamSources,
        ...props,
      },
      stubs: { UpstreamRepositoryPicker: true },
      attachTo: document.body,
    });
  };

  const openPicker = async () => {
    await findToggle().trigger('click');
  };

  describe.each([
    ['MAVEN', 'Maven repositories'],
    ['NPM', 'npm repositories'],
    ['DOCKER', 'Docker repositories'],
    ['OCI', 'OCI repositories'],
  ])('when the format is %s', (format, expected) => {
    beforeEach(() => {
      createComponent({ props: { format } });
    });

    it('names the format in the title', () => {
      expect(findCrud().props('title')).toBe(expected);
    });
  });

  describe('the header', () => {
    beforeEach(() => {
      createComponent();
    });

    it('counts the sources against the cap', () => {
      expect(findCounter().text()).toBe('3 of 20');
    });

    it('states that the order is the resolution order', () => {
      expect(findOrderInstruction().text()).toBe(
        'Use the arrow buttons to reorder repositories. Artifacts are resolved from top to bottom.',
      );
    });

    it('carries the add action as the card toggle', () => {
      expect(findCrud().props('toggleText')).toBe('Add repository');
      expect(findToggle().text()).toBe('Add repository');
    });

    it('opens the picker in the card, and asks its parent for nothing', async () => {
      await openPicker();

      expect(findPicker().exists()).toBe(true);
      expect(wrapper.emitted('add')).toBeUndefined();
      expect(wrapper.emitted('move')).toBeUndefined();
      expect(wrapper.emitted('remove')).toBeUndefined();
    });
  });

  describe('the frame', () => {
    beforeEach(() => {
      createComponent();
    });

    it('heads the card with the title, carrying the counter beside it', () => {
      expect(findTitle().element.tagName).toBe('H2');
      expect(findTitle().text()).toContain('Maven repositories');
      expect(findCounter().text()).toBe('3 of 20');
    });

    it('sets the list apart from the header, in a panel of its own', () => {
      expect(findBody().findComponent(UpstreamRepositoriesOrderTable).exists()).toBe(true);
    });
  });

  describe('the frame with no sources', () => {
    beforeEach(() => {
      createComponent({ props: { sources: [] } });
    });

    it('holds the empty body in the same panel', () => {
      expect(findBody().find('[data-testid="crud-empty"]').exists()).toBe(true);
    });
  });

  describe('when the count changes', () => {
    beforeEach(() => {
      createComponent();
    });

    it('counts an added source', async () => {
      await wrapper.setProps({
        sources: [
          ...mockUpstreamSources,
          { id: 'added', name: 'extra-source', kind: 'HOSTED', url: null },
        ],
      });

      expect(findCounter().text()).toBe('4 of 20');
    });

    it('counts a removed source', async () => {
      await wrapper.setProps({ sources: mockUpstreamSources.slice(0, 2) });

      expect(findCounter().text()).toBe('2 of 20');
    });

    it('counts a list narrowed to a single source', async () => {
      await wrapper.setProps({ sources: mockUpstreamSources.slice(0, 1) });

      expect(findCounter().text()).toBe('1 of 20');
    });
  });

  describe('when no sources have been added', () => {
    beforeEach(() => {
      createComponent({ props: { sources: [] } });
    });

    it('says so, naming the add control by the label it carries', () => {
      expect(findEmptyBody().text()).toBe(
        'No repositories added yet. Select Add repository to add a source.',
      );
      expect(findEmptyBody().text()).toContain(findToggle().text());
    });

    it('renders no table', () => {
      expect(findTable().exists()).toBe(false);
    });

    it('counts zero against the cap', () => {
      expect(findCounter().text()).toBe('0 of 20');
    });
  });

  describe('when the list holds the maximum number of sources', () => {
    const fullList = Array.from({ length: 20 }, (_, index) => ({
      id: `c1000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
      name: `source-${index + 1}`,
      kind: 'HOSTED',
      url: null,
    }));

    beforeEach(() => {
      createComponent({ props: { sources: fullList } });
    });

    it('counts the full list against the cap', () => {
      expect(findCounter().text()).toBe('20 of 20');
    });

    it('replaces the add action with a message that the maximum is reached', () => {
      expect(findCapMessage().text()).toBe('Maximum number of upstream repositories reached.');
      expect(findCrud().props('toggleText')).toBe(null);
      expect(findToggle().exists()).toBe(false);
    });

    it('offers the add action again once a source is removed', async () => {
      await wrapper.setProps({ sources: fullList.slice(1) });

      expect(findCapMessage().exists()).toBe(false);
      expect(findToggle().exists()).toBe(true);
    });
  });

  describe('when sources have been added', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the table with the sources in the order it holds them', () => {
      expect(findTable().props('sources')).toBe(mockUpstreamSources);
    });

    it('renders no empty body', () => {
      expect(findEmptyBody().exists()).toBe(false);
    });

    it('passes a move on to its parent', () => {
      findTable().vm.$emit('move', { from: 2, to: 0 });

      expect(wrapper.emitted('move')).toEqual([[{ from: 2, to: 0 }]]);
    });

    it('passes a removal on to its parent', () => {
      findTable().vm.$emit('remove', 1);

      expect(wrapper.emitted('remove')).toEqual([[1]]);
    });
  });

  describe('the picker', () => {
    const PICKED_SOURCES = [
      {
        id: 'c1000000-0000-4000-8000-000000000001',
        name: 'platform-libs',
        kind: 'HOSTED',
        url: null,
        sizeBytes: '4096',
      },
      {
        id: 'c1000000-0000-4000-8000-000000000002',
        name: 'maven-central',
        kind: 'REMOTE',
        url: 'https://repo1.maven.org/maven2',
        sizeBytes: null,
      },
    ];

    beforeEach(() => {
      createComponent();
    });

    it('stays shut until the add action is used', () => {
      expect(findPicker().exists()).toBe(false);
    });

    it('shuts when the format changes, discarding whatever was picked', async () => {
      await openPicker();
      await wrapper.setProps({ format: 'NPM' });

      expect(findPicker().exists()).toBe(false);
    });

    it('is handed the format, the repositories already listed, and the size of the list', async () => {
      await openPicker();

      expect(findPicker().props('format')).toBe('MAVEN');
      expect(findPicker().props('excludedIds')).toEqual([
        'd1000000-0000-4000-8000-000000000001',
        'd1000000-0000-4000-8000-000000000002',
        'd1000000-0000-4000-8000-000000000003',
      ]);
      expect(findPicker().props('listSize')).toBe(3);
    });

    it('sits above the list rather than in place of it', async () => {
      await openPicker();

      expect(findTable().exists()).toBe(true);
    });

    it('sits in the form panel of the card, apart from the list', async () => {
      await openPicker();

      expect(findForm().findComponent(UpstreamRepositoryPicker).exists()).toBe(true);
      expect(findBody().findComponent(UpstreamRepositoryPicker).exists()).toBe(false);
    });

    it('takes the place of the add action while it is open', async () => {
      await openPicker();

      expect(findToggle().exists()).toBe(false);
      expect(findCapMessage().exists()).toBe(false);
    });

    it('leaves the add action behind it when it closes', async () => {
      await openPicker();
      findPicker().vm.$emit('close');
      await nextTick();

      expect(findToggle().exists()).toBe(true);
    });

    it('passes the rows it confirms on to the parent', async () => {
      await openPicker();
      findPicker().vm.$emit('confirm', PICKED_SOURCES);
      await nextTick();

      expect(wrapper.emitted('add')).toEqual([[PICKED_SOURCES]]);
    });

    it('closes once it has confirmed', async () => {
      await openPicker();
      findPicker().vm.$emit('confirm', PICKED_SOURCES);
      await nextTick();

      expect(findPicker().exists()).toBe(false);
    });

    it('closes on a cancel, asking the parent for nothing', async () => {
      await openPicker();
      findPicker().vm.$emit('close');
      await nextTick();

      expect(findPicker().exists()).toBe(false);
      expect(wrapper.emitted('add')).toBeUndefined();
    });

    it('returns the focus to the add action it was opened from', async () => {
      await openPicker();
      findPicker().vm.$emit('close');
      await waitForPromises();

      expect(document.activeElement).toBe(findToggle().element);
    });

    it('returns the focus to the add action once it has confirmed', async () => {
      await openPicker();
      findPicker().vm.$emit('confirm', PICKED_SOURCES);
      await waitForPromises();

      expect(document.activeElement).toBe(findToggle().element);
    });

    it('moves the focus to the cap message when a confirm fills the list', async () => {
      const nearlyFull = Array.from({ length: 18 }, (_, index) => ({
        id: `e1000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
        name: `source-${index + 1}`,
        kind: 'HOSTED',
        url: null,
      }));
      await wrapper.setProps({ sources: nearlyFull });
      await openPicker();

      findPicker().vm.$emit('confirm', PICKED_SOURCES);
      await wrapper.setProps({ sources: [...nearlyFull, ...PICKED_SOURCES] });
      await waitForPromises();

      expect(findToggle().exists()).toBe(false);
      expect(document.activeElement).toBe(findCapMessage().element);
    });
  });

  describe('the picker with no sources yet', () => {
    beforeEach(async () => {
      createComponent({ props: { sources: [] } });
      await openPicker();
    });

    it('takes the place of the empty line rather than sitting beneath it', () => {
      expect(findPicker().exists()).toBe(true);
      expect(findEmptyBody().exists()).toBe(false);
    });

    it('leaves the empty line behind it when it closes', async () => {
      findPicker().vm.$emit('close');
      await nextTick();

      expect(findEmptyBody().text()).toBe(
        'No repositories added yet. Select Add repository to add a source.',
      );
    });
  });

  describe('focus after a removal', () => {
    beforeEach(() => {
      createComponent();
    });

    it('moves to the remove button of the row that took the removed row\u2019s place', async () => {
      findTable().vm.$emit('remove', 1);
      await wrapper.setProps({ sources: [mockUpstreamSources[0], mockUpstreamSources[2]] });
      await nextTick();

      const removeButtons = wrapper.findAllByTestId('remove-source');

      expect(document.activeElement).toBe(removeButtons.at(1).element);
      expect(removeButtons.at(1).attributes('aria-label')).toBe('Remove platform-snapshots');
    });

    it('moves to the add action when the last row goes', async () => {
      findTable().vm.$emit('remove', 0);
      await wrapper.setProps({ sources: [] });
      await nextTick();

      expect(document.activeElement).toBe(findToggle().element);
    });
  });

  describe('focus after a move', () => {
    const findUpArrows = () => wrapper.findAllByTestId('move-source-up');
    const findDownArrows = () => wrapper.findAllByTestId('move-source-down');
    const reorder = (order) =>
      wrapper.setProps({ sources: order.map((index) => mockUpstreamSources[index]) });

    beforeEach(() => {
      createComponent();
    });

    it('follows the row up, staying on the arrow that moved it', async () => {
      await findUpArrows().at(2).trigger('click');
      await reorder([0, 2, 1]);
      await nextTick();

      expect(document.activeElement).toBe(findUpArrows().at(1).element);
      expect(findUpArrows().at(1).attributes('aria-label')).toBe('Move platform-snapshots up');
    });

    it('follows the row down, staying on the arrow that moved it', async () => {
      await findDownArrows().at(0).trigger('click');
      await reorder([1, 0, 2]);
      await nextTick();

      expect(document.activeElement).toBe(findDownArrows().at(1).element);
      expect(findDownArrows().at(1).attributes('aria-label')).toBe('Move maven-central-proxy down');
    });

    it('lands on the boundary arrow after a jump to the end of the list', async () => {
      findTable().vm.$emit('move', { from: 0, to: 2 });
      await reorder([1, 2, 0]);
      await nextTick();

      expect(document.activeElement).toBe(findDownArrows().at(2).element);
      expect(findDownArrows().at(2).attributes('aria-label')).toBe('Move maven-central-proxy down');
      expect(findDownArrows().at(2).attributes('aria-disabled')).toBe('true');
    });
  });

  describe('the order announcement', () => {
    beforeEach(() => {
      createComponent();
    });

    it('sits in a polite, atomic region that is read out but not shown', () => {
      expect(findAnnouncement().classes()).toContain('gl-sr-only');
      expect(findAnnouncement().attributes('aria-live')).toBe('polite');
      expect(findAnnouncement().attributes('aria-atomic')).toBe('true');
    });

    it('announces nothing until something changes', () => {
      expect(findAnnouncement().text()).toBe('');
    });

    it.each([
      [{ from: 2, to: 0 }, [2, 0, 1], 'platform-snapshots moved to position 1 of 3.'],
      [{ from: 0, to: 1 }, [1, 0, 2], 'maven-central-proxy moved to position 2 of 3.'],
      [{ from: 0, to: 2 }, [1, 2, 0], 'maven-central-proxy moved to position 3 of 3.'],
    ])('announces the settled position after %p', async (move, order, expected) => {
      findTable().vm.$emit('move', move);
      await wrapper.setProps({ sources: order.map((index) => mockUpstreamSources[index]) });

      expect(findAnnouncement().text()).toBe(expected);
    });

    it('announces the renumbered list after a removal', async () => {
      findTable().vm.$emit('remove', 0);
      await wrapper.setProps({ sources: mockUpstreamSources.slice(1) });

      expect(findAnnouncement().text()).toBe(
        'Resolution order updated: 1. payments-releases, 2. platform-snapshots.',
      );
    });

    it('announces the renumbered list after an add', async () => {
      await wrapper.setProps({
        sources: [
          ...mockUpstreamSources,
          { id: 'added', name: 'extra-source', kind: 'HOSTED', url: null },
        ],
      });

      expect(findAnnouncement().text()).toBe(
        'Resolution order updated: 1. maven-central-proxy, 2. payments-releases, 3. platform-snapshots, 4. extra-source.',
      );
    });

    it('announces that nothing is left when the last source goes', async () => {
      findTable().vm.$emit('remove', 0);
      await wrapper.setProps({ sources: [] });
      await nextTick();

      expect(findAnnouncement().text()).toBe(
        'All upstream repositories removed. The list is empty.',
      );
    });
  });

  describe.each([
    ['with sources', mockUpstreamSources],
    ['without sources', []],
  ])('%s', (_state, sources) => {
    beforeEach(() => {
      createComponent({ props: { sources } });
    });

    it('renders no cache-eviction control', () => {
      expect(wrapper.findByTestId('clear-cache').exists()).toBe(false);
      expect(wrapper.findByTestId('clear-source-cache').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('Clear cache');
    });
  });
});
