import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FunctionalVerificationStatusBadge from 'ee/ai/settings/components/functional_verifications/status_badge.vue';
import { FUNCTIONAL_VERIFICATION_STATUS } from 'ee/ai/settings/components/functional_verifications/constants';

describe('FunctionalVerificationStatusBadge', () => {
  let wrapper;

  const findBadge = () => wrapper.findComponent(GlBadge);

  const createComponent = (status) => {
    wrapper = shallowMountExtended(FunctionalVerificationStatusBadge, {
      propsData: { status },
    });
  };

  it.each`
    status                                    | variant      | icon                     | text
    ${FUNCTIONAL_VERIFICATION_STATUS.RUNNING} | ${'info'}    | ${'status-running'}      | ${'Running'}
    ${FUNCTIONAL_VERIFICATION_STATUS.PASSED}  | ${'success'} | ${'check-circle-filled'} | ${'Passed'}
    ${FUNCTIONAL_VERIFICATION_STATUS.FAILED}  | ${'danger'}  | ${'error'}               | ${'Failed'}
    ${FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN} | ${'neutral'} | ${'dash-circle'}         | ${'Not run'}
  `(
    'renders variant $variant, icon $icon, and text "$text" for status $status',
    ({ status, variant, icon, text }) => {
      createComponent(status);

      expect(findBadge().props()).toMatchObject({ variant, icon });
      expect(findBadge().text()).toBe(text);
    },
  );

  it('has a status role for accessibility', () => {
    createComponent(FUNCTIONAL_VERIFICATION_STATUS.PASSED);

    expect(wrapper.findByTestId('functional-verification-status-badge').attributes('role')).toBe(
      'status',
    );
  });

  it('does not render a badge for an unrecognized status', () => {
    createComponent('UNKNOWN');

    expect(findBadge().exists()).toBe(false);
  });
});
