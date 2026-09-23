<script>
import { GlButton, GlDrawer, GlToggle } from '@gitlab/ui';
import { __ } from '~/locale';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';

export default {
  name: 'DisplayOptions',
  components: {
    GlButton,
    GlDrawer,
    GlToggle,
  },
  model: {
    prop: 'hiddenColumns',
    event: 'input',
  },
  props: {
    columns: {
      type: Array,
      required: true,
    },
    hiddenColumns: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['input'],
  data() {
    return {
      isDrawerOpen: false,
    };
  },
  DRAWER_Z_INDEX,
  computed: {
    drawerHeaderHeight() {
      return getContentWrapperHeight();
    },
  },
  methods: {
    isVisible(key) {
      return !this.hiddenColumns.includes(key);
    },
    toggleColumn(key) {
      const hiddenColumns = this.isVisible(key)
        ? [...this.hiddenColumns, key]
        : this.hiddenColumns.filter((hiddenKey) => hiddenKey !== key);

      this.$emit('input', hiddenColumns);
    },
  },
  i18n: {
    display: __('Display'),
    columns: __('Columns'),
  },
};
</script>

<template>
  <div>
    <gl-button
      icon="preferences"
      :selected="isDrawerOpen"
      class="gl-shrink-0"
      data-testid="display-options-button"
      @click="isDrawerOpen = !isDrawerOpen"
    >
      {{ $options.i18n.display }}
    </gl-button>

    <gl-drawer
      :open="isDrawerOpen"
      :header-height="drawerHeaderHeight"
      :z-index="$options.DRAWER_Z_INDEX"
      data-testid="display-options-drawer"
      @close="isDrawerOpen = false"
    >
      <template #title>
        <h2 class="gl-my-0 gl-text-size-h2 gl-leading-24">{{ $options.i18n.display }}</h2>
      </template>
      <template #default>
        <div class="gl-border-t gl-pt-5">
          <p class="gl-mb-3 gl-font-bold">{{ $options.i18n.columns }}</p>
          <gl-toggle
            v-for="column in columns"
            :key="column.key"
            :value="isVisible(column.key)"
            label-position="left"
            class="gl-mb-3 gl-justify-between"
            :data-testid="`column-toggle-${column.key}`"
            @change="toggleColumn(column.key)"
          >
            <template #label>
              <span class="gl-font-normal">{{ column.label }}</span>
            </template>
          </gl-toggle>
        </div>
      </template>
    </gl-drawer>
  </div>
</template>
