import initExploreAnalyticsDashboards from '~/explore/analytics_dashboards';
import initAnalyticsDashboards from 'ee/analytics/analytics_dashboards';

// Which app mounts is decided by the `consolidate_analytics_dashboards` flag.
// Each init no-ops without its element.
initExploreAnalyticsDashboards();
initAnalyticsDashboards();
