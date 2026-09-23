<script>
import {
  GlBadge,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlIcon,
  GlLink,
  GlLoadingIcon,
  GlSprintf,
  GlTable,
  GlToastMixin,
  GlTooltipDirective,
} from '@gitlab/ui';
import { isEqual } from 'lodash-es';
import {
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
  VERSION_DETAIL_ROUTE_NAME,
} from 'ee/packages_and_registries/artifact_registry/constants';
import deleteVersionMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_version.mutation.graphql';
import getArtifactVersionsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_versions.query.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import { permissionAllows } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';
import { humanSize, versionsTableFields } from 'ee/packages_and_registries/artifact_registry/utils';
import { s__, sprintf } from '~/locale';
import HelpIcon from '~/vue_shared/components/help_icon/help_icon.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import DeleteConfirmationModal from '../components/delete_confirmation_modal.vue';
import PullCommandDrawer from './pull_command_drawer.vue';
import { sourceOf } from './version_source';

export default {
  name: 'ArtifactRegistryVersionsTable',
  components: {
    DeleteConfirmationModal,
    GlBadge,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlIcon,
    GlLink,
    GlLoadingIcon,
    GlSprintf,
    GlTable,
    HelpIcon,
    PullCommandDrawer,
    TimeAgoTooltip,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin],
  props: {
    versions: {
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
      activeVersion: null,
      versionToDelete: null,
      pendingDeletionIds: [],
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
      return versionsTableFields(this.format).filter(
        ({ key }) => !this.hiddenColumns.includes(key),
      );
    },
    rows() {
      return this.versions.map((version) => ({ ...version, source: sourceOf(version) }));
    },
    activeVersionName() {
      return this.activeVersion?.version ?? '';
    },
    activeVersionTags() {
      return this.activeVersion?.tags ?? [];
    },
    deleteModalCopy() {
      const { deleteTitle, deleteBody, deleteVersionLabel } = this.$options.i18n;

      return {
        title: deleteTitle,
        body: deleteBody,
        name: this.versionToDelete?.version ?? '',
        actionText: deleteVersionLabel,
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
    humanSize,
    versionRoute({ id: versionId }) {
      return {
        name: VERSION_DETAIL_ROUTE_NAME,
        params: { id: this.name, artifactId: this.artifact.id, versionId },
      };
    },
    requestSort({ sortBy, sortDesc }) {
      this.requestedSort = { sortBy, sortDesc };

      this.$emit('sort-changed', { sortBy, sortDesc });
    },
    // The toggle renders as an icon, so its accessible name is all a screen reader gets:
    // it names the version the actions belong to rather than saying only "More actions".
    toggleText(version) {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), { name: version });
    },
    pullCommandItem(version) {
      return {
        text: s__('ArtifactRegistry|View pull command'),
        action: () => {
          this.activeVersion = { version: version.version, tags: version.distTags };
        },
      };
    },
    deleteItem(version) {
      return {
        text: this.$options.i18n.deleteVersionLabel,
        variant: 'danger',
        action: () => {
          this.versionToDelete = version;
        },
      };
    },
    isPendingDeletion({ id }) {
      return this.pendingDeletionIds.includes(id);
    },
    async deleteVersion({ id }) {
      if (this.pendingDeletionIds.includes(id)) return;

      this.pendingDeletionIds.push(id);

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: deleteVersionMutation,
          input: { name: this.name, id },
          refetchQueries: [getArtifactVersionsQuery],
          awaitRefetchQueries: true,
        });

        if (accepted) this.$toast.show(this.$options.i18n.deletionScheduled);
      } finally {
        this.pendingDeletionIds = this.pendingDeletionIds.filter((pendingId) => pendingId !== id);
      }
    },
  },
  i18n: {
    alphabeticalSort: s__(
      'ArtifactRegistry|Sorts alphabetically, not by version order. Ascending puts 1.10.0 before 1.9.0.',
    ),
    deleteVersionLabel: s__('ArtifactRegistry|Delete version'),
    deleteTitle: s__('ArtifactRegistry|Delete version?'),
    deleteBody: s__(
      'ArtifactRegistry|This action permanently deletes version %{name} and all of its files. This action cannot be undone.',
    ),
    deletionScheduled: s__('ArtifactRegistry|Version successfully scheduled for deletion.'),
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

      <template #head(version)="{ label }">
        <span class="gl-inline-flex gl-items-center gl-gap-2">
          {{ label }}
          <help-icon
            v-gl-tooltip
            :title="$options.i18n.alphabeticalSort"
            :aria-label="$options.i18n.alphabeticalSort"
            data-testid="version-sort-hint"
          />
        </span>
      </template>

      <template #cell(version)="{ item }">
        <router-link
          :to="versionRoute(item)"
          class="gl-font-semibold gl-text-default gl-wrap-anywhere"
          data-testid="version-name"
          >{{ item.version }}</router-link
        >
      </template>

      <template #cell(tags)="{ item }">
        <div v-if="item.distTags.length" class="gl-flex gl-flex-wrap gl-gap-2">
          <gl-badge
            v-for="tag in item.distTags"
            :key="tag"
            variant="info"
            data-testid="version-tag"
            >{{ tag }}</gl-badge
          >
        </div>
        <span v-else class="gl-text-subtle" data-testid="version-untagged">{{
          s__('ArtifactRegistry|untagged')
        }}</span>
      </template>

      <template #cell(sizeBytes)="{ item }">
        <span v-if="item.sizeBytes != null" data-testid="version-size">{{
          humanSize(item.sizeBytes)
        }}</span>
      </template>

      <template #cell(createdAt)="{ item }">
        <time-ago-tooltip :time="item.createdAt" data-testid="version-published" />
      </template>

      <template #cell(source)="{ value }">
        <div class="gl-flex gl-flex-col gl-gap-1">
          <span v-if="value.sha" class="gl-flex gl-items-center gl-gap-2">
            <gl-icon name="commit" />
            <gl-link
              v-if="value.commitPath"
              :href="value.commitPath"
              class="gl-font-monospace"
              data-testid="version-commit"
              >{{ value.sha }}</gl-link
            >
            <span v-else class="gl-font-monospace" data-testid="version-commit">{{
              value.sha
            }}</span>
          </span>

          <span v-else data-testid="version-published-by">
            <gl-sprintf :message="value.originMessage">
              <template v-if="value.author" #author>{{ value.author }}</template>
            </gl-sprintf>
          </span>

          <span
            v-if="value.attributionMessage"
            class="gl-text-sm gl-text-subtle"
            data-testid="version-attribution"
          >
            <gl-sprintf :message="value.attributionMessage">
              <template v-if="value.project" #project>
                <gl-link :href="value.project.webPath">{{ value.project.name }}</gl-link>
              </template>
              <template v-if="value.author" #author>{{ value.author }}</template>
            </gl-sprintf>
          </span>
        </div>
      </template>

      <template #cell(actions)="{ item }">
        <gl-disclosure-dropdown
          icon="ellipsis_v"
          :toggle-text="toggleText(item.version)"
          :loading="isPendingDeletion(item)"
          text-sr-only
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="version-actions"
        >
          <gl-disclosure-dropdown-item
            :item="pullCommandItem(item)"
            data-testid="view-pull-command"
          />
          <gl-disclosure-dropdown-item
            v-if="canDelete"
            :item="deleteItem(item)"
            data-testid="delete-version"
          />
        </gl-disclosure-dropdown>
      </template>
    </gl-table>

    <!-- One drawer for the table rather than one per row: the drawer it opens reads the
         row from `activeVersion`, and only one row's menu can be acted on at a time. -->
    <pull-command-drawer
      :open="Boolean(activeVersion)"
      :format="format"
      :artifact="artifact"
      :name="name"
      :version="activeVersionName"
      :tags="activeVersionTags"
      @close="activeVersion = null"
    />

    <delete-confirmation-modal
      v-model="versionToDelete"
      v-bind="deleteModalCopy"
      @confirm="deleteVersion"
    />
  </div>
</template>
