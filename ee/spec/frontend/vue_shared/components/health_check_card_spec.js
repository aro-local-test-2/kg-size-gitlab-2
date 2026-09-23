import { GlAnimatedChevronRightDownIcon, GlCollapse, GlExperimentBadge } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { parseBoolean } from '~/lib/utils/common_utils';
import HealthCheckCard from 'ee/vue_shared/components/health_check_card.vue';

describe('HealthCheckCard', () => {
  let wrapper;

  const findGlCollapse = () => wrapper.findComponent(GlCollapse);
  const findExpandButton = () => wrapper.findComponentByTestId('health-check-card-expand-button');
  const findExpandIcon = () => wrapper.findComponent(GlAnimatedChevronRightDownIcon);
  const findIcon = () => wrapper.findComponentByTestId('health-check-card-icon');
  const findTitle = () => wrapper.findByTestId('health-check-card-title');
  const findExpandText = () => wrapper.findByTestId('health-check-card-expand-text');

  const createComponent = ({ props = {}, slots = {} } = {}) => {
    wrapper = mountExtended(HealthCheckCard, {
      propsData: {
        title: 'Some check',
        icon: 'status-health',
        contentId: 'some-check-results',
        expanded: false,
        ...props,
      },
      slots,
    });
  };

  it('renders the title and icon', () => {
    createComponent({ props: { icon: 'check-circle-filled', iconVariant: 'success' } });

    expect(findTitle().text()).toBe('Some check');
    expect(findIcon().props('name')).toBe('check-circle-filled');
    expect(findIcon().props('variant')).toBe('success');
  });

  it('does not render the icon when icon is not provided', () => {
    createComponent({ props: { icon: null } });

    expect(findIcon().exists()).toBe(false);
  });

  it('mutes the title when titleMuted is true', () => {
    createComponent({ props: { titleMuted: true } });

    expect(findTitle().classes()).toContain('gl-text-subtle');
  });

  it('does not mute the title when titleMuted is false', () => {
    createComponent({ props: { titleMuted: false } });

    expect(findTitle().classes()).not.toContain('gl-text-subtle');
  });

  it('renders the actions slot in the header', () => {
    createComponent({ slots: { actions: '<button data-testid="my-action">Run</button>' } });

    expect(wrapper.findByTestId('my-action').exists()).toBe(true);
  });

  it('renders the expand-text slot and the beta badge', () => {
    createComponent({ slots: { 'expand-text': 'Ready to run' } });

    expect(findExpandText().text()).toBe('Ready to run');
    expect(wrapper.findComponent(GlExperimentBadge).props('type')).toBe('beta');
  });

  it('renders the default slot inside the collapse', () => {
    createComponent({ slots: { default: '<div data-testid="my-body">Body</div>' } });

    expect(findGlCollapse().find('[data-testid="my-body"]').exists()).toBe(true);
  });

  describe('when collapsed', () => {
    beforeEach(() => {
      createComponent({ props: { expanded: false } });
    });

    it('renders the collapse as not visible', () => {
      expect(findGlCollapse().props('visible')).toBe(false);
    });

    it('renders the expand button as collapsed', () => {
      expect(
        findExpandIcon().props('isOn') ?? parseBoolean(findExpandIcon().attributes('is-on')),
      ).toBe(false);
      expect(findExpandButton().attributes('aria-label')).toBe('Show results');
      expect(findExpandButton().attributes('aria-expanded')).toBe('false');
      expect(findExpandButton().attributes('aria-controls')).toBe('some-check-results');
    });

    it('does not render the footer slot', () => {
      createComponent({
        props: { expanded: false },
        slots: { footer: '<div data-testid="my-footer">Footer</div>' },
      });

      expect(wrapper.findByTestId('my-footer').exists()).toBe(false);
    });
  });

  describe('when expanded', () => {
    beforeEach(() => {
      createComponent({ props: { expanded: true } });
    });

    it('renders the collapse as visible', () => {
      expect(findGlCollapse().props('visible')).toBe(true);
    });

    it('renders the expand button as expanded', () => {
      expect(
        findExpandIcon().props('isOn') ?? parseBoolean(findExpandIcon().attributes('is-on')),
      ).toBe(true);
      expect(findExpandButton().attributes('aria-label')).toBe('Hide results');
    });

    it('renders the footer slot', () => {
      createComponent({
        props: { expanded: true },
        slots: { footer: '<div data-testid="my-footer">Footer</div>' },
      });

      expect(wrapper.findByTestId('my-footer').exists()).toBe(true);
    });
  });

  it('emits toggle when the expand button is clicked', async () => {
    createComponent();

    await findExpandButton().trigger('click');

    expect(wrapper.emitted('toggle')).toHaveLength(1);
  });

  it('does not disable the expand button by default', () => {
    createComponent();

    expect(findExpandButton().props('disabled')).toBe(false);
  });

  it('disables the expand button when expandDisabled is true', () => {
    createComponent({ props: { expandDisabled: true } });

    expect(findExpandButton().props('disabled')).toBe(true);
  });
});
