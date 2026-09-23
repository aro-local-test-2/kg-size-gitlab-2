<script>
import emptyStateIllustrationPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-ai-catalog-md.svg?url';
import { GlLink, GlToastMixin } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import { createAlert } from '~/alert';
import { fetchPolicies } from '~/lib/graphql';
import { helpPagePath } from '~/helpers/help_page_helper';
import { setPageFullWidth, setPageDefaultWidth } from '~/lib/utils/common_utils';
import { parseErrorMessage } from '~/lib/utils/error_message';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import ResourceListsEmptyState from '~/vue_shared/components/resource_lists/empty_state.vue';
import ConfirmActionModal from '~/vue_shared/components/confirm_action_modal.vue';
import ResourceListsLoadingStateList from '~/vue_shared/components/resource_lists/loading_state_list.vue';
import getProjectAiFlowTriggers from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_triggers.query.graphql';
import getProjectServiceAccountRoles from 'ee/ai/duo_agents_platform/graphql/queries/get_project_service_account_roles.query.graphql';
import deleteAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/delete_ai_flow_trigger.mutation.graphql';
import updateAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import FlowTriggersCta from './components/flow_triggers_cta.vue';
import FlowTriggersList from './components/flow_triggers_list.vue';

export default {
  name: 'FlowTriggersIndex',
  components: {
    ConfirmActionModal,
    FlowTriggersCta,
    FlowTriggersList,
    GlLink,
    PageHeading,
    ResourceListsEmptyState,
    ResourceListsLoadingStateList,
  },
  mixins: [glAbilitiesMixin(), GlToastMixin],
  inject: ['projectPath'],
  data() {
    return {
      aiFlowTriggers: [],
      serviceAccountRoles: {},
      idToBeDeleted: null,
      togglingIds: [],
    };
  },
  apollo: {
    aiFlowTriggers: {
      query: getProjectAiFlowTriggers,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          projectPath: this.projectPath,
        };
      },
      update: (data) => data.project?.aiFlowTriggers?.nodes ?? [],
      error(error) {
        createAlert({
          message: error.message || s__('DuoAgentsPlatform|Failed to fetch triggers'),
          captureError: true,
        });
      },
    },
    // Roles are a project membership concern, not a field on the trigger, so they are fetched
    // once here and mapped by service account user ID rather than per card. The lookup is
    // scoped to the rendered triggers' service accounts and skipped entirely when there are
    // none. A failure leaves the map empty, which just hides the role rather than blocking
    // the list.
    serviceAccountRoles: {
      query: getProjectServiceAccountRoles,
      skip() {
        return this.triggerUserIds.length === 0;
      },
      variables() {
        return { fullPath: this.projectPath, ids: this.triggerUserIds };
      },
      update(data) {
        return (data.project?.projectMembers?.nodes ?? []).reduce((acc, member) => {
          if (member.user?.id) {
            acc[member.user.id] = member.accessLevel?.humanAccess ?? null;
          }
          return acc;
        }, {});
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.aiFlowTriggers.loading;
    },
    showEmptyState() {
      return !this.isLoading && this.aiFlowTriggers.length === 0;
    },
    triggerUserIds() {
      return [...new Set(this.aiFlowTriggers.map((trigger) => trigger.user?.id).filter(Boolean))];
    },
    showNewTriggerButton() {
      return (
        this.glAbilities.readAiCatalogThirdPartyFlow || // User could select a configured AI Catalog external agent for the trigger
        this.glAbilities.readAiCatalogFlow || // User could select a configured AI Catalog flow for the trigger
        this.glAbilities.createAiCatalogThirdPartyFlow // User could create new "manual" external agent (one with a configuration path)
      );
    },
  },
  mounted() {
    setPageFullWidth();
  },
  beforeDestroy() {
    setPageDefaultWidth();
  },
  methods: {
    async deleteAiFlowTrigger() {
      try {
        await this.$apollo.mutate({
          mutation: deleteAiFlowTrigger,
          variables: {
            id: this.idToBeDeleted,
          },
          refetchQueries: [getProjectAiFlowTriggers],
        });

        this.$toast.show(s__('DuoAgentsPlatform|Trigger deleted successfully.'));
      } catch (error) {
        createAlert({
          message: error.message || s__('DuoAgentsPlatform|Failed to delete trigger.'),
        });
      } finally {
        this.resetItemIdToBeDeleted();
      }
    },
    resetItemIdToBeDeleted() {
      this.idToBeDeleted = null;
    },
    // The toggle reads `active` straight from the cache, so a failed mutation leaves the
    // cache untouched and the control snaps back on its own.
    async toggleAiFlowTrigger({ id, active }) {
      this.togglingIds = [...this.togglingIds, id];

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateAiFlowTrigger,
          variables: { input: { id, active } },
        });

        const { errors } = data.aiFlowTriggerUpdate;

        if (errors.length > 0) {
          createAlert({ message: errors.join(' ') });
          return;
        }

        this.$toast.show(
          active
            ? s__('DuoAgentsPlatform|Trigger turned on')
            : s__('DuoAgentsPlatform|Trigger turned off'),
        );
      } catch (error) {
        createAlert({
          message: parseErrorMessage(error, s__('DuoAgentsPlatform|Failed to update trigger.')),
          error,
          captureError: true,
        });
      } finally {
        this.togglingIds = this.togglingIds.filter((togglingId) => togglingId !== id);
      }
    },
  },
  emptyStateIllustrationPath,
  triggersDocsPath: helpPagePath('user/duo_agent_platform/triggers/_index'),
};
</script>

<template>
  <!-- minHeight offset accounts for .panel-content's gl-pb-3, so the panel doesn't overflow into scroll -->
  <div
    class="gl-flex gl-flex-col"
    :style="
      showEmptyState
        ? { minHeight: 'calc(var(--panel-content-inner-height) - var(--gl-spacing-scale-3))' }
        : null
    "
  >
    <page-heading :heading="s__('DuoAgentsPlatform|Triggers')">
      <template #description>
        {{
          s__('DuoAgentsPlatform|Triggers run a flow or external agent when defined events occur.')
        }}
        <gl-link :href="$options.triggersDocsPath" target="_blank">{{ __('Learn more') }}</gl-link
        >.
      </template>
      <template v-if="showNewTriggerButton" #actions>
        <flow-triggers-cta />
      </template>
    </page-heading>
    <resource-lists-loading-state-list
      v-if="isLoading"
      :left-lines-count="1"
      :right-lines-count="1"
    />
    <resource-lists-empty-state
      v-else-if="showEmptyState"
      class="gl-my-auto"
      :title="s__('DuoAgentsPlatform|No triggers yet')"
      :description="
        s__(
          'DuoAgentsPlatform|Triggers connect flows or external agents to events in this project. Create a trigger to determine when your flows or external agents are run.',
        )
      "
      :svg-path="$options.emptyStateIllustrationPath"
    >
      <template v-if="showNewTriggerButton" #actions>
        <slot name="actions">
          <flow-triggers-cta />
        </slot>
      </template>
    </resource-lists-empty-state>
    <template v-else>
      <flow-triggers-list
        :ai-flow-triggers="aiFlowTriggers"
        :toggling-ids="togglingIds"
        :service-account-roles="serviceAccountRoles"
        @delete-trigger="(id) => (idToBeDeleted = id)"
        @toggle-trigger="toggleAiFlowTrigger"
      />
      <confirm-action-modal
        v-if="idToBeDeleted"
        modal-id="delete-item-modal"
        variant="danger"
        :title="s__('DuoAgentsPlatform|Delete trigger')"
        :action-fn="deleteAiFlowTrigger"
        :action-text="__('Delete')"
        @close="resetItemIdToBeDeleted"
      >
        {{
          s__(
            'DuoAgentsPlatform|Are you sure you want to delete this trigger? This action cannot be undone.',
          )
        }}
      </confirm-action-modal>
    </template>
  </div>
</template>
