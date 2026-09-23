import DashboardHeroHeader from './dashboard_hero_header.vue';

export default {
  component: DashboardHeroHeader,
  title: 'ee/explore/analytics_dashboards/dashboard_hero_header',
};

export const Default = () => ({
  components: { DashboardHeroHeader },
  template: `<div class="gl-@container"><dashboard-hero-header /></div>`,
});
