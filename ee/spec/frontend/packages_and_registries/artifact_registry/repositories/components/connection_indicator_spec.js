import { GlBadge } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeDate } from 'helpers/fake_date';
import ConnectionIndicator from 'ee/packages_and_registries/artifact_registry/repositories/components/connection_indicator.vue';
import { getTimeago } from '~/lib/utils/datetime_utility';

const LAST_CHECKED_AT = '2026-07-12T00:00:00Z';

const PROBED_AT = '2026-07-14T00:00:00Z';

const VERDICT_LABELS = {
  HEALTHY: 'Healthy',
  UNHEALTHY: 'Unhealthy',
};

describe('ArtifactRegistryConnectionIndicator', () => {
  let wrapper;

  useFakeDate(2026, 6, 15);

  const timeAgo = (time) => getTimeago().format(time);

  const findIndicator = () => wrapper.findByTestId('connection-indicator');
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findLastVerified = () => wrapper.findByTestId('connection-last-verified');

  const createComponent = ({
    healthStatus = 'HEALTHY',
    lastHealthCheckedAt = LAST_CHECKED_AT,
    inline = false,
  } = {}) => {
    wrapper = mountExtended(ConnectionIndicator, {
      propsData: { healthStatus, lastHealthCheckedAt, inline },
    });
  };

  describe.each`
    healthStatus   | lastHealthCheckedAt | variant      | icon                  | label
    ${'HEALTHY'}   | ${LAST_CHECKED_AT}  | ${'success'} | ${'status-success'}   | ${'Healthy'}
    ${'UNHEALTHY'} | ${LAST_CHECKED_AT}  | ${'danger'}  | ${'status-failed'}    | ${'Unhealthy'}
    ${'UNKNOWN'}   | ${null}             | ${'neutral'} | ${'severity-unknown'} | ${'Unknown'}
  `(
    'on a $healthStatus upstream',
    ({ healthStatus, lastHealthCheckedAt, variant, icon, label }) => {
      beforeEach(() => {
        createComponent({ healthStatus, lastHealthCheckedAt });
      });

      it('names the verdict in words', () => {
        expect(findBadge().text()).toBe(label);
      });

      it('draws the treatment the value carries', () => {
        expect(findBadge().props()).toMatchObject({ variant, icon });
      });
    },
  );

  describe('the last-verified line', () => {
    it.each(['HEALTHY', 'UNHEALTHY'])(
      'renders when the probe that recorded a %s verdict ran',
      (healthStatus) => {
        createComponent({ healthStatus });

        expect(findLastVerified().text()).toMatchInterpolatedText(
          `Last verified: ${timeAgo(LAST_CHECKED_AT)}`,
        );
      },
    );

    it('says the upstream has not been checked when no probe has recorded a time', () => {
      createComponent({ healthStatus: 'UNKNOWN', lastHealthCheckedAt: null });

      expect(findLastVerified().text()).toMatchInterpolatedText('Last verified: not yet checked');
    });
  });

  describe('the accessible name', () => {
    it.each(['HEALTHY', 'UNHEALTHY'])(
      'names the %s verdict and the time it was recorded together',
      (healthStatus) => {
        createComponent({ healthStatus });

        expect(findIndicator().attributes('aria-label')).toBe(
          `${VERDICT_LABELS[healthStatus]}. Last verified: ${timeAgo(LAST_CHECKED_AT)}`,
        );
      },
    );

    it('names the verdict and the absence of a time when no probe has recorded one', () => {
      createComponent({ healthStatus: 'UNKNOWN', lastHealthCheckedAt: null });

      expect(findIndicator().attributes('aria-label')).toBe(
        'Unknown. Last verified: not yet checked',
      );
    });
  });

  it('announces its own changes, being where a probe lands its result', () => {
    createComponent();

    expect(findIndicator().attributes('role')).toBe('status');
  });

  it('replaces the verdict and its time in place rather than rendering a second one', async () => {
    createComponent({ healthStatus: 'HEALTHY' });

    await wrapper.setProps({ healthStatus: 'UNHEALTHY', lastHealthCheckedAt: PROBED_AT });

    expect(wrapper.findAllComponents(GlBadge)).toHaveLength(1);
    expect(findBadge().text()).toBe('Unhealthy');
    expect(findLastVerified().text()).toMatchInterpolatedText(
      `Last verified: ${timeAgo(PROBED_AT)}`,
    );
  });
});
