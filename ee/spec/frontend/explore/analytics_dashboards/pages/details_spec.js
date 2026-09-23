import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import ExploreAnalyticsDashboardDetailsEE from 'ee/explore/analytics_dashboards/pages/details.vue';
import waitForPromises from 'helpers/wait_for_promises';
import ExploreAnalyticsDashboardDetails from '~/explore/analytics_dashboards/pages/details.vue';
import AnalyzeWithDuoButton from 'ee/explore/analytics_dashboards/components/analyze_with_duo_button.vue';

describe('ExploreAnalyticsDashboardDetailsEE', () => {
  let wrapper;

  const createComponent = ({ routeParams = { slug: '123' }, isSystemDashboard = false } = {}) => {
    wrapper = shallowMountExtended(ExploreAnalyticsDashboardDetailsEE, {
      mocks: { $route: { params: routeParams } },
      stubs: {
        AnalyzeWithDuoButton: stubComponent(AnalyzeWithDuoButton),
        // Render the CE component's #actions slot so the EE Edit button is mounted,
        // forwarding isSystemDashboard exactly as the CE component does.
        ExploreAnalyticsDashboardDetails: stubComponent(ExploreAnalyticsDashboardDetails, {
          template: `<div>
            <slot name="actions" :is-system-dashboard="${isSystemDashboard}"></slot>
            <slot
              name="filter-actions"
              namespace-full-path="dev-group"
              :filters="{ dateRangeOption: '30d' }"
              :panels="[{ title: 'Panel' }]"
              :duo-prompts="['Config prompt']"
              :is-project="false"
              :is-system-dashboard="${isSystemDashboard}"
            ></slot>
          </div>`,
        }),
      },
    });
  };

  const findEditButton = () => wrapper.findComponentByTestId('dashboard-edit-button');

  beforeEach(() => {
    createComponent();
  });

  it('renders the CE dashboard details component', () => {
    expect(wrapper.findComponent(ExploreAnalyticsDashboardDetails).exists()).toBe(true);
  });

  describe('edit button', () => {
    it('renders an Edit button with the pencil icon', () => {
      expect(findEditButton().exists()).toBe(true);
      expect(findEditButton().props('icon')).toBe('pencil');
      expect(findEditButton().text()).toBe('Edit');
    });

    it('links to the edit page for the current dashboard', () => {
      expect(findEditButton().props('to')).toEqual({
        name: 'dashboard-edit',
        params: { slug: '123' },
      });
    });
  });

  describe('analyze with Duo button', () => {
    it('does not render on non-system dashboards', () => {
      expect(wrapper.findComponent(AnalyzeWithDuoButton).exists()).toBe(false);
    });

    describe('on a system dashboard', () => {
      beforeEach(async () => {
        createComponent({ isSystemDashboard: true });
        await waitForPromises();
      });

      it('renders in the filter actions slot with the dashboard context', () => {
        const button = wrapper.findComponent(AnalyzeWithDuoButton);

        expect(button.exists()).toBe(true);
        expect(button.props()).toMatchObject({
          namespaceFullPath: 'dev-group',
          filters: { dateRangeOption: '30d' },
          panels: [{ title: 'Panel' }],
          configPrompts: ['Config prompt'],
          isProject: false,
        });
      });
    });
  });

  describe('when viewing a system dashboard', () => {
    beforeEach(() => {
      createComponent({ isSystemDashboard: true });
    });

    it('does not render the Edit button', () => {
      expect(findEditButton().exists()).toBe(false);
    });
  });
});
