<script>
import { defineComponent } from 'vue';
import { debounce } from 'lodash-es';
import { GlAlert, GlAvatar, GlCollapsibleListbox, GlModal } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import excludableNamespacesQuery from '../graphql/queries/excludable_namespaces.query.graphql';
import excludedNamespaceCreateMutation from '../graphql/mutations/excluded_namespace_create.mutation.graphql';

const SEARCH_DEBOUNCE_MS = 500;
const GENERIC_ERROR_MESSAGE = s__('Orbit|Failed to exclude the group. Please try again.');

export default defineComponent({
  name: 'ExcludeGroupModal',
  compatConfig: { MODE: 3 },
  components: {
    GlAlert,
    GlAvatar,
    GlCollapsibleListbox,
    GlModal,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    excludedPaths: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['change', 'excluded'],
  apollo: {
    groups: {
      query: excludableNamespacesQuery,
      variables() {
        return { search: this.searchTerm || null };
      },
      update(data) {
        return data.groups?.nodes || [];
      },
      skip() {
        return !this.visible;
      },
    },
  },
  data() {
    return {
      groups: [],
      searchTerm: '',
      selectedPath: null,
      excluding: false,
      errorMessage: '',
    };
  },
  computed: {
    availableGroups() {
      return this.groups.filter((group) => !this.excludedPaths.includes(group.fullPath));
    },
    listboxItems() {
      return this.availableGroups.map((group) => ({ value: group.fullPath, text: group.name }));
    },
    selectedGroup() {
      return this.availableGroups.find((group) => group.fullPath === this.selectedPath) || null;
    },
    toggleText() {
      return this.selectedGroup?.name || s__('Orbit|Select a top-level group');
    },
    primaryAction() {
      return {
        text: s__('Orbit|Exclude'),
        attributes: {
          variant: 'confirm',
          disabled: !this.selectedGroup,
          loading: this.excluding,
        },
      };
    },
    cancelAction() {
      return {
        text: s__('Orbit|Cancel'),
        attributes: { disabled: this.excluding },
      };
    },
  },
  created() {
    this.debouncedSearch = debounce((searchTerm) => {
      this.searchTerm = searchTerm;
    }, SEARCH_DEBOUNCE_MS);
  },
  beforeDestroy() {
    this.debouncedSearch.cancel();
  },
  methods: {
    onChange(visible) {
      this.$emit('change', visible);
      if (!visible) {
        this.selectedPath = null;
        this.searchTerm = '';
        this.errorMessage = '';
      }
    },
    async onPrimary() {
      if (!this.selectedGroup || this.excluding) return;

      this.excluding = true;
      this.errorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation: excludedNamespaceCreateMutation,
          variables: { input: { groupPath: this.selectedGroup.fullPath } },
        });
        const result = data.knowledgeGraphExcludedNamespaceCreate;
        if (result.errors?.length) {
          [this.errorMessage] = result.errors;
          return;
        }

        this.$emit('excluded', result.group);
        this.$emit('change', false);
      } catch (error) {
        Sentry.captureException(error);
        this.errorMessage = GENERIC_ERROR_MESSAGE;
      } finally {
        this.excluding = false;
      }
    },
  },
});
</script>

<template>
  <gl-modal
    :visible="visible"
    modal-id="orbit-exclude-group-modal"
    :title="s__('Orbit|Exclude group from automatic indexing')"
    :action-primary="primaryAction"
    :action-cancel="cancelAction"
    data-testid="orbit-exclude-group-modal"
    @change="onChange"
    @primary.prevent="onPrimary"
  >
    <gl-alert v-if="errorMessage" variant="danger" class="gl-mb-4" @dismiss="errorMessage = ''">
      {{ errorMessage }}
    </gl-alert>
    <p>
      {{
        s__(
          'Orbit|Excluded groups are not automatically indexed. If the group is already indexed, GitLab removes its enrollment and index within a few minutes.',
        )
      }}
    </p>
    <gl-collapsible-listbox
      block
      searchable
      :items="listboxItems"
      :selected="selectedPath"
      :toggle-text="toggleText"
      :searching="$apollo.queries.groups.loading"
      :header-text="s__('Orbit|Select group')"
      :no-results-text="s__('Orbit|No top-level groups found')"
      @search="debouncedSearch"
      @select="selectedPath = $event"
    >
      <template #list-item="{ item }">
        <span class="gl-flex gl-items-center gl-gap-3">
          <gl-avatar
            :src="availableGroups.find((group) => group.fullPath === item.value)?.avatarUrl"
            :entity-name="item.text"
            :size="24"
            shape="rect"
          />
          {{ item.text }}
        </span>
      </template>
    </gl-collapsible-listbox>
  </gl-modal>
</template>
