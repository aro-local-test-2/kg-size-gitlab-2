import { GlAlert } from '@gitlab/ui';
import ExploreDashboardsAlert from 'ee/analytics/analytics_dashboards/components/explore_dashboards_alert.vue';
import UserCalloutDismisser from '~/vue_shared/components/user_callout_dismisser.vue';
import { makeMockUserCalloutDismisser } from 'helpers/mock_user_callout_dismisser';
import { mountExtended } from 'helpers/vue_test_utils_helper';

describe('ExploreDashboardsAlert', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;
  let dismissSpy;

  const exploreDashboardsPath = '/explore/analytics_dashboards';

  const createWrapper = ({ shouldShowCallout = true } = {}) => {
    dismissSpy = jest.fn();

    wrapper = mountExtended(ExploreDashboardsAlert, {
      propsData: {
        exploreDashboardsPath,
      },
      stubs: {
        UserCalloutDismisser: makeMockUserCalloutDismisser({
          dismiss: dismissSpy,
          shouldShowCallout,
        }),
      },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findCalloutDismisser = () => wrapper.findComponent(UserCalloutDismisser);

  describe('default', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('renders the alert', () => {
      expect(findAlert().props('title')).toBe('Try analytics dashboards in Explore');
      expect(findAlert().text()).toContain(
        'The analytics dashboards page is being rebuilt and moved to the Explore page to give you visibility across your entire organization.',
      );
    });

    it('links the call to action to the explore dashboards', () => {
      expect(findAlert().props('primaryButtonText')).toBe('Go to Explore');
      expect(findAlert().props('primaryButtonLink')).toBe(exploreDashboardsPath);
    });

    it('links to the analytics dashboards documentation', () => {
      expect(findAlert().props('secondaryButtonText')).toBe('Learn more');
      expect(findAlert().props('secondaryButtonLink')).toBe(
        '/help/user/analytics/analytics_dashboards',
      );
    });

    it('dismisses the callout when the alert is dismissed', () => {
      expect(findCalloutDismisser().props('featureName')).toBe(
        'explore_analytics_dashboards_promo',
      );

      findAlert().vm.$emit('dismiss');

      expect(dismissSpy).toHaveBeenCalled();
    });
  });

  describe('when the callout was already dismissed', () => {
    beforeEach(() => {
      createWrapper({ shouldShowCallout: false });
    });

    it('does not render the alert', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });
});
