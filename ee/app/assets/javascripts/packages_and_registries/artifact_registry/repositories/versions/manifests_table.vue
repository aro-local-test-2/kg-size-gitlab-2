<script>
import {
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlLoadingIcon,
  GlSprintf,
  GlTable,
  GlToastMixin,
  GlTruncate,
} from '@gitlab/ui';
import { isEqual } from 'lodash-es';
import {
  MANIFEST_KIND_LABELS,
  MANIFEST_KIND_SBOM,
  MANIFEST_KIND_SIGNATURE,
  MANIFEST_KIND_SLSA,
  MANIFESTS_TABLE_FIELDS,
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
} from 'ee/packages_and_registries/artifact_registry/constants';
import deleteManifestMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_manifest.mutation.graphql';
import getArtifactManifestsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_manifests.query.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import { permissionAllows } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';
import {
  humanSize,
  manifestDeleteBody,
  manifestType,
  shortDigest,
} from 'ee/packages_and_registries/artifact_registry/utils';
import { createAlert } from '~/alert';
import { __, s__, sprintf } from '~/locale';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import DeleteConfirmationModal from '../components/delete_confirmation_modal.vue';
import PullCommandDrawer from './pull_command_drawer.vue';

const REFERRER_MESSAGES = {
  [MANIFEST_KIND_SIGNATURE]: s__('ArtifactRegistry|Signature for %{digest}'),
  [MANIFEST_KIND_SBOM]: s__('ArtifactRegistry|SBOM attestation for %{digest}'),
  [MANIFEST_KIND_SLSA]: s__('ArtifactRegistry|SLSA attestation for %{digest}'),
};

export default {
  name: 'ArtifactRegistryManifestsTable',
  components: {
    ClipboardButton,
    DeleteConfirmationModal,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlLoadingIcon,
    GlSprintf,
    GlTable,
    GlTruncate,
    PullCommandDrawer,
    TimeAgoTooltip,
  },
  mixins: [GlToastMixin],
  props: {
    manifests: {
      type: Array,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
    artifact: {
      type: Object,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    imageId: {
      type: String,
      required: true,
    },
    hiddenColumns: {
      type: Array,
      required: false,
      default: () => [],
    },
    sort: {
      type: Object,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['sort-changed'],
  data() {
    return {
      manifestToDelete: null,
      pendingDeletionDigests: [],
      activeDigest: null,
      // Remounts the table: `GlTable` seeds its sort state in `data()` and never watches it.
      externalSortCount: 0,
      requestedSort: null,
    };
  },
  computed: {
    canDelete() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_DELETE_ARTIFACT);
    },
    fields() {
      return MANIFESTS_TABLE_FIELDS.filter(({ key }) => !this.hiddenColumns.includes(key));
    },
    rows() {
      return this.manifests.map((manifest) => ({ ...manifest, type: manifestType(manifest) }));
    },
    deleteModalCopy() {
      const { deleteTitle, deleteManifestLabel } = this.$options.i18n;

      return {
        title: deleteTitle,
        body: manifestDeleteBody(this.manifestToDelete?.type?.kind),
        name: shortDigest(this.manifestToDelete?.digest),
        actionText: deleteManifestLabel,
      };
    },
  },
  watch: {
    sort(sort) {
      if (isEqual(sort, this.requestedSort)) return;

      this.externalSortCount += 1;
    },
  },
  methods: {
    requestSort({ sortBy, sortDesc }) {
      this.requestedSort = { sortBy, sortDesc };

      this.$emit('sort-changed', { sortBy, sortDesc });
    },
    humanSize,
    shortDigest,
    standaloneLabel({ kind }) {
      return MANIFEST_KIND_LABELS[kind];
    },
    referrerMessage({ kind, artifactType }) {
      if (REFERRER_MESSAGES[kind]) return REFERRER_MESSAGES[kind];

      return artifactType ? this.$options.i18n.rawReferrer : this.$options.i18n.referrer;
    },
    toggleText(digest) {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), {
        name: shortDigest(digest),
      });
    },
    deleteItem(manifest) {
      return {
        text: this.$options.i18n.deleteManifestLabel,
        variant: 'danger',
        action: () => {
          this.manifestToDelete = manifest;
        },
      };
    },
    pullCommandItem(digest) {
      return {
        text: s__('ArtifactRegistry|View pull command'),
        action: () => {
          this.activeDigest = digest;
        },
      };
    },
    isPendingDeletion({ digest }) {
      return this.pendingDeletionDigests.includes(digest);
    },
    async deleteManifest({ digest }) {
      if (this.pendingDeletionDigests.includes(digest)) return;

      this.pendingDeletionDigests.push(digest);

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: deleteManifestMutation,
          input: { name: this.name, imageId: this.imageId, digest },
        });

        if (!accepted) return;

        try {
          await this.$apollo.getClient().refetchQueries({ include: [getArtifactManifestsQuery] });
        } catch (error) {
          createAlert({
            message: __('Something went wrong. Please try again.'),
            error,
            captureError: true,
          });
          return;
        }

        this.$toast.show(this.$options.i18n.deletionScheduled);
      } finally {
        this.pendingDeletionDigests = this.pendingDeletionDigests.filter(
          (pendingDigest) => pendingDigest !== digest,
        );
      }
    },
  },
  i18n: {
    copyDigest: s__('ArtifactRegistry|Copy digest'),
    rawReferrer: s__('ArtifactRegistry|%{artifactType} for %{digest}'),
    referrer: s__('ArtifactRegistry|Referrer for %{digest}'),
    deleteManifestLabel: s__('ArtifactRegistry|Delete manifest'),
    deleteTitle: s__('ArtifactRegistry|Delete manifest?'),
    deletionScheduled: s__('ArtifactRegistry|Manifest successfully scheduled for deletion.'),
  },
};
</script>

<template>
  <div>
    <gl-table
      :key="externalSortCount"
      :busy="isLoading"
      :fields="fields"
      :items="rows"
      :sort-by="sort.sortBy"
      :sort-desc="sort.sortDesc"
      no-local-sorting
      stacked="md"
      @sort-changed="requestSort"
    >
      <template #table-busy>
        <!-- The guard keeps the spinner tied to the busy state: a stubbed table renders
             this slot whatever `busy` holds. -->
        <gl-loading-icon v-if="isLoading" size="sm" class="gl-my-5" />
      </template>

      <template #cell(digest)="{ item }">
        <span
          class="gl-flex gl-items-center gl-justify-end gl-gap-2 @md/panel:gl-justify-start"
          data-testid="manifest-digest"
        >
          <span class="gl-font-semibold gl-text-default">{{ shortDigest(item.digest) }}</span>
          <clipboard-button
            :text="item.digest"
            :title="$options.i18n.copyDigest"
            category="tertiary"
            size="small"
          />
        </span>
      </template>

      <template #cell(type)="{ value }">
        <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-1" data-testid="manifest-type">
          <template v-if="value.subjectDigest">
            <gl-sprintf :message="referrerMessage(value)">
              <template v-if="value.artifactType" #artifactType>
                <gl-truncate
                  :text="value.artifactType"
                  class="gl-min-w-0 gl-max-w-26"
                  position="middle"
                  with-tooltip
                />
              </template>
              <template #digest>
                <!-- Text rather than a link: whether a subject digest opens the manifest it names
                     is open on the design (https://www.figma.com/design/b5gaaEDjfxZbphoRQ3jVGv/AR-concepting?node-id=3791-41107). -->
                <span class="gl-font-monospace">{{ value.subjectDigest }}</span>
              </template>
            </gl-sprintf>
          </template>
          <template v-else>{{ standaloneLabel(value) }}</template>
        </span>
      </template>

      <template #cell(size)="{ item }">
        <span data-testid="manifest-size">{{ humanSize(item.size) }}</span>
      </template>

      <template #cell(createdAt)="{ item }">
        <time-ago-tooltip :time="item.createdAt" data-testid="manifest-published" />
      </template>

      <template #cell(actions)="{ item }">
        <gl-disclosure-dropdown
          icon="ellipsis_v"
          :toggle-text="toggleText(item.digest)"
          :loading="isPendingDeletion(item)"
          text-sr-only
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="manifest-actions"
        >
          <gl-disclosure-dropdown-item
            :item="pullCommandItem(item.digest)"
            data-testid="view-pull-command"
          />
          <gl-disclosure-dropdown-item
            v-if="canDelete"
            :item="deleteItem(item)"
            data-testid="delete-manifest"
          />
        </gl-disclosure-dropdown>
      </template>
    </gl-table>

    <pull-command-drawer
      :open="Boolean(activeDigest)"
      :format="format"
      :artifact="artifact"
      :name="name"
      :digest="activeDigest || ''"
      @close="activeDigest = null"
    />

    <delete-confirmation-modal
      v-model="manifestToDelete"
      v-bind="deleteModalCopy"
      @confirm="deleteManifest"
    />
  </div>
</template>
