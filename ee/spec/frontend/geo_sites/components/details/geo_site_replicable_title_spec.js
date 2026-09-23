import { GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GeoSiteReplicableTitle from 'ee/geo_sites/components/details/geo_site_replicable_title.vue';

describe('GeoSiteReplicableTitle', () => {
  let wrapper;

  const createComponent = (props) => {
    wrapper = shallowMountExtended(GeoSiteReplicableTitle, {
      propsData: {
        ...props,
      },
    });
  };

  const findLink = () => wrapper.findComponent(GlLink);

  describe('when the item has a replication view', () => {
    beforeEach(() => {
      createComponent({ item: { titlePlural: 'Wikis', replicationView: '/replication/wikis' } });
    });

    it('renders a link to the replication view', () => {
      expect(findLink().text()).toBe('Wikis');
      expect(findLink().attributes('href')).toBe('/replication/wikis');
    });
  });

  describe('when the item has no replication view', () => {
    beforeEach(() => {
      createComponent({ item: { titlePlural: 'Wikis', replicationView: null } });
    });

    it('renders the plain title', () => {
      expect(wrapper.text()).toBe('Wikis');
      expect(findLink().exists()).toBe(false);
    });
  });
});
