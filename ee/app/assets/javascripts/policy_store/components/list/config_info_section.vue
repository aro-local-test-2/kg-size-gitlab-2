<script>
export default {
  name: 'ConfigInfoSection',
  props: {
    testid: {
      type: String,
      required: true,
    },
    label: {
      type: String,
      required: true,
    },
    emptyLabel: {
      type: String,
      required: true,
    },
    entries: {
      type: Array,
      required: true,
    },
  },
};
</script>

<template>
  <div :data-testid="testid">
    <span class="gl-block gl-text-sm gl-font-semibold">{{ label }}</span>
    <p v-if="!entries.length" class="gl-mb-0 gl-text-sm gl-text-subtle">
      {{ emptyLabel }}
    </p>
    <ul v-else class="gl-mb-0 gl-list-none gl-pl-0">
      <li v-for="entry in entries" :key="entry.id" class="gl-mt-1 gl-text-sm">
        <span class="gl-font-semibold">{{ entry.label }}</span>
        <span v-if="entry.description" class="gl-text-subtle">— {{ entry.description }}</span>
        <dl v-if="entry.configItems?.length" class="gl-mb-0 gl-ml-4 gl-mt-1">
          <div v-for="item in entry.configItems" :key="item.key" class="gl-text-xs">
            <dt class="gl-inline gl-font-semibold gl-text-subtle">{{ item.label }}:</dt>
            <dd class="gl-mb-0 gl-ml-1 gl-inline">
              <code v-if="item.code">{{ item.value }}</code>
              <template v-else>{{ item.value }}</template>
            </dd>
          </div>
        </dl>
      </li>
    </ul>
  </div>
</template>
