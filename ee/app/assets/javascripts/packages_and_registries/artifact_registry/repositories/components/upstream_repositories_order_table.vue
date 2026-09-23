<script>
import {
  GlBadge,
  GlButton,
  GlButtonGroup,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlTable,
  GlTooltipDirective,
} from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import {
  REPOSITORY_EDIT_ROUTE_NAME,
  REPOSITORY_KIND_LABELS,
  UPSTREAM_REPOSITORIES_ORDER_TABLE_FIELDS,
} from '../../constants';
import { humanSize } from '../../utils';

export default {
  name: 'ArtifactRegistryUpstreamRepositoriesOrderTable',
  components: {
    GlBadge,
    GlButton,
    GlButtonGroup,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlTable,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    sources: {
      type: Array,
      required: true,
    },
  },
  emits: ['move', 'remove'],
  computed: {
    lastIndex() {
      return this.sources.length - 1;
    },
    hasJumps() {
      return this.sources.length > 1;
    },
  },
  methods: {
    kindLabel(kind) {
      return REPOSITORY_KIND_LABELS[kind] || kind;
    },
    sizeLabel(sizeBytes) {
      return humanSize(sizeBytes);
    },
    moveUpLabel(name) {
      return sprintf(s__('ArtifactRegistry|Move %{name} up'), { name });
    },
    moveDownLabel(name) {
      return sprintf(s__('ArtifactRegistry|Move %{name} down'), { name });
    },
    editLabel(name) {
      return sprintf(s__('ArtifactRegistry|Edit %{name}'), { name });
    },
    removeLabel(name) {
      return sprintf(s__('ArtifactRegistry|Remove %{name}'), { name });
    },
    menuLabel(name) {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), { name });
    },
    editRoute(name) {
      return { name: REPOSITORY_EDIT_ROUTE_NAME, params: { id: name } };
    },
    moveToStartItem(index) {
      return {
        text: s__('ArtifactRegistry|Move to start of list'),
        action: () => this.move(index, 0),
      };
    },
    moveToEndItem(index) {
      return {
        text: s__('ArtifactRegistry|Move to end of list'),
        action: () => this.move(index, this.lastIndex),
      };
    },
    move(from, to) {
      this.$emit('move', { from, to });
    },
  },
  fields: UPSTREAM_REPOSITORIES_ORDER_TABLE_FIELDS,
};
</script>

<template>
  <gl-table
    :fields="$options.fields"
    :items="sources"
    primary-key="id"
    class="gl-mb-0"
    data-testid="upstream-repositories-order-table"
  >
    <template #cell(position)="{ index, item }">
      <gl-button-group vertical>
        <gl-button
          size="small"
          icon="chevron-up"
          :disabled="index === 0"
          :title="moveUpLabel(item.name)"
          :aria-label="moveUpLabel(item.name)"
          data-testid="move-source-up"
          @click="move(index, index - 1)"
        />
        <gl-button
          size="small"
          icon="chevron-down"
          :disabled="index === lastIndex"
          :title="moveDownLabel(item.name)"
          :aria-label="moveDownLabel(item.name)"
          data-testid="move-source-down"
          @click="move(index, index + 1)"
        />
      </gl-button-group>
    </template>

    <template #cell(name)="{ item }">
      <span class="gl-font-semibold gl-text-default gl-wrap-anywhere" data-testid="source-name">{{
        item.name
      }}</span>
      <span
        v-if="item.url"
        class="gl-block gl-text-sm gl-text-subtle gl-wrap-anywhere"
        data-testid="source-url"
        >{{ item.url }}</span
      >
    </template>

    <template #cell(kind)="{ item }">
      <gl-badge data-testid="source-kind">{{ kindLabel(item.kind) }}</gl-badge>
    </template>

    <template #cell(sizeBytes)="{ item }">
      <span v-if="item.sizeBytes" data-testid="source-size">{{ sizeLabel(item.sizeBytes) }}</span>
    </template>

    <template #cell(actions)="{ index, item }">
      <div class="gl-flex gl-items-center gl-justify-end gl-gap-2">
        <gl-button
          v-gl-tooltip="editLabel(item.name)"
          size="small"
          category="tertiary"
          icon="pencil"
          :aria-label="editLabel(item.name)"
          :to="editRoute(item.name)"
          data-testid="edit-source"
        />
        <gl-button
          v-gl-tooltip="removeLabel(item.name)"
          size="small"
          category="tertiary"
          icon="close"
          :aria-label="removeLabel(item.name)"
          data-testid="remove-source"
          @click="$emit('remove', index)"
        />
        <gl-disclosure-dropdown
          v-if="hasJumps"
          icon="ellipsis_v"
          :toggle-text="menuLabel(item.name)"
          text-sr-only
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="source-actions"
        >
          <gl-disclosure-dropdown-item
            v-if="index > 0"
            :item="moveToStartItem(index)"
            data-testid="move-source-to-start"
          />
          <gl-disclosure-dropdown-item
            v-if="index < lastIndex"
            :item="moveToEndItem(index)"
            data-testid="move-source-to-end"
          />
        </gl-disclosure-dropdown>
      </div>
    </template>
  </gl-table>
</template>
