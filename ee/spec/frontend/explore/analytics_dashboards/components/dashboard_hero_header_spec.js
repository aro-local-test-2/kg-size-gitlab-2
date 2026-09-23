import { GlBadge, GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DashboardHeroHeader from 'ee/explore/analytics_dashboards/components/dashboard_hero_header.vue';

describe('DashboardHeroHeader', () => {
  let wrapper;

  const findBadge = () => wrapper.findComponent(GlBadge);
  const findHeading = () => wrapper.find('h1');
  const findBackground = () => wrapper.findByTestId('dashboard-hero-header-background');
  const findIllustration = () => wrapper.findByTestId('dashboard-hero-header-illustration');
  const findHeader = () => wrapper.findByTestId('dashboard-hero-header');

  const createComponent = () => {
    wrapper = shallowMountExtended(DashboardHeroHeader);
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders the GitLab Analytics badge with the tanuki icon', () => {
    expect(findBadge().props('icon')).toBe('tanuki');
    expect(findBadge().text()).toBe('GitLab Analytics');
  });

  it('renders the page title as a level one heading', () => {
    expect(findHeading().text()).toBe('Analytics dashboards');
  });

  it('renders the page description', () => {
    expect(wrapper.text()).toContain('Keep your teams aligned around the metrics that matter most');
  });

  it('renders full-bleed with only a bottom divider instead of a bordered box', () => {
    expect(findHeader().classes()).toContain('gl-border-b');
    expect(findHeader().classes()).not.toContain('gl-border');
    expect(findHeader().classes()).not.toContain('gl-rounded-lg');
  });

  it('renders a decorative background hidden from screen readers', () => {
    expect(findBackground().attributes('aria-hidden')).toBe('true');
  });

  it('renders the wave illustration hidden from screen readers', () => {
    expect(findIllustration().attributes('aria-hidden')).toBe('true');
    expect(findIllustration().attributes('focusable')).toBe('false');
  });

  it('hides the wave illustration below the @md container width', () => {
    expect(findIllustration().classes()).toEqual(expect.arrayContaining(['@max-md:gl-hidden']));
  });

  it('draws a solid and a dashed trend line with dots on each', () => {
    const strokedPaths = findIllustration()
      .findAll('path')
      .wrappers.filter((path) => path.attributes('stroke') === 'currentColor');

    expect(strokedPaths).toHaveLength(2);
    expect(strokedPaths.filter((path) => path.attributes('stroke-dasharray'))).toHaveLength(1);
    expect(findIllustration().findAll('circle').length).toBeGreaterThanOrEqual(4);
  });

  it('does not render any action buttons', () => {
    expect(wrapper.findComponent(GlButton).exists()).toBe(false);
    expect(findHeader().find('button').exists()).toBe(false);
  });
});
