import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoCodeReviewFeedbackLink from 'ee/notes/components/duo_code_review_feedback_link.vue';

describe('DuoCodeReviewFeedbackLink', () => {
  let wrapper;

  const createComponent = ({ glFeatures = {} } = {}) => {
    wrapper = shallowMountExtended(DuoCodeReviewFeedbackLink, {
      provide: { glFeatures },
    });
  };

  const findLink = () => wrapper.findComponent(GlButton);

  it('renders the "Leave feedback" link', () => {
    createComponent();

    expect(findLink().text()).toBe('Leave feedback');
  });

  it('links to the public feedback issue by default', () => {
    createComponent();

    expect(findLink().attributes('href')).toBe(
      'https://gitlab.com/gitlab-org/gitlab/-/issues/517386',
    );
  });

  describe('when duoCodeReviewDeepFlow is enabled', () => {
    it('links to the internal feedback issue', () => {
      createComponent({ glFeatures: { duoCodeReviewDeepFlow: true } });

      expect(findLink().attributes('href')).toBe(
        'https://gitlab.com/gitlab-org/gitlab/-/work_items/628792',
      );
    });
  });
});
