import { GlDrawer } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AuditEventDetailsDrawer from 'ee/audit_events/components/audit_event_details_drawer.vue';

describe('AuditEventDetailsDrawer', () => {
  let wrapper;

  const mockEventWithDetails = {
    id: 1,
    action: 'Signed in with STANDARD authentication',
    details: {
      custom_message: 'User signed in',
      author_name: 'Test User',
      target_id: 123,
      with: 'standard',
      add: ['admin', 'developer'],
      allow_force_push: true,
      empty_array: [],
      null_value: null,
      nested_object: { key: 'value' },
    },
  };

  const mockEventWithoutDetails = {
    id: 2,
    action: 'Created project',
    details: {},
  };

  const createComponent = ({ event = mockEventWithDetails, open = true } = {}) => {
    wrapper = shallowMountExtended(AuditEventDetailsDrawer, {
      propsData: {
        event,
        open,
      },
    });
  };

  const findDrawer = () => wrapper.findComponent(GlDrawer);
  const findTitle = () => wrapper.findByTestId('audit-event-drawer-title');
  const findContent = () => wrapper.findByTestId('audit-event-drawer-content');
  const findAction = () => wrapper.findByTestId('audit-event-drawer-action');
  const findDetailItems = () => wrapper.findAllByTestId('audit-event-detail-item');
  const findNoDetailsMessage = () => wrapper.findByTestId('audit-event-no-details');

  describe('drawer behavior', () => {
    it('renders the drawer', () => {
      createComponent();

      expect(findDrawer().exists()).toBe(true);
    });

    it('passes open prop to drawer', () => {
      createComponent({ open: true });

      expect(findDrawer().props('open')).toBe(true);
    });

    it('emits close event when drawer closes', () => {
      createComponent();

      findDrawer().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('when event is provided', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the title', () => {
      expect(findTitle().text()).toBe('Audit event details');
    });

    it('renders the action', () => {
      expect(findAction().text()).toBe('Signed in with STANDARD authentication');
    });

    it('renders detail items for each key in details', () => {
      const detailItems = findDetailItems();

      expect(detailItems).toHaveLength(Object.keys(mockEventWithDetails.details).length);
    });

    it('humanizes the detail keys', () => {
      const firstItem = findDetailItems().at(0);

      expect(firstItem.text()).toContain('Custom message');
    });
  });

  describe('value formatting', () => {
    beforeEach(() => {
      createComponent();
    });

    it('formats string values correctly', () => {
      const content = findContent().text();

      expect(content).toContain('User signed in');
    });

    it('formats boolean true as Yes', () => {
      const content = findContent().text();

      expect(content).toContain('Yes');
    });

    it('formats arrays as comma-separated values', () => {
      const content = findContent().text();

      expect(content).toContain('admin, developer');
    });

    it('formats empty arrays as dash', () => {
      const content = findContent().text();

      expect(content).toContain('-');
    });

    it('formats null values as dash', () => {
      const detailItems = findDetailItems();
      const nullItem = detailItems.wrappers.find((item) => item.text().includes('Null value'));

      expect(nullItem.text()).toContain('-');
    });

    it('formats objects as JSON strings', () => {
      const content = findContent().text();

      expect(content).toContain('{"key":"value"}');
    });
  });

  describe('when event has no details', () => {
    beforeEach(() => {
      createComponent({ event: mockEventWithoutDetails });
    });

    it('shows no details message', () => {
      expect(findNoDetailsMessage().exists()).toBe(true);
      expect(findNoDetailsMessage().text()).toBe('No additional details available for this event.');
    });

    it('does not render detail items', () => {
      expect(findDetailItems()).toHaveLength(0);
    });
  });

  describe('when event is null', () => {
    beforeEach(() => {
      createComponent({ event: null });
    });

    it('does not render content', () => {
      expect(findContent().exists()).toBe(false);
    });
  });

  describe('when event has undefined details property', () => {
    const mockEventWithUndefinedDetails = {
      id: 3,
      action: 'Test action',
    };

    beforeEach(() => {
      createComponent({ event: mockEventWithUndefinedDetails });
    });

    it('shows no details message', () => {
      expect(findNoDetailsMessage().exists()).toBe(true);
    });

    it('does not render detail items', () => {
      expect(findDetailItems()).toHaveLength(0);
    });
  });

  describe('when drawer is closed', () => {
    beforeEach(() => {
      createComponent({ open: false });
    });

    it('passes open=false to drawer', () => {
      expect(findDrawer().props('open')).toBe(false);
    });
  });
});
