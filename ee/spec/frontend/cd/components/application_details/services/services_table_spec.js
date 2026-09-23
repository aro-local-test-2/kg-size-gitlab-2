import { GlTableLite } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import ServicesTable from 'ee/cd/components/application_details/services/services_table.vue';
import { makeService } from 'ee/cd/../../../../spec/frontend/cd/components/mock_data';

describe('ServicesTable', () => {
  let wrapper;

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findTimeAgo = () => wrapper.findComponent(TimeAgo);
  const findRows = () => wrapper.findAll('tbody tr');

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(ServicesTable, {
      propsData: {
        services: [makeService()],
        ...props,
      },
    });
  };

  const mountComponent = (props = {}) => {
    wrapper = mountExtended(ServicesTable, {
      propsData: {
        services: [makeService()],
        ...props,
      },
    });
  };

  describe('table rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a GlTableLite', () => {
      expect(findTable().exists()).toBe(true);
    });

    it('passes services as items', () => {
      expect(findTable().props('items')).toHaveLength(1);
    });

    it('shows the Service and Deployed columns', () => {
      expect(
        findTable()
          .props('fields')
          .map((f) => f.key),
      ).toEqual(['name', 'lastDeployedAt']);
    });

    it('stacks the table on small viewports', () => {
      expect(findTable().attributes('stacked')).toBe('sm');
    });
  });

  describe('rows (full mount)', () => {
    describe('when the service has been deployed', () => {
      beforeEach(() => {
        mountComponent();
      });

      it('renders the service name', () => {
        expect(findRows().at(0).text()).toContain('api-server');
      });

      it('renders TimeAgo', () => {
        expect(findTimeAgo().props('time')).toBe('2024-06-10T08:00:00Z');
      });
    });

    describe('when the service has never been deployed', () => {
      beforeEach(() => {
        mountComponent({ services: [makeService({ lastDeployedAt: null })] });
      });

      it('hides TimeAgo', () => {
        expect(findTimeAgo().exists()).toBe(false);
      });
    });
  });

  describe('with a selected service', () => {
    beforeEach(() => {
      mountComponent({
        services: [
          makeService({ id: 'gid://gitlab/Cd::Service/10', name: 'api-server' }),
          makeService({ id: 'gid://gitlab/Cd::Service/20', name: 'worker' }),
        ],
        selectedId: 'gid://gitlab/Cd::Service/10',
      });
    });

    it('highlights the selected service row only', () => {
      expect(findRows().at(0).classes()).toContain('gl-bg-blue-50');
      expect(findRows().at(1).classes()).not.toContain('gl-bg-blue-50');
    });
  });
});
