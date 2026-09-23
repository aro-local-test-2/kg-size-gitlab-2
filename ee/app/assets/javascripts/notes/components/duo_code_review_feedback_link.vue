<script>
import { GlButton } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';

const FEEDBACK_ISSUE_URL = 'https://gitlab.com/gitlab-org/gitlab/-/issues/517386';
const INTERNAL_FEEDBACK_ISSUE_URL = 'https://gitlab.com/gitlab-org/gitlab/-/work_items/628792';

export default {
  name: 'DuoCodeReviewFeedbackLink',
  components: {
    GlButton,
  },
  mixins: [glFeatureFlagsMixin()],
  computed: {
    feedbackIssueUrl() {
      // Keyed on the viewer, not on the user whose flag selected the flow for this
      // review, so that internal dogfooders always land in the internal thread.
      return this.glFeatures.duoCodeReviewDeepFlow
        ? INTERNAL_FEEDBACK_ISSUE_URL
        : FEEDBACK_ISSUE_URL;
    },
  },
};
</script>

<template>
  <span>
    <span class="gl-mx-2" aria-hidden="true">&middot;</span>
    <gl-button variant="link" :href="feedbackIssueUrl">
      {{ __('Leave feedback') }}
    </gl-button>
  </span>
</template>
