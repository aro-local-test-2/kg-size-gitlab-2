<script>
import { debounce } from 'lodash-es';
import { GlFormTextarea } from '@gitlab/ui';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';

export default {
  name: 'NameListTextarea',
  components: { GlFormTextarea },
  props: {
    items: {
      type: Array,
      required: false,
      default: () => [],
    },
    placeholder: {
      type: String,
      required: true,
    },
  },
  emits: ['input'],
  data() {
    // Seeded once from `items`, then never re-synced from it (see spec: "does not
    // clobber in-progress typing...").
    return {
      text: this.items.join('\n'),
    };
  },
  created() {
    this.debouncedEmitChange = debounce(this.emitChange, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
  },
  destroyed() {
    this.debouncedEmitChange.cancel();
  },
  methods: {
    handleInput(text) {
      this.text = text;
      this.debouncedEmitChange(text);
    },
    emitChange(text) {
      const parsed = [
        ...new Set(
          text
            .split(/[\n,]+/)
            .map((line) => line.trim())
            .filter(Boolean),
        ),
      ];

      this.$emit('input', parsed);
    },
  },
};
</script>

<template>
  <gl-form-textarea no-resize :value="text" :placeholder="placeholder" @input="handleInput" />
</template>
