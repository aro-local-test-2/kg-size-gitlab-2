import { GlKeysetPagination, GlTable } from '@gitlab/ui';
import { mount } from '@vue/test-utils';

import { nextTick } from 'vue';
import EmptyResult from '~/vue_shared/components/empty_result.vue';
import AuditEventsTable from 'ee/audit_events/components/audit_events_table.vue';
import AuditEventDetailsDrawer from 'ee/audit_events/components/audit_event_details_drawer.vue';
import setWindowLocation from 'helpers/set_window_location_helper';
import { visitUrl } from '~/lib/utils/url_utility';
import createEvents from '../mock_data';

jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
}));

const EVENTS = createEvents().map((event, index) => ({
  ...event,
  details: { custom_message: `Test message ${index}`, target_id: index },
}));

describe('AuditEventsTable component', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    return mount(AuditEventsTable, {
      propsData: {
        events: EVENTS,
        isLastPage: false,
        ...props,
      },
    });
  };

  const getCell = (trIdx, tdIdx) => {
    return wrapper.findComponent(GlTable).findAll('tr').at(trIdx).findAll('td').at(tdIdx);
  };

  beforeEach(() => {
    setWindowLocation('https://localhost');

    wrapper = createComponent();
  });

  describe('Empty behaviour', () => {
    it('should show the empty state if there is no data', async () => {
      wrapper.setProps({ events: [] });
      await nextTick();
      expect(wrapper.findComponent(EmptyResult).exists()).toBe(true);
    });
  });

  describe('Table behaviour', () => {
    it('should show', () => {
      expect(getCell(1, 0).text()).toBe('User');
    });

    it('applies a fixed table layout so long cell content cannot expand the table width', () => {
      expect(wrapper.findComponent(GlTable).find('table').classes()).toContain(
        'gl-table-layout-fixed',
      );
    });

    it.each`
      removed  | name                | expected
      ${false} | ${'(System)'}       | ${'(System)'}
      ${true}  | ${'A deleted user'} | ${'A deleted user (removed)'}
    `(
      'renders an author without a url as "$expected" when removed=$removed',
      ({ removed, name, expected }) => {
        wrapper = createComponent({
          events: [{ ...EVENTS[0], author: { name, url: null, removed } }],
        });

        expect(getCell(1, 0).text()).toBe(expected);
      },
    );
  });

  describe('Pagination behaviour', () => {
    it('should show', () => {
      expect(wrapper.findComponent(GlKeysetPagination).exists()).toBe(true);
    });

    it('should hide if there is no data', async () => {
      wrapper.setProps({ events: [] });
      await nextTick();
      expect(wrapper.findComponent(GlKeysetPagination).exists()).toBe(false);
    });

    it('should not have a previous page if the page is 1', () => {
      setWindowLocation('?page=1');
      wrapper = createComponent();

      expect(wrapper.findComponent(GlKeysetPagination).props().hasPreviousPage).toBe(false);
    });

    it('should have a previous page if the page is 2', () => {
      setWindowLocation('?page=2');
      wrapper = createComponent();

      expect(wrapper.findComponent(GlKeysetPagination).props().hasPreviousPage).toBe(true);
    });

    it('should not have a next page if isLastPage is true', async () => {
      wrapper.setProps({ isLastPage: true });
      await nextTick();
      expect(wrapper.findComponent(GlKeysetPagination).props().hasNextPage).toBe(false);
    });

    it('should have a next page if the page is 1', () => {
      setWindowLocation('?page=1');
      wrapper = createComponent();

      expect(wrapper.findComponent(GlKeysetPagination).props().hasNextPage).toBe(true);
    });

    describe('navigation', () => {
      it('should call visitUrl with correct page when prev is emitted', () => {
        setWindowLocation('?page=2');
        wrapper = createComponent();

        wrapper.findComponent(GlKeysetPagination).vm.$emit('prev');

        expect(visitUrl).toHaveBeenCalledWith('https://localhost/?page=1');
      });

      it('should call visitUrl with correct page when next is emitted', () => {
        setWindowLocation('?page=1');
        wrapper = createComponent();

        wrapper.findComponent(GlKeysetPagination).vm.$emit('next');

        expect(visitUrl).toHaveBeenCalledWith('https://localhost/?page=2');
      });
    });
  });

  describe('Drawer behaviour', () => {
    const findDrawer = () => wrapper.findComponent(AuditEventDetailsDrawer);
    const findTable = () => wrapper.findComponent(GlTable);

    describe('when showDetailsDrawer is false', () => {
      beforeEach(() => {
        wrapper = createComponent({ showDetailsDrawer: false });
      });

      it('does not render the details drawer', () => {
        expect(findDrawer().exists()).toBe(false);
      });

      it('does not open drawer when row is clicked', async () => {
        findTable().vm.$emit('row-clicked', EVENTS[0]);
        await nextTick();

        expect(findDrawer().exists()).toBe(false);
      });

      it('does not set ARIA attributes on rows', () => {
        const rowAttributes = wrapper.vm.tableRowAttributes(EVENTS[0]);

        expect(rowAttributes).toEqual({});
      });
    });

    describe('when showDetailsDrawer is true', () => {
      beforeEach(() => {
        wrapper = createComponent({ showDetailsDrawer: true });
      });

      it('renders the details drawer', () => {
        expect(findDrawer().exists()).toBe(true);
      });

      it('drawer is closed by default', () => {
        expect(findDrawer().props('open')).toBe(false);
      });

      it('drawer has no selected event by default', () => {
        expect(findDrawer().props('event')).toBeNull();
      });

      describe('when a row is clicked', () => {
        beforeEach(async () => {
          findTable().vm.$emit('row-clicked', EVENTS[0]);
          await nextTick();
        });

        it('opens the drawer', () => {
          expect(findDrawer().props('open')).toBe(true);
        });

        it('passes the clicked event to the drawer', () => {
          expect(findDrawer().props('event')).toEqual(EVENTS[0]);
        });
      });

      describe('when drawer emits close', () => {
        beforeEach(async () => {
          findTable().vm.$emit('row-clicked', EVENTS[0]);
          await nextTick();
          findDrawer().vm.$emit('close');
          await nextTick();
        });

        it('closes the drawer', () => {
          expect(findDrawer().props('open')).toBe(false);
        });

        it('clears the selected event', () => {
          expect(findDrawer().props('event')).toBeNull();
        });
      });

      describe('keyboard accessibility', () => {
        it('sets correct ARIA attributes on rows', () => {
          const rowAttributes = wrapper.vm.tableRowAttributes(EVENTS[0]);

          expect(rowAttributes.role).toBe('button');
          expect(rowAttributes.tabindex).toBe('0');
        });

        it('opens drawer when Enter key is pressed on a row', async () => {
          const rowAttributes = wrapper.vm.tableRowAttributes(EVENTS[0]);
          const enterEvent = { key: 'Enter', preventDefault: jest.fn() };

          rowAttributes.onKeydown(enterEvent);
          await nextTick();

          expect(enterEvent.preventDefault).toHaveBeenCalled();
          expect(findDrawer().props('open')).toBe(true);
          expect(findDrawer().props('event')).toEqual(EVENTS[0]);
        });

        it('opens drawer when Space key is pressed on a row', async () => {
          const rowAttributes = wrapper.vm.tableRowAttributes(EVENTS[0]);
          const spaceEvent = { key: ' ', preventDefault: jest.fn() };

          rowAttributes.onKeydown(spaceEvent);
          await nextTick();

          expect(spaceEvent.preventDefault).toHaveBeenCalled();
          expect(findDrawer().props('open')).toBe(true);
          expect(findDrawer().props('event')).toEqual(EVENTS[0]);
        });

        it('does not open drawer for other key presses', async () => {
          const rowAttributes = wrapper.vm.tableRowAttributes(EVENTS[0]);
          const tabEvent = { key: 'Tab', preventDefault: jest.fn() };

          rowAttributes.onKeydown(tabEvent);
          await nextTick();

          expect(tabEvent.preventDefault).not.toHaveBeenCalled();
          expect(findDrawer().props('open')).toBe(false);
        });
      });
    });
  });
});
