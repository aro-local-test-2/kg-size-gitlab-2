import { GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import InboxRow from 'ee/ai/duo_agents_platform/panel/inbox_row.vue';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import { buildInboxRowItem } from '../../mocks';

describe('InboxRow', () => {
  let wrapper;
  let mockRouter;

  beforeEach(() => {
    mockRouter = { push: jest.fn() };
  });

  const createWrapper = ({
    item = buildInboxRowItem(),
    slots = { status: '<span data-testid="slotted-status">Status</span>' },
  } = {}) => {
    wrapper = shallowMountExtended(InboxRow, {
      propsData: { item },
      slots,
      mocks: { $router: mockRouter },
    });
  };

  const findLink = () => wrapper.findComponent(GlLink);
  const findTitle = () => wrapper.findByTestId('item-title');
  const findUpdatedDate = () => wrapper.findComponentByTestId('item-updated-date');
  const findMetadata = () => wrapper.findByTestId('item-metadata');

  describe('link', () => {
    beforeEach(() => createWrapper());

    it('points at the session page in the project', () => {
      expect(findLink().attributes('href')).toBe(
        '/gitlab-org/test-project/-/automate/agent-sessions/42',
      );
    });

    it('has no href when the project is null', () => {
      createWrapper({ item: buildInboxRowItem({ project: null }) });

      expect(findLink().attributes('href')).toBeUndefined();
    });
  });

  describe('default content', () => {
    beforeEach(() => createWrapper());

    it('renders the status slot in the header line', () => {
      expect(wrapper.findByTestId('slotted-status').text()).toBe('Status');
    });

    it('renders no status container when the slot is empty', () => {
      createWrapper({ slots: {} });

      expect(wrapper.findByTestId('item-status').exists()).toBe(false);
    });

    it('renders the session title', () => {
      expect(findTitle().text()).toBe('Fix the login bug');
    });

    it('tooltips the title with its session ID', () => {
      expect(findTitle().attributes('title')).toBe('Fix the login bug 42');
    });

    it('renders the age as a TimeAgoTooltip', () => {
      expect(findUpdatedDate().props('time')).toBe('2024-01-01T00:00:00Z');
    });

    it('renders the metadata line with numeric ID, flow name, and project name', () => {
      const text = findMetadata().text();

      expect(text).toContain('42');
      expect(text).toContain('Software development');
      expect(text).toContain('Test Project');
    });
  });

  describe('when project is null', () => {
    beforeEach(() => createWrapper({ item: buildInboxRowItem({ project: null }) }));

    it('renders the metadata line without the project name, and does not throw', () => {
      expect(findMetadata().exists()).toBe(true);
      expect(findMetadata().text()).not.toContain('Test Project');
    });
  });

  describe('when the session ran a catalog item', () => {
    beforeEach(() =>
      createWrapper({
        item: buildInboxRowItem({
          workflowDefinition: 'ai_catalog_agent',
          aiCatalogItem: { id: 'gid://gitlab/Ai::Catalog::Item/69', name: 'Issue Smoke Test' },
        }),
      }),
    );

    it('renders the catalog item name as the flow name', () => {
      expect(findMetadata().text()).toContain('Issue Smoke Test');
    });
  });

  describe('when the session has no catalog item', () => {
    beforeEach(() =>
      createWrapper({
        item: buildInboxRowItem({ workflowDefinition: 'ai_catalog_agent', aiCatalogItem: null }),
      }),
    );

    it('falls back to the humanized workflow definition', () => {
      expect(findMetadata().text()).toContain('Ai catalog agent');
    });
  });

  describe.each([null, ''])('when the title is %p', (title) => {
    beforeEach(() => createWrapper({ item: buildInboxRowItem({ title }) }));

    it('renders no title text', () => {
      expect(findTitle().text()).toBe('');
    });

    it('tooltips the session ID alone, rather than interpolating the empty title', () => {
      expect(findTitle().attributes('title')).toBe('42');
    });
  });

  describe('slot overrides', () => {
    it.each`
      slot          | replaces
      ${'title'}    | ${'item-title'}
      ${'trailing'} | ${'item-updated-date'}
      ${'metadata'} | ${'item-metadata'}
    `('the $slot slot replaces the default $replaces content', ({ slot, replaces }) => {
      createWrapper({ slots: { [slot]: `<b data-testid="slotted-${slot}">x</b>` } });

      expect(wrapper.findByTestId(`slotted-${slot}`).exists()).toBe(true);
      expect(wrapper.findByTestId(replaces).exists()).toBe(false);
    });

    it('renders the default slot between the title and the metadata line', () => {
      createWrapper({ slots: { default: '<p data-testid="slotted-body">note</p>' } });

      const { children } = findLink().element;
      const indexOf = (testid) =>
        Array.from(children).findIndex((el) => el.dataset.testid === testid);

      expect(indexOf('slotted-body')).toBeGreaterThan(indexOf('item-title'));
      expect(indexOf('slotted-body')).toBeLessThan(indexOf('item-metadata'));
    });
  });

  describe('navigation', () => {
    beforeEach(() => createWrapper());

    it('calls preventDefault and router.push on a plain click', async () => {
      const event = { metaKey: false, ctrlKey: false, shiftKey: false, preventDefault: jest.fn() };
      await findLink().vm.$emit('click', event);

      expect(event.preventDefault).toHaveBeenCalledTimes(1);
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: AGENTS_PLATFORM_SHOW_ROUTE,
        params: { id: 42 },
      });
    });

    describe.each(['metaKey', 'ctrlKey', 'shiftKey'])('when %s is pressed', (modifier) => {
      let event;

      beforeEach(async () => {
        event = {
          metaKey: false,
          ctrlKey: false,
          shiftKey: false,
          [modifier]: true,
          preventDefault: jest.fn(),
        };
        await findLink().vm.$emit('click', event);
      });

      it('leaves the default alone, so the browser opens the href in a new tab', () => {
        expect(event.preventDefault).not.toHaveBeenCalled();
      });

      it('does not navigate inside the panel', () => {
        expect(mockRouter.push).not.toHaveBeenCalled();
      });
    });
  });
});
