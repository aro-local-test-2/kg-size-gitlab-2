<script>
import { GlDisclosureDropdown, GlSprintf } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { n__, s__ } from '~/locale';
import ProjectAvatar from '~/vue_shared/components/project_avatar.vue';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';

export default {
  name: 'ApplicationCard',
  components: {
    GlDisclosureDropdown,
    GlSprintf,
    ProjectAvatar,
    TimeAgo,
  },
  props: {
    application: {
      type: Object,
      required: true,
    },
    isGridView: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['manage-access'],
  computed: {
    dropdownItems() {
      return [
        {
          text: s__('ContinuousDeployment|Manage access'),
          action: () => {
            this.$emit('manage-access');
          },
        },
      ];
    },
    servicesText() {
      return n__(
        'ContinuousDeployment|%d service',
        'ContinuousDeployment|%d services',
        this.application.services.count,
      );
    },
    applicationRoute() {
      return {
        name: 'applications_show_route',
        params: { id: String(getIdFromGraphQLId(this.application.id)) },
      };
    },
  },
};
</script>

<template>
  <div
    class="gl-min-h-26 gl-rounded-lg gl-border-1 gl-border-solid gl-border-subtle"
    data-testid="application-card"
  >
    <div
      class="gl-flex gl-items-center gl-gap-3 gl-p-4"
      :class="{ 'gl-border-b': isGridView, 'gl-border-subtle': isGridView }"
    >
      <project-avatar :project-name="application.name" :size="24" />
      <h2 class="gl-m-0 gl-truncate gl-text-base" :title="application.name">
        <router-link
          :to="applicationRoute"
          class="gl-text-default hover:gl-no-underline"
          data-testid="application-card-link"
          >{{ application.name }}</router-link
        >
      </h2>
      <gl-disclosure-dropdown
        class="gl-ml-auto"
        category="tertiary"
        icon="ellipsis_v"
        :items="dropdownItems"
        no-caret
        text-sr-only
        :toggle-text="__('More actions')"
      />
    </div>
    <div class="gl-p-4">
      <div class="gl-text-sm gl-text-secondary">
        {{ servicesText }}
        <template v-if="application.lastDeployedAt">
          &middot;
          <gl-sprintf :message="s__('ContinuousDeployment|Last deployed %{time}')">
            <template #time><time-ago :time="application.lastDeployedAt" /></template>
          </gl-sprintf>
        </template>
      </div>
    </div>
  </div>
</template>
