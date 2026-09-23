import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCard, GlCollapsibleListbox, GlPopover, GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ToolCoverageCard from 'ee/security_inventory/components/tool_coverage_card.vue';
import ToolCoverageChart from 'ee/security_inventory/components/tool_coverage_chart.vue';
import GroupToolCoverageQuery from 'ee/security_inventory/graphql/group_tool_coverage.query.graphql';
import { groupToolCoverageResponse } from '../mock_data';

Vue.use(VueApollo);

describe('ToolCoverageCard', () => {
  let wrapper;

  const fullPath = 'gitlab-org';

  const findCard = () => wrapper.findComponent(GlCard);
  const findChart = () => wrapper.findComponent(ToolCoverageChart);
  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findConfigurationLink = () => wrapper.findByTestId('view-configuration-link');
  const findLearnMoreLink = () => wrapper.findByTestId('learn-more-link');
  const findPopover = () => wrapper.findComponent(GlPopover);

  // The item is the whole row; the row is the toggle button inside it.
  const findLegendItem = (status) => wrapper.findByTestId(`legend-item-${status}`);
  const findLegendRow = (status) => wrapper.findByTestId(`legend-row-${status}`);
  const findEnableScannersLink = (status) =>
    findLegendItem(status).find('[data-testid="enable-scanners-link"]');
  const legendCountFor = (status) =>
    findLegendItem(status).find('[data-testid="legend-count"]').text();
  const legendPercentFor = (status) =>
    findLegendItem(status).find('[data-testid="legend-percent"]').text();

  const createComponent = ({ handler, selection } = {}) => {
    const queryHandler = handler ?? jest.fn().mockResolvedValue(groupToolCoverageResponse);

    wrapper = shallowMountExtended(ToolCoverageCard, {
      apolloProvider: createMockApollo([[GroupToolCoverageQuery, queryHandler]]),
      propsData: { fullPath, ...(selection ? { selection } : {}) },
      stubs: {
        GlCard: stubComponent(GlCard, {
          template:
            '<div><slot name="header"></slot><slot></slot><slot name="footer"></slot></div>',
        }),
      },
    });

    return queryHandler;
  };

  describe('while loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a skeleton loader instead of the chart', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
      expect(findChart().exists()).toBe(false);
    });

    it('disables the scanner listbox', () => {
      expect(findListbox().props('disabled')).toBe(true);
    });
  });

  describe('when the card mounts', () => {
    it('fetches the coverage for the given group', () => {
      const handler = createComponent();

      expect(handler).toHaveBeenCalledWith({ fullPath });
    });
  });

  describe('help popover', () => {
    beforeEach(() => {
      createComponent();
    });

    it('explains what the coverage is based on', () => {
      expect(findPopover().props('title')).toBe('Tool coverage');
      expect(findPopover().text()).toContain(
        'Coverage across all scanners, or for a single scanner, based on the scan status of the most recent pipeline on the default branch.',
      );
    });

    it('links to the scanner coverage documentation', () => {
      expect(findLearnMoreLink().attributes('href')).toBe(
        '/help/user/application_security/security_inventory/_index#scanner-coverage',
      );
    });
  });

  describe('when the query succeeds', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the card and chart', () => {
      expect(findCard().exists()).toBe(true);
      expect(findChart().exists()).toBe(true);
      expect(findSkeletonLoader().exists()).toBe(false);
    });

    it.each`
      status              | percent  | count
      ${'SUCCESS'}        | ${'52%'} | ${'788'}
      ${'FAILED'}         | ${'20%'} | ${'299'}
      ${'STALE'}          | ${'20%'} | ${'306'}
      ${'NOT_CONFIGURED'} | ${'8%'}  | ${'127'}
    `('shows $count ($percent) in the legend for $status', ({ status, percent, count }) => {
      expect(legendPercentFor(status)).toBe(percent);
      expect(legendCountFor(status)).toBe(count);
    });

    it('passes the chart a color variable for each status', () => {
      expect(findChart().props('segments')).toMatchObject([
        { label: 'Enabled', color: 'var(--green-500)' },
        { label: 'Failed', color: 'var(--red-500)' },
        { label: 'Stale', color: 'var(--gl-color-neutral-600)' },
        { label: 'Not enabled', color: 'var(--gl-color-neutral-200)' },
      ]);
    });

    it('includes each scanner and an all scanners option', () => {
      expect(
        findListbox()
          .props('items')
          .map(({ value }) => value),
      ).toEqual([
        'ALL',
        'DEPENDENCY_SCANNING',
        'SAST',
        'SECRET_DETECTION',
        'CONTAINER_SCANNING',
        'DAST',
        'SAST_IAC',
      ]);
    });

    it('links to the group security configuration', () => {
      expect(findConfigurationLink().attributes('href')).toBe(
        '/groups/gitlab-org/-/security/configuration',
      );
    });

    describe('enable scanners link', () => {
      it('links the not-enabled row to the wizard', () => {
        const link = findEnableScannersLink('NOT_CONFIGURED');

        expect(link.text()).toBe('Enable scanners');
        expect(link.attributes('href')).toBe(
          '/groups/gitlab-org/-/security/configuration#/enable_scanners',
        );
      });

      it.each(['SUCCESS', 'FAILED', 'STALE'])(
        'does not link the %s row to the wizard',
        (status) => {
          expect(findEnableScannersLink(status).exists()).toBe(false);
        },
      );

      it('shows on hover', () => {
        expect(findEnableScannersLink('NOT_CONFIGURED').classes()).toEqual(
          expect.arrayContaining([
            'gl-opacity-0',
            'group-hover:gl-opacity-10',
            'focus:gl-opacity-10',
          ]),
        );
        expect(findLegendItem('NOT_CONFIGURED').classes()).toContain('gl-group');
      });
    });

    it('shows legend rows as unpressed without a selection', () => {
      expect(wrapper.findAll('[aria-pressed="true"]')).toHaveLength(0);
    });

    describe('when the scanner listbox selects a scanner', () => {
      beforeEach(() => {
        findListbox().vm.$emit('select', 'DAST');
      });

      it('emits the scanner selection', () => {
        expect(wrapper.emitted('update:selection')).toEqual([[{ scanner: 'DAST', status: null }]]);
      });
    });

    describe('when a legend row is clicked', () => {
      beforeEach(() => {
        findLegendRow('FAILED').trigger('click');
      });

      it('emits a status selection', () => {
        expect(wrapper.emitted('update:selection')).toEqual([
          [{ scanner: 'ALL', status: 'FAILED' }],
        ]);
      });
    });

    describe('when a chart slice is clicked', () => {
      beforeEach(() => {
        findChart().vm.$emit('select-status', 'STALE');
      });

      it('emits a status selection', () => {
        expect(wrapper.emitted('update:selection')).toEqual([
          [{ scanner: 'ALL', status: 'STALE' }],
        ]);
      });
    });

    describe('when a single scanner is selected with no status', () => {
      beforeEach(async () => {
        createComponent({ selection: { scanner: 'DAST', status: null } });
        await waitForPromises();
      });

      it.each`
        status              | percent  | count
        ${'SUCCESS'}        | ${'40%'} | ${'88'}
        ${'FAILED'}         | ${'45%'} | ${'99'}
        ${'STALE'}          | ${'3%'}  | ${'6'}
        ${'NOT_CONFIGURED'} | ${'12%'} | ${'27'}
      `(
        'narrows $status to that scanner, showing $count ($percent)',
        ({ status, percent, count }) => {
          expect(legendPercentFor(status)).toBe(percent);
          expect(legendCountFor(status)).toBe(count);
        },
      );
    });

    describe('when a status is selected', () => {
      beforeEach(async () => {
        createComponent({ selection: { scanner: 'ALL', status: 'FAILED' } });
        await waitForPromises();
      });

      it('sets aria-pressed and styles per selection', () => {
        expect(findLegendRow('FAILED').attributes('aria-pressed')).toBe('true');
        expect(findLegendItem('FAILED').classes()).toContain('gl-bg-feedback-info');
        expect(findLegendItem('FAILED').classes()).not.toContain('hover:gl-bg-strong');

        expect(findLegendRow('SUCCESS').attributes('aria-pressed')).toBe('false');
        expect(findLegendItem('SUCCESS').classes()).not.toContain('gl-bg-feedback-info');
        expect(findLegendItem('SUCCESS').classes()).toContain('hover:gl-bg-strong');
      });

      it('sets isSelected on the matching chart segment', () => {
        expect(findChart().props('segments')).toMatchObject([
          { label: 'Enabled', isSelected: false },
          { label: 'Failed', isSelected: true },
          { label: 'Stale', isSelected: false },
          { label: 'Not enabled', isSelected: false },
        ]);
      });

      describe('when the selected row is clicked again', () => {
        beforeEach(() => {
          findLegendRow('FAILED').trigger('click');
        });

        it('clears the selected status', () => {
          expect(wrapper.emitted('update:selection')).toEqual([[{ scanner: 'ALL', status: null }]]);
        });
      });

      describe('when the scanner changes', () => {
        beforeEach(() => {
          findListbox().vm.$emit('select', 'DAST');
        });

        it('keeps the selected status', () => {
          expect(wrapper.emitted('update:selection')).toEqual([
            [{ scanner: 'DAST', status: 'FAILED' }],
          ]);
        });
      });
    });

    describe('when a legend row is hovered', () => {
      beforeEach(async () => {
        await findLegendRow('FAILED').trigger('mouseenter');
      });

      it('sets isHovered on the hovered segment', () => {
        expect(findChart().props('segments')).toMatchObject([
          { label: 'Enabled', isHovered: false },
          { label: 'Failed', isHovered: true },
          { label: 'Stale', isHovered: false },
          { label: 'Not enabled', isHovered: false },
        ]);
      });

      describe('when the pointer leaves the row', () => {
        beforeEach(async () => {
          await findLegendRow('FAILED').trigger('mouseleave');
        });

        it('clears the hover flag on every segment', () => {
          expect(findChart().props('segments')).toMatchObject([
            { label: 'Enabled', isHovered: false },
            { label: 'Failed', isHovered: false },
            { label: 'Stale', isHovered: false },
            { label: 'Not enabled', isHovered: false },
          ]);
        });
      });
    });

    describe('when the chart reports a hovered slice', () => {
      beforeEach(async () => {
        findChart().vm.$emit('hover-status', 'STALE');
        await nextTick();
      });

      it('sets isHovered on the hovered segment', () => {
        expect(findChart().props('segments')).toMatchObject([
          { label: 'Enabled', isHovered: false },
          { label: 'Failed', isHovered: false },
          { label: 'Stale', isHovered: true },
          { label: 'Not enabled', isHovered: false },
        ]);
      });
    });
  });

  describe('when the group has no analyzer data', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue({
          data: {
            group: {
              ...groupToolCoverageResponse.data.group,
              descendantGroups: { __typename: 'GroupConnection', count: 0 },
              analyzerStatuses: [],
            },
          },
        }),
      });
      await waitForPromises();
    });

    it('renders zeroed counts rather than hiding the card', () => {
      expect(findCard().exists()).toBe(true);
      expect(legendCountFor('SUCCESS')).toBe('0');
      expect(legendPercentFor('SUCCESS')).toBe('0%');
    });
  });

  describe('when the query fails', () => {
    const error = new Error('nope');

    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException').mockImplementation();
      createComponent({
        handler: jest
          .fn()
          .mockRejectedValueOnce(error)
          .mockResolvedValue(groupToolCoverageResponse),
      });
      await waitForPromises();
    });

    it('hides the card', () => {
      expect(findCard().exists()).toBe(false);
    });

    it('calls Sentry with the error', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    describe('when the user navigates to another group and the query succeeds', () => {
      beforeEach(async () => {
        await wrapper.setProps({ fullPath: 'gitlab-org/subgroup' });
        await waitForPromises();
      });

      it('shows the card again', () => {
        expect(findCard().exists()).toBe(true);
      });
    });
  });
});
