<script>
import { GlIcon, GlButton, GlTooltipDirective } from '@gitlab/ui';
import { RULE_TYPE_ANY_APPROVER } from 'ee/approvals/constants';
import { createAlert } from '~/alert';
import { __, sprintf } from '~/locale';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import ReviewerAvatarLink from '~/sidebar/components/reviewers/reviewer_avatar_link.vue';
import setReviewersMutation from '~/merge_requests/components/reviewers/queries/set_reviewers.mutation.graphql';
import suggestedReviewersQuery from '../../queries/suggested_reviewer.query.graphql';

export default {
  name: 'SuggestedReviewers',
  apollo: {
    suggestedReviewers: {
      query: suggestedReviewersQuery,
      variables() {
        return {
          projectPath: this.projectPath,
          iid: this.issuableIid,
        };
      },
      update: (d) => d.project?.mergeRequest?.aiSuggestedReviewers?.nodes || [],
    },
  },
  components: {
    GlIcon,
    GlButton,
    ReviewerAvatarLink,
    HelpPopover,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['projectPath', 'issuableIid'],
  props: {
    canUpdate: {
      type: Boolean,
      required: true,
    },
  },
  data() {
    return {
      suggestedReviewers: [],
      loadingUserIds: [],
    };
  },
  computed: {
    groupedSuggestedReviewers() {
      const groups = new Map();

      this.suggestedReviewers.forEach((suggested) => {
        const id = suggested.approvalRule?.id || 'no-rule';

        if (!groups.has(id)) {
          groups.set(id, { id, approvalRule: suggested.approvalRule, reviewers: [suggested] });
        } else {
          groups.get(id).reviewers.push(suggested);
        }
      });

      return [...groups.values()].sort((a, b) => Number(!a.approvalRule) - Number(!b.approvalRule));
    },
  },
  methods: {
    ruleName({ type, name }) {
      return type.toLowerCase() === RULE_TYPE_ANY_APPROVER ? __('Any eligible user') : name;
    },
    async addSuggestedReviewer(user) {
      this.loadingUserIds = [...this.loadingUserIds, user.id];

      try {
        await this.$apollo.mutate({
          mutation: setReviewersMutation,
          variables: {
            reviewerUsernames: [user.username],
            projectPath: this.projectPath,
            iid: this.issuableIid,
            operationMode: 'APPEND',
          },
        });

        this.$apollo.queries.suggestedReviewers.refetch();
      } catch (error) {
        createAlert({
          message: sprintf(__('Could not add %{name} as a reviewer. Try again later.'), {
            name: user.name,
          }),
          error,
          captureError: true,
        });
      } finally {
        this.loadingUserIds = this.loadingUserIds.filter((id) => id !== user.id);
      }
    },
    addButtonAriaLabel(user) {
      return sprintf(__('Add %{name} as a reviewer'), {
        name: user.name,
      });
    },
  },
};
</script>

<template>
  <div v-if="suggestedReviewers.length" class="gl-mr-2">
    <div class="gl-mb-3 gl-mt-5 gl-flex gl-items-center gl-gap-3 gl-font-bold gl-leading-20">
      <gl-icon name="tanuki-ai" />
      {{ __('Recommended') }}
    </div>
    <div
      v-for="(group, index) in groupedSuggestedReviewers"
      :key="group.id"
      :class="{
        'gl-mb-4': index !== groupedSuggestedReviewers.length - 1,
      }"
      class="gl-grid gl-items-center gl-gap-3"
      data-testid="reviewer"
    >
      <span class="gl-break-all gl-text-sm gl-font-semibold gl-text-subtle">
        <template v-if="group.approvalRule">
          {{ ruleName(group.approvalRule) }}
        </template>
        <template v-else-if="groupedSuggestedReviewers.length > 1">
          {{ __('No approval rule') }}
        </template>
      </span>
      <div
        v-for="reviewer in group.reviewers"
        :key="reviewer.user.id"
        class="reviewer-grid gl-grid gl-items-center"
      >
        <reviewer-avatar-link :user="reviewer.user" class="gl-break-anywhere">
          <div class="gl-ml-3 gl-grid gl-items-center gl-leading-normal">
            {{ reviewer.user.name }}
          </div>
        </reviewer-avatar-link>
        <help-popover :aria-label="__('Reason for recommended reviewer')" class="gl-flex">
          {{ reviewer.reason }}
        </help-popover>
        <gl-button
          v-if="canUpdate"
          v-gl-tooltip.left
          :title="__('Add reviewer')"
          :aria-label="addButtonAriaLabel(reviewer.user)"
          class="gl-ml-2 !gl-text-subtle"
          size="small"
          icon="plus"
          variant="link"
          :loading="loadingUserIds.includes(reviewer.user.id)"
          @click="addSuggestedReviewer(reviewer.user)"
        />
      </div>
    </div>
  </div>
</template>
