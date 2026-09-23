<script>
import { s__, sprintf } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { REPOSITORY_FORMAT_LABELS, UPSTREAM_REPOSITORIES_CAP } from '../../constants';
import UpstreamRepositoriesOrderTable from './upstream_repositories_order_table.vue';
import UpstreamRepositoryPicker from './upstream_repository_picker.vue';

export default {
  name: 'ArtifactRegistryUpstreamRepositoriesSection',
  components: {
    CrudComponent,
    UpstreamRepositoriesOrderTable,
    UpstreamRepositoryPicker,
  },
  props: {
    format: {
      type: String,
      required: true,
    },
    sources: {
      type: Array,
      required: true,
    },
  },
  emits: ['add', 'move', 'remove'],
  data() {
    return {
      announcement: '',
      movedId: null,
      removedIndex: null,
      isPickerOpen: false,
    };
  },
  computed: {
    title() {
      return sprintf(s__('ArtifactRegistry|%{format} repositories'), {
        format: REPOSITORY_FORMAT_LABELS[this.format] ?? this.format,
      });
    },
    counter() {
      return sprintf(s__('ArtifactRegistry|%{count} of %{cap}'), {
        count: this.sources.length,
        cap: UPSTREAM_REPOSITORIES_CAP,
      });
    },
    isEmpty() {
      return this.sources.length === 0;
    },
    isCapReached() {
      return this.sources.length >= UPSTREAM_REPOSITORIES_CAP;
    },
  },
  watch: {
    format() {
      this.$refs.crud.hideForm();
    },
    async sources(next, previous) {
      this.announcement = this.announcementFor(next, previous);

      const { movedId, removedIndex } = this;
      this.movedId = null;
      this.removedIndex = null;

      if (removedIndex !== null && next.length < previous.length) {
        await this.$nextTick();

        this.focusAfterRemove(removedIndex);
        return;
      }

      if (movedId === null || next.length !== previous.length) return;

      const from = previous.findIndex(({ id }) => id === movedId);
      const to = next.findIndex(({ id }) => id === movedId);

      if (from === -1 || to === -1 || from === to) return;

      await this.$nextTick();

      this.focusAfterMove(to, to < from);
    },
  },
  methods: {
    announcementFor(next, previous) {
      if (!next.length) {
        return s__('ArtifactRegistry|All upstream repositories removed. The list is empty.');
      }

      const position = next.findIndex(({ id }) => id === this.movedId);

      if (this.movedId && next.length === previous.length && position !== -1) {
        return sprintf(s__('ArtifactRegistry|%{name} moved to position %{position} of %{total}.'), {
          name: next[position].name,
          position: position + 1,
          total: next.length,
        });
      }

      return sprintf(s__('ArtifactRegistry|Resolution order updated: %{names}.'), {
        names: next.map(({ name }, index) => `${index + 1}. ${name}`).join(', '),
      });
    },
    async closePicker() {
      this.$refs.crud.hideForm();

      await this.$nextTick();

      this.focusTrigger();
    },
    focusTrigger() {
      const toggle = this.$el.querySelector('[data-testid="crud-form-toggle"]');
      const capMessage = this.$el.querySelector(
        '[data-testid="upstream-repositories-cap-reached"]',
      );

      (toggle ?? capMessage)?.focus();
    },
    onPickerConfirm(rows) {
      this.$emit('add', rows);
      this.closePicker();
    },
    onMove({ from, to }) {
      this.movedId = this.sources[from]?.id ?? null;
      this.$emit('move', { from, to });
    },
    onRemove(index) {
      this.movedId = null;
      this.removedIndex = index;
      this.$emit('remove', index);
    },
    focusAfterRemove(index) {
      const removeButtons = this.$el.querySelectorAll('[data-testid="remove-source"]');

      if (!removeButtons.length) {
        this.focusTrigger();
        return;
      }

      removeButtons[Math.min(index, removeButtons.length - 1)].focus();
    },
    focusAfterMove(index, movedUp) {
      const testId = movedUp ? 'move-source-up' : 'move-source-down';

      this.$el.querySelectorAll(`[data-testid="${testId}"]`)[index]?.focus();
    },
  },
};
</script>

<template>
  <div class="gl-mb-5" data-testid="upstream-repositories-section">
    <crud-component
      ref="crud"
      :title="title"
      :count="counter"
      :description="
        s__(
          'ArtifactRegistry|Use the arrow buttons to reorder repositories. Artifacts are resolved from top to bottom.',
        )
      "
      :toggle-text="isCapReached ? null : s__('ArtifactRegistry|Add repository')"
      :body-class="isPickerOpen ? '!gl-p-0' : null"
      @show-form="isPickerOpen = true"
      @hide-form="isPickerOpen = false"
    >
      <template #actions>
        <span v-if="isCapReached" tabindex="-1" data-testid="upstream-repositories-cap-reached">{{
          s__('ArtifactRegistry|Maximum number of upstream repositories reached.')
        }}</span>
      </template>

      <template #form>
        <upstream-repository-picker
          :format="format"
          :excluded-ids="sources.map(({ id }) => id)"
          :list-size="sources.length"
          @confirm="onPickerConfirm"
          @close="closePicker"
        />
      </template>

      <template v-if="isEmpty && !isPickerOpen" #empty>{{
        s__('ArtifactRegistry|No repositories added yet. Select Add repository to add a source.')
      }}</template>

      <template v-if="!isEmpty" #default>
        <upstream-repositories-order-table :sources="sources" @move="onMove" @remove="onRemove" />
      </template>
    </crud-component>

    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="upstream-repositories-announcement"
      >{{ announcement }}</span
    >
  </div>
</template>
