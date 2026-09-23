<script>
import { GlAlert, GlButton, GlKeysetPagination, GlSprintf } from '@gitlab/ui';
import EMPTY_SVG_URL from '@gitlab/svgs/dist/illustrations/empty-state/empty-ai-catalog-md.svg?url';
import { __ } from '~/locale';
import SafeHtml from '~/vue_shared/directives/safe_html';
import ConfirmActionModal from '~/vue_shared/components/confirm_action_modal.vue';
import ResourceListsEmptyState from '~/vue_shared/components/resource_lists/empty_state.vue';
import AiCatalogListItem from './ai_catalog_list_item.vue';
import AiCatalogListSkeleton from './ai_catalog_list_skeleton.vue';

export default {
  name: 'AiCatalogList',
  components: {
    GlAlert,
    AiCatalogListItem,
    AiCatalogListSkeleton,
    ConfirmActionModal,
    GlButton,
    GlKeysetPagination,
    GlSprintf,
    ResourceListsEmptyState,
  },
  directives: {
    SafeHtml,
  },
  props: {
    items: {
      type: Array,
      required: true,
    },
    pageInfo: {
      type: Object,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    itemTypeConfig: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    disableConfirmTitle: {
      type: String,
      required: false,
      default: undefined,
    },
    disableConfirmMessage: {
      type: String,
      required: false,
      default: undefined,
    },
    disabledItemTypeMessages: {
      type: Array,
      required: false,
      default: () => [],
    },
    disableFn: {
      type: Function,
      required: false,
      default: undefined,
    },
    search: {
      type: String,
      required: false,
      default: '',
    },
    emptyStateTitle: {
      type: String,
      required: true,
    },
    emptyStateDescription: {
      type: String,
      required: false,
      default: null,
    },
    emptyStateButtonHref: {
      type: String,
      required: false,
      default: null,
    },
    emptyStateButtonText: {
      type: String,
      required: false,
      default: null,
    },
    emptyStateButtonTrackingLabel: {
      type: String,
      required: false,
      default: null,
    },
    emptyStatePrimaryButtonText: {
      type: String,
      required: false,
      default: null,
    },
    emptyStatePrimaryButtonHref: {
      type: String,
      required: false,
      default: null,
    },
    emptyStatePrimaryButtonTrackingLabel: {
      type: String,
      required: false,
      default: null,
    },
    emptyStateTrackingEvent: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['empty-state-click', 'next-page', 'prev-page'],
  data() {
    return {
      itemToDisable: null,
    };
  },
  computed: {
    hasActionItems() {
      return Boolean(this.itemTypeConfig.disableActionItem || this.itemTypeConfig.actionItems);
    },
    disableActionText() {
      return this.itemTypeConfig.disableActionItem?.text || __('Disable');
    },
    hasPrimaryButton() {
      return Boolean(this.emptyStatePrimaryButtonText);
    },
    exploreButtonVariant() {
      return this.hasPrimaryButton ? 'default' : 'confirm';
    },
  },
  methods: {
    async disableItem() {
      await this.disableFn?.(this.itemToDisable);

      this.itemToDisable = null;
    },
  },
  EMPTY_SVG_URL,
};
</script>

<template>
  <!--
    Set typography explicitly: this list renders both inside GlTabs and outside it
    (Explore page), so it can't rely on inheriting line-height and font-size from
    whatever container it's placed in.
  -->
  <div class="gl-text-base gl-leading-normal gl-text-default">
    <template v-if="disabledItemTypeMessages.length > 0">
      <gl-alert
        v-for="message in disabledItemTypeMessages"
        :key="message"
        data-testid="disabled-type-alert"
        class="gl-my-5"
        :dismissible="false"
      >
        <span v-safe-html="message"></span>
      </gl-alert>
    </template>

    <ai-catalog-list-skeleton v-if="isLoading" :show-right-element="hasActionItems" />

    <template v-else-if="items.length > 0">
      <ul class="gl-list-none gl-p-0">
        <ai-catalog-list-item
          v-for="item in items"
          :key="item.id"
          :item="item"
          :item-type-config="itemTypeConfig"
          @disable="itemToDisable = item"
        />
      </ul>

      <gl-keyset-pagination
        v-bind="pageInfo"
        class="gl-mt-5 gl-flex gl-justify-center"
        @prev="$emit('prev-page')"
        @next="$emit('next-page')"
      />

      <confirm-action-modal
        v-if="itemToDisable"
        modal-id="disable-item-modal"
        variant="danger"
        :title="disableConfirmTitle"
        :action-fn="disableItem"
        :action-text="disableActionText"
        @close="itemToDisable = null"
      >
        <gl-sprintf :message="disableConfirmMessage">
          <template #name>
            <strong class="gl-wrap-anywhere">{{ itemToDisable.name }}</strong>
          </template>
        </gl-sprintf>
      </confirm-action-modal>
    </template>

    <template v-else>
      <slot name="empty-state">
        <resource-lists-empty-state
          :title="emptyStateTitle"
          :description="emptyStateDescription"
          :svg-path="$options.EMPTY_SVG_URL"
          :search="search"
        >
          <template
            v-if="emptyStatePrimaryButtonText || emptyStateButtonHref || emptyStateButtonText"
            #actions
          >
            <div class="gl-flex gl-justify-center gl-gap-3">
              <gl-button
                v-if="emptyStatePrimaryButtonText"
                variant="confirm"
                :href="emptyStatePrimaryButtonHref"
                :data-event-tracking="
                  emptyStatePrimaryButtonTrackingLabel && emptyStateTrackingEvent
                "
                :data-event-label="emptyStatePrimaryButtonTrackingLabel"
                data-testid="empty-state-primary-action"
              >
                {{ emptyStatePrimaryButtonText }}
              </gl-button>
              <gl-button
                v-if="emptyStateButtonHref"
                :variant="exploreButtonVariant"
                :href="emptyStateButtonHref"
                :data-event-tracking="emptyStateButtonTrackingLabel && emptyStateTrackingEvent"
                :data-event-label="emptyStateButtonTrackingLabel"
                data-testid="empty-state-action"
              >
                {{ emptyStateButtonText }}
              </gl-button>
              <gl-button
                v-else-if="emptyStateButtonText"
                :variant="exploreButtonVariant"
                :data-event-tracking="emptyStateButtonTrackingLabel && emptyStateTrackingEvent"
                :data-event-label="emptyStateButtonTrackingLabel"
                data-testid="empty-state-action"
                @click="$emit('empty-state-click')"
              >
                {{ emptyStateButtonText }}
              </gl-button>
            </div>
          </template>
        </resource-lists-empty-state>
      </slot>
    </template>
  </div>
</template>
