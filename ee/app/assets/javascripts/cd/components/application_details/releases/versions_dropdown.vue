<script>
import { GlButton, GlCollapsibleListbox } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { MAX_NAME_LENGTH } from 'ee/cd/constants';
import cdVersionCreateMutation from 'ee/cd/graphql/applications/releases/cd_version_create.mutation.graphql';

const MAX_ENVIRONMENTS_SHOWN = 2;

export default {
  name: 'VersionsDropdown',
  components: {
    GlButton,
    GlCollapsibleListbox,
  },
  props: {
    artifactSourceId: {
      type: String,
      required: true,
    },
    versionItems: {
      type: Array,
      required: true,
    },
    selected: {
      type: String,
      required: false,
      default: null,
    },
    changed: {
      type: Boolean,
      required: false,
      default: false,
    },
    toggleAriaLabelledBy: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['select', 'error'],
  data() {
    return {
      searchTerm: '',
      isCreating: false,
      listboxKey: 0,
    };
  },
  computed: {
    filteredItems() {
      const term = this.searchTerm.trim().toLowerCase();

      return term
        ? this.versionItems.filter((item) => item.text.toLowerCase().includes(term))
        : this.versionItems;
    },
    canCreate() {
      const term = this.searchTerm.trim();

      return (
        Boolean(term) &&
        !this.versionItems.some((item) => item.text.toLowerCase() === term.toLowerCase())
      );
    },
    createText() {
      return sprintf(s__('ReleaseCreation|Use "%{name}"'), { name: this.searchTerm.trim() }, false);
    },
    toggleText() {
      const selected = this.versionItems.find((item) => item.value === this.selected);

      return selected ? this.versionText(selected) : s__('ReleaseCreation|Select version');
    },
  },
  methods: {
    environmentsText(environments) {
      const shown = environments.slice(0, MAX_ENVIRONMENTS_SHOWN);
      const remaining = environments.length - shown.length;

      return remaining ? `${shown.join(', ')} +${remaining}` : shown.join(', ');
    },
    versionSubtext(item) {
      if (item.environments.length) {
        return this.environmentsText(item.environments);
      }

      return item.verified
        ? s__('ReleaseCreation|not deployed')
        : s__('ReleaseCreation|unverified version');
    },
    versionText(item) {
      return `${item.text} · ${this.versionSubtext(item)}`;
    },
    addVersionToCache(cache, { data }) {
      const version = data?.cdVersionCreate?.version;
      if (!version) {
        return;
      }

      cache.modify({
        id: cache.identify({ __typename: 'CdArtifactSource', id: this.artifactSourceId }),
        fields: {
          versions(existing = { nodes: [] }, { toReference }) {
            return { ...existing, nodes: [toReference(version, true), ...existing.nodes] };
          },
        },
      });
    },
    resetSearch() {
      this.searchTerm = '';
      this.listboxKey += 1;
    },
    async createVersion() {
      const name = this.searchTerm.trim();
      if (!name || this.isCreating) {
        return;
      }

      if (name.length > MAX_NAME_LENGTH) {
        this.$emit(
          'error',
          sprintf(s__('ReleaseCreation|Version name cannot exceed %{maxLength} characters.'), {
            maxLength: MAX_NAME_LENGTH,
          }),
        );
        return;
      }

      this.isCreating = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: cdVersionCreateMutation,
          variables: { input: { artifactSourceId: this.artifactSourceId, name } },
          update: (cache, result) => this.addVersionToCache(cache, result),
        });

        const errors = data?.cdVersionCreate?.errors ?? [];
        if (errors.length) {
          this.$emit('error', errors.join(' '));
          return;
        }

        this.$emit('select', data.cdVersionCreate.version.id);
        this.$refs.listbox.close();
      } catch (error) {
        Sentry.captureException(error);
        this.$emit('error', s__('ReleaseCreation|Failed to add the version. Please try again.'));
      } finally {
        this.isCreating = false;
      }
    },
  },
};
</script>

<template>
  <gl-collapsible-listbox
    :key="listboxKey"
    ref="listbox"
    :items="filteredItems"
    :selected="selected"
    :toggle-text="toggleText"
    :toggle-aria-labelled-by="toggleAriaLabelledBy"
    :toggle-class="changed ? '' : '!gl-text-subtle'"
    :search-placeholder="s__('ReleaseCreation|Search version')"
    searchable
    size="small"
    block
    @search="searchTerm = $event"
    @select="$emit('select', $event)"
    @hidden="resetSearch"
  >
    <template #list-item="{ item: version }">
      <span class="gl-flex gl-flex-col">
        <span>{{ version.text }}</span>
        <span class="gl-text-sm gl-text-subtle" data-testid="version-subtext">{{
          versionSubtext(version)
        }}</span>
      </span>
    </template>
    <template v-if="canCreate" #footer>
      <gl-button
        category="tertiary"
        class="!gl-justify-start !gl-rounded-tl-none !gl-rounded-tr-none !gl-border-t-1 gl-border-t-dropdown !gl-pl-7 gl-border-t-solid"
        :class="{ 'gl-mt-3': !filteredItems.length }"
        :loading="isCreating"
        data-testid="create-version-button"
        @click="createVersion"
      >
        {{ createText }}
      </gl-button>
    </template>
  </gl-collapsible-listbox>
</template>
