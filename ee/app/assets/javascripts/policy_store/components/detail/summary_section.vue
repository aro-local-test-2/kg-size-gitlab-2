<script>
import { GlIcon } from '@gitlab/ui';
import { s__ } from '~/locale';

export default {
  name: 'PolicySummarySection',
  components: {
    GlIcon,
  },
  i18n: {
    noneAdded: s__('PolicyStore|None added'),
  },
  props: {
    label: {
      type: String,
      required: true,
    },
    entries: {
      type: Array,
      required: false,
      default: () => [],
    },
    testid: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <section
    class="gl-border gl-rounded-lg gl-border-default gl-p-5"
    :data-testid="`${testid}-section`"
  >
    <h2 class="gl-heading-4 gl-mb-4">{{ label }}</h2>
    <!-- The slot lets sections with bespoke content (like the scope summary)
         reuse the card chrome without faking catalog entries. -->
    <slot>
      <p v-if="!entries.length" class="gl-mb-0 gl-text-subtle">
        {{ $options.i18n.noneAdded }}
      </p>
      <div v-else class="gl-flex gl-flex-col gl-gap-4">
        <div
          v-for="entry in entries"
          :key="entry.id"
          class="gl-flex gl-items-start gl-gap-3"
          :data-testid="`${testid}-entry`"
        >
          <span
            class="gl-flex gl-h-6 gl-w-6 gl-flex-shrink-0 gl-items-center gl-justify-center gl-rounded-base gl-bg-subtle gl-text-subtle"
          >
            <gl-icon :name="entry.icon" :size="14" />
          </span>
          <span class="gl-min-w-0 gl-grow">
            <span class="gl-block gl-font-semibold">{{ entry.label }}</span>
            <span v-if="entry.description" class="gl-mt-0.5 gl-block gl-text-sm gl-text-subtle">
              {{ entry.description }}
            </span>
            <dl
              v-if="entry.configItems && entry.configItems.length"
              class="gl-mb-0 gl-mt-3"
              :data-testid="`${testid}-entry-config`"
            >
              <template v-for="item in entry.configItems">
                <dt :key="`${item.key}-label`" class="gl-text-sm gl-font-semibold gl-text-subtle">
                  {{ item.label }}
                </dt>
                <dd :key="`${item.key}-value`" class="gl-mb-2 gl-ml-0 gl-text-sm">
                  <pre
                    v-if="item.code"
                    class="gl-mb-0 gl-mt-1 gl-whitespace-pre-wrap gl-rounded-base gl-bg-subtle gl-p-3 gl-text-sm"
                  ><code>{{ item.value }}</code></pre>
                  <template v-else>{{ item.value }}</template>
                </dd>
              </template>
            </dl>
          </span>
        </div>
      </div>
    </slot>
  </section>
</template>
