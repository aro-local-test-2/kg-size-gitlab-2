import { shallowMount } from '@vue/test-utils';
import { GlBadge, GlIcon } from '@gitlab/ui';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import ApprovalCount from 'ee/merge_requests/components/approval_count.vue';
import ApprovalCountFOSS from '~/merge_requests/components/approval_count.vue';

let wrapper;

function createComponent(propsData = {}) {
  wrapper = shallowMount(ApprovalCount, {
    propsData,
    directives: {
      GlTooltip: createMockDirective('gl-tooltip'),
    },
  });
}

const findFossApprovalCount = () => wrapper.findComponent(ApprovalCountFOSS);
const findBadge = () => wrapper.findComponent(GlBadge);
const findIcon = () => wrapper.findComponent(GlIcon);
const findButton = () => wrapper.find('button');
const findTooltip = () => {
  const button = findButton();
  if (button.exists()) {
    return getBinding(button.element, 'gl-tooltip');
  }
  return null;
};

describe('Merge request dashboard approval count FOSS component', () => {
  describe('when approvals are not required', () => {
    it('renders approval count FOSS component', () => {
      createComponent({
        mergeRequest: { approvalsRequired: 0 },
      });

      expect(findFossApprovalCount().exists()).toBe(true);
      expect(findFossApprovalCount().props('mergeRequest')).toEqual(
        expect.objectContaining({
          approvalsRequired: 0,
        }),
      );
    });
  });

  describe('when approvals are required', () => {
    it('renders badge when merge request is approved', () => {
      createComponent({
        mergeRequest: { approvalsRequired: 1, approvalsLeft: 1 },
      });

      expect(findBadge().exists()).toBe(true);
    });

    it.each`
      approved | approvalsRequired | approvalsLeft | tooltipTitle
      ${false} | ${1}              | ${1}          | ${'Required approvals (0 of 1 given)'}
      ${false} | ${1}              | ${0}          | ${'Required approvals (1 of 1 given)'}
    `(
      'renders badge with correct tooltip title',
      ({ approved, approvalsRequired, approvalsLeft, tooltipTitle }) => {
        createComponent({
          mergeRequest: { approved, approvalsRequired, approvalsLeft },
        });

        const tooltip = findTooltip();
        expect(tooltip).not.toBeNull();
        expect(tooltip.value).toBe(tooltipTitle);
      },
    );

    it.each`
      approved | approvalsRequired | approvalsLeft | tooltipTitle
      ${false} | ${1}              | ${1}          | ${'0/1'}
      ${false} | ${1}              | ${0}          | ${'1/1'}
      ${true}  | ${1}              | ${0}          | ${'1/1'}
    `(
      'renders badge with correct tooltip title',
      ({ approved, approvalsRequired, approvalsLeft, tooltipTitle }) => {
        createComponent({
          mergeRequest: { approved, approvalsRequired, approvalsLeft },
        });

        expect(findBadge().text()).toBe(tooltipTitle);
      },
    );
  });

  describe('when current user has approved', () => {
    beforeEach(() => {
      gon.current_user_id = 1;
    });

    it('sets icon as approval-solid', () => {
      createComponent({
        mergeRequest: {
          approvalsRequired: 1,
          approved: true,
          approvedBy: { nodes: [{ id: 'gid://gitlab/User/1' }] },
        },
      });

      expect(findBadge().props('icon')).toBe('approval-solid');
    });
  });

  describe('when neutral', () => {
    beforeEach(() => {
      createComponent({
        mergeRequest: { approvalsRequired: 2, approvalsLeft: 1, approved: false },
        neutral: true,
      });
    });

    it('does not render the badge', () => {
      expect(findBadge().exists()).toBe(false);
    });

    it('renders a subtle approval icon and the given-of-required count', () => {
      expect(findIcon().props('name')).toBe('approval');
      expect(findIcon().props('variant')).toBe('subtle');
      expect(findButton().text()).toBe('1 of 2');
    });

    it('passes neutral through to the FOSS component when no approvals are required', () => {
      createComponent({
        mergeRequest: { approvalsRequired: 0, approvedBy: { nodes: [] } },
        neutral: true,
      });

      expect(findFossApprovalCount().props('neutral')).toBe(true);
    });
  });
});
