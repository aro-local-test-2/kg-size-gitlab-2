<script>
import { fileChecksums } from 'ee/packages_and_registries/artifact_registry/utils';
import { s__, sprintf } from '~/locale';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import DetailsRow from '~/vue_shared/components/registry/details_row.vue';

export default {
  name: 'ArtifactRegistryFileChecksums',
  components: {
    ClipboardButton,
    DetailsRow,
  },
  props: {
    file: {
      type: Object,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
  },
  computed: {
    checksums() {
      return fileChecksums(this.file, this.format);
    },
  },
  methods: {
    isLast(index) {
      return index === this.checksums.length - 1;
    },
    copyTitle(label) {
      return sprintf(this.$options.i18n.copy, { checksum: label, name: this.file.fileName }, false);
    },
  },
  i18n: {
    copy: s__('ArtifactRegistry|Copy %{checksum} for %{name}'),
  },
};
</script>

<template>
  <div
    v-if="checksums.length"
    class="gl-flex gl-grow gl-flex-col gl-rounded-base gl-bg-subtle gl-shadow-inner-1-gray-100"
  >
    <details-row
      v-for="(checksum, index) in checksums"
      :key="checksum.key"
      :dashed="!isLast(index)"
      :data-testid="`file-checksum-${checksum.key}`"
    >
      <div class="gl-flex gl-items-start gl-gap-3 gl-px-4">
        <span class="gl-shrink-0 gl-text-subtle" data-testid="checksum-label"
          >{{ checksum.label }}:</span
        >
        <span data-testid="checksum-value">{{ checksum.value }}</span>
        <clipboard-button
          :text="checksum.value"
          :title="copyTitle(checksum.label)"
          category="tertiary"
          size="small"
          class="gl-shrink-0"
        />
      </div>
    </details-row>
  </div>
</template>
