<script>
import { debounce } from 'lodash-es';
import { GlBadge, GlButton, GlResizeObserverDirective } from '@gitlab/ui';
import { __, n__, s__, sprintf } from '~/locale';

const LINK_TYPE_SOURCE = 'SOURCE';
const LINK_TYPE_CREATED = 'CREATED';
const LINK_TYPE_TRIGGERED = 'TRIGGERED';

const DEFAULT_WORK_ITEM_ICON = 'work-item-issue';
const MERGE_REQUEST_ICON = 'git-merge';
const NOTE_ICON = 'comment';

// Room reserved at the end of the first badge row for the "+N more" button
const MORE_BUTTON_RESERVE_PX = 80;
const MEASURE_DEBOUNCE_MS = 100;

export default {
  name: 'AgentFlowLinkedItems',
  components: {
    GlBadge,
    GlButton,
  },
  directives: {
    GlResizeObserver: GlResizeObserverDirective,
  },
  inject: {
    isSidePanelView: { default: false },
  },
  props: {
    workItemLinks: {
      type: Array,
      required: false,
      default: () => [],
    },
    mergeRequestLinks: {
      type: Array,
      required: false,
      default: () => [],
    },
    noteLinks: {
      type: Array,
      required: false,
      default: () => [],
    },
    workItem: {
      type: Object,
      required: false,
      default: null,
    },
    mergeRequest: {
      type: Object,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      expandedRows: {},
      isMeasuring: false,
      firstRowCounts: {},
    };
  },
  computed: {
    sourceItems() {
      const items = [
        ...this.workItemItems(LINK_TYPE_SOURCE),
        ...this.mergeRequestItems(LINK_TYPE_SOURCE),
        ...this.noteItems(LINK_TYPE_TRIGGERED),
      ];

      return items.length ? items : this.legacySourceItems;
    },
    legacySourceItems() {
      const items = [];

      if (this.workItem) {
        items.push({
          id: this.workItem.id,
          icon: DEFAULT_WORK_ITEM_ICON,
          text: `#${this.workItem.iid} ${this.workItem.title}`,
          href: this.workItem.webPath,
        });
      }

      if (this.mergeRequest) {
        items.push({
          id: this.mergeRequest.id,
          icon: MERGE_REQUEST_ICON,
          text: `!${this.mergeRequest.iid} ${this.mergeRequest.title}`,
          href: this.mergeRequest.webPath,
        });
      }

      return items;
    },
    createdItems() {
      return [
        ...this.workItemItems(LINK_TYPE_CREATED),
        ...this.mergeRequestItems(LINK_TYPE_CREATED),
        ...this.noteItems(LINK_TYPE_CREATED),
      ];
    },
    rows() {
      return [
        { label: __('Source'), items: this.sourceItems, id: 'linked-items-source' },
        { label: __('Created'), items: this.createdItems, id: 'linked-items-created' },
      ].filter((row) => row.items.length);
    },
    itemsCount() {
      return this.sourceItems.length + this.createdItems.length;
    },
    itemsCountText() {
      return n__('%d item', '%d items', this.itemsCount);
    },
    hasItems() {
      return this.itemsCount > 0;
    },
  },
  watch: {
    rows() {
      this.measureRows();
    },
  },
  created() {
    this.debouncedMeasureRows = debounce(this.measureRows, MEASURE_DEBOUNCE_MS);
  },
  mounted() {
    this.measureRows();
  },
  beforeDestroy() {
    this.debouncedMeasureRows.cancel();
  },
  methods: {
    workItemItems(linkType) {
      return this.workItemLinks
        .filter((link) => link.linkType === linkType && link.workItem)
        .map(({ workItem }) => ({
          id: workItem.id,
          icon: workItem.workItemType?.iconName || DEFAULT_WORK_ITEM_ICON,
          text: `${workItem.reference} ${workItem.title}`,
          href: workItem.webPath,
        }));
    },
    mergeRequestItems(linkType) {
      return this.mergeRequestLinks
        .filter((link) => link.linkType === linkType && link.mergeRequest)
        .map(({ mergeRequest }) => ({
          id: mergeRequest.id,
          icon: MERGE_REQUEST_ICON,
          text: `${mergeRequest.reference} ${mergeRequest.title}`,
          href: mergeRequest.webPath,
        }));
    },
    noteItems(linkType) {
      return this.noteLinks
        .filter((link) => link.linkType === linkType && link.note)
        .map(({ note }) => ({
          id: note.id,
          icon: NOTE_ICON,
          text: this.noteText(note),
          href: note.url,
        }));
    },
    noteText(note) {
      const reference = note.discussion?.noteable?.reference;

      return reference
        ? sprintf(s__('DuoAgentsPlatform|Note on %{reference}'), { reference })
        : __('Note');
    },
    hiddenCountFor(row) {
      if (!this.isSidePanelView) return 0;

      const firstRowCount = this.firstRowCounts[row.id];
      if (firstRowCount === undefined) return 0;

      return Math.max(row.items.length - firstRowCount, 0);
    },
    isRowExpanded(row) {
      return Boolean(this.expandedRows[row.id]);
    },
    toggleRow(row) {
      this.expandedRows = { ...this.expandedRows, [row.id]: !this.isRowExpanded(row) };
    },
    isBadgeVisible(row, index) {
      if (!this.isSidePanelView || this.isRowExpanded(row) || this.isMeasuring) return true;

      const firstRowCount = this.firstRowCounts[row.id];
      return firstRowCount === undefined || index < firstRowCount;
    },
    toggleButtonText(row) {
      if (this.isRowExpanded(row)) return __('Show less');

      const count = this.hiddenCountFor(row);
      return sprintf(n__('DuoAgentsPlatform|+%d more', 'DuoAgentsPlatform|+%d more', count), count);
    },
    async measureRows() {
      if (!this.isSidePanelView) return;

      this.isMeasuring = true;
      await this.$nextTick();

      const counts = {};
      this.rows.forEach((row) => {
        const [container] = this.$refs[row.id] || [];
        const badges = container
          ? Array.from(container.children).filter((child) =>
              Object.hasOwn(child.dataset, 'linkedItemBadge'),
            )
          : [];
        if (!badges.length) return;

        const firstRowTop = badges[0].offsetTop;
        let fit = badges.filter((badge) => badge.offsetTop === firstRowTop).length;

        if (fit < badges.length) {
          const containerRight = container.getBoundingClientRect().right;
          while (
            fit > 1 &&
            badges[fit - 1].getBoundingClientRect().right + MORE_BUTTON_RESERVE_PX > containerRight
          ) {
            fit -= 1;
          }
        }

        counts[row.id] = fit;
      });

      this.firstRowCounts = counts;
      this.isMeasuring = false;
    },
  },
};
</script>
<template>
  <section
    v-if="hasItems"
    v-gl-resize-observer="debouncedMeasureRows"
    class="gl-border-b gl-pb-5"
    :class="isSidePanelView ? '-gl-mx-[--container-padding-x] gl-px-[--container-padding-x]' : ''"
    data-testid="linked-items-section"
  >
    <div
      class="gl-flex gl-items-center gl-gap-3"
      :class="isSidePanelView ? 'gl-mb-3 gl-justify-between' : 'gl-mb-4'"
    >
      <component
        :is="isSidePanelView ? 'h4' : 'h2'"
        class="gl-my-0 gl-font-bold"
        :class="isSidePanelView ? 'gl-text-base' : 'gl-heading-2'"
        data-testid="linked-items-heading"
      >
        {{ s__('DuoAgentsPlatform|Linked items') }}
      </component>
      <span
        class="gl-text-subtle"
        :class="isSidePanelView ? 'gl-text-sm' : 'gl-text-base'"
        data-testid="linked-items-count"
      >
        {{ itemsCountText }}
      </span>
    </div>
    <dl class="gl-m-0 gl-flex gl-flex-col gl-gap-3">
      <div v-for="row in rows" :key="row.id" class="gl-flex gl-gap-4">
        <dt
          class="gl-shrink-0 gl-font-normal gl-text-subtle"
          :class="isSidePanelView ? 'gl-min-w-10' : 'gl-min-w-11'"
        >
          {{ row.label }}
        </dt>
        <dd
          :ref="row.id"
          class="gl-m-0 gl-flex gl-min-w-0 gl-flex-wrap gl-items-center gl-gap-2"
          :data-testid="row.id"
        >
          <gl-badge
            v-for="(item, index) in row.items"
            v-show="isBadgeVisible(row, index)"
            :key="item.id"
            :href="item.href"
            :icon="item.icon"
            icon-size="sm"
            data-linked-item-badge
          >
            <span class="gl-truncate">{{ item.text }}</span>
          </gl-badge>
          <div v-if="hiddenCountFor(row)" :class="isRowExpanded(row) ? 'gl-w-full' : 'gl-contents'">
            <gl-button
              variant="link"
              :aria-expanded="isRowExpanded(row) ? 'true' : 'false'"
              :data-testid="`${row.id}-toggle`"
              @click="toggleRow(row)"
            >
              {{ toggleButtonText(row) }}
            </gl-button>
          </div>
        </dd>
      </div>
    </dl>
  </section>
</template>
