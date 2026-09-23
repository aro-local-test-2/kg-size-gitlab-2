<script>
import { GlButton, GlLoadingIcon, GlTable } from '@gitlab/ui';
import { FILES_TABLE_FIELDS } from 'ee/packages_and_registries/artifact_registry/constants';
import {
  fileChecksums,
  fileType,
  humanSize,
} from 'ee/packages_and_registries/artifact_registry/utils';
import { s__, sprintf } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import FileChecksums from './file_checksums.vue';

export default {
  name: 'ArtifactRegistryFilesTable',
  components: {
    FileChecksums,
    GlButton,
    GlLoadingIcon,
    GlTable,
    TimeAgoTooltip,
  },
  props: {
    files: {
      type: Array,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      disclosureMessage: '',
      expandedRows: {},
    };
  },
  computed: {
    rows() {
      return this.files.map((file) => ({
        ...file,
        type: fileType(file.fileName, this.format),
        // Derived, not mutated: `discloseRow` is the only way in, and the slot's own
        // `toggleDetails` would write to a row object this rebuilds.
        _showDetails: Boolean(this.expandedRows[file.id]),
      }));
    },
    tableFields() {
      return FILES_TABLE_FIELDS.map((field) => ({
        ...field,
        tdClass: (_value, _key, item) => [field.tdClass, this.disclosedClass(item)],
      }));
    },
  },
  watch: {
    files() {
      this.expandedRows = {};
      this.disclosureMessage = '';
    },
  },
  methods: {
    humanSize,
    disclosedClass(item) {
      // Scoped to the wide layout: below `md` GlTable stacks, and every cell's bottom
      // border is the divider between the stacked label/value pairs.
      // eslint-disable-next-line no-underscore-dangle
      return item._showDetails ? '@md:!gl-border-b-0' : '';
    },
    hasChecksums(file) {
      return fileChecksums(file, this.format).length > 0;
    },
    checksumsId(file) {
      return `ar-file-checksums-${file.id}`;
    },
    discloseRow(file, wasDisclosed) {
      this.expandedRows = { ...this.expandedRows, [file.id]: !wasDisclosed };

      // Clear on collapse so reopening the same row announces again; identical text stays silent.
      this.disclosureMessage = wasDisclosed
        ? ''
        : sprintf(
            this.$options.i18n.checksumsRevealed,
            {
              name: file.fileName,
              checksums: fileChecksums(file, this.format)
                .map(({ label }) => label)
                .join(', '),
            },
            false,
          );
    },
    toggleTitle(fileName, detailsShowing) {
      const { hideChecksums, showChecksums } = this.$options.i18n;

      return sprintf(detailsShowing ? hideChecksums : showChecksums, { name: fileName }, false);
    },
  },
  i18n: {
    showChecksums: s__('ArtifactRegistry|Show checksums for %{name}'),
    hideChecksums: s__('ArtifactRegistry|Hide checksums for %{name}'),
    checksumsRevealed: s__('ArtifactRegistry|Revealed %{checksums} for %{name}.'),
  },
};
</script>

<template>
  <div>
    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="checksums-announcement"
      >{{ disclosureMessage }}</span
    >

    <gl-table :busy="isLoading" :fields="tableFields" :items="rows" stacked="md">
      <template #table-busy>
        <!-- The guard keeps the spinner tied to the busy state: a stubbed table renders
             this slot whatever `busy` holds. -->
        <gl-loading-icon v-if="isLoading" size="sm" class="gl-my-5" />
      </template>

      <template #cell(fileName)="{ item, detailsShowing }">
        <div class="gl-flex gl-items-start gl-gap-2">
          <!-- aria-expanded stays a string: Vue drops a bound `false`, taking the collapsed state out of the DOM. -->
          <gl-button
            v-if="hasChecksums(item)"
            :icon="detailsShowing ? 'chevron-down' : 'chevron-right'"
            :aria-label="toggleTitle(item.fileName, detailsShowing)"
            :aria-expanded="detailsShowing ? 'true' : 'false'"
            :aria-controls="checksumsId(item)"
            category="tertiary"
            size="small"
            data-testid="toggle-checksums"
            @click="discloseRow(item, detailsShowing)"
          />
          <!-- Holds the toggle's space so checksum-less rows stay aligned; not dead markup. -->
          <gl-button
            v-else
            class="gl-invisible"
            icon="chevron-right"
            category="tertiary"
            size="small"
            aria-hidden="true"
            data-testid="toggle-placeholder"
          />
          <span class="gl-wrap-anywhere" data-testid="file-name">{{ item.fileName }}</span>
        </div>
      </template>

      <template #cell(type)="{ value }">
        <span data-testid="file-type">{{ value }}</span>
      </template>

      <template #cell(sizeBytes)="{ item }">
        <span data-testid="file-size">{{ humanSize(item.sizeBytes) }}</span>
      </template>

      <template #cell(createdAt)="{ item }">
        <time-ago-tooltip v-if="item.createdAt" :time="item.createdAt" data-testid="file-created" />
      </template>

      <template #row-details="{ item }">
        <file-checksums :id="checksumsId(item)" :file="item" :format="format" />
      </template>
    </gl-table>
  </div>
</template>
