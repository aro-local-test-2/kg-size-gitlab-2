<script>
import {
  GlAvatarLabeled,
  GlButton,
  GlCollapsibleListbox,
  GlFormGroup,
  GlLoadingIcon,
  GlSprintf,
} from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { __, s__ } from '~/locale';
import getDuoDefaultNamespaceCandidates from 'ee/ai/graphql/get_duo_default_namespace_candidates.query.graphql';
import updateDuoDefaultNamespace from 'ee/ai/graphql/update_duo_default_namespace.mutation.graphql';

export default {
  name: 'NoNamespaceEmptyState',
  i18n: {
    // Kept keyed: emitted from two branches of onConfirm and must stay identical.
    saveError: s__('DuoAgenticChat|Unable to save your namespace selection. Try again.'),
  },
  components: {
    GlAvatarLabeled,
    GlButton,
    GlCollapsibleListbox,
    GlFormGroup,
    GlLoadingIcon,
    GlSprintf,
  },
  props: {
    isClassicAvailable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['return-to-classic', 'namespace-selected', 'save-error'],
  apollo: {
    namespaceCandidates: {
      query: getDuoDefaultNamespaceCandidates,
      update(data) {
        return data?.duoDefaultNamespaceCandidates?.nodes ?? [];
      },
      error() {
        this.fetchError = true;
      },
    },
  },
  data() {
    return {
      namespaceCandidates: [],
      searchTerm: '',
      selectedNamespaceId: null,
      isSaving: false,
      fetchError: false,
      validationFailed: false,
    };
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.namespaceCandidates.loading;
    },
    hasNamespaceCandidates() {
      return this.namespaceCandidates.length > 0;
    },
    listboxItems() {
      // The backend scope has no ORDER BY, so sort alphabetically here.
      const options = [...this.namespaceCandidates]
        .sort((a, b) => a.name.localeCompare(b.name))
        .filter((ns) => ns.name.toLowerCase().includes(this.searchTerm.toLowerCase()))
        .map((ns) => ({
          value: ns.id,
          text: ns.name,
          avatarUrl: ns.avatarUrl,
          entityId: getIdFromGraphQLId(ns.id),
        }));

      // Empty means no group row at all, so the no-results text can show.
      if (!options.length) return [];

      return [{ text: s__('DuoAgenticChat|Groups with GitLab Duo enabled'), options }];
    },
    noResultsText() {
      return this.fetchError
        ? s__('DuoAgenticChat|Unable to load groups. Try again.')
        : __('No results found');
    },
    selectedNamespaceName() {
      if (!this.selectedNamespaceId) return '';
      const found = this.namespaceCandidates.find((ns) => ns.id === this.selectedNamespaceId);
      return found?.name ?? '';
    },
  },
  methods: {
    onSearch(searchTerm) {
      this.searchTerm = searchTerm;
    },
    onNamespaceSelect(namespaceId) {
      this.selectedNamespaceId = namespaceId;
      this.validationFailed = false;
      this.$emit('save-error', '');
    },
    async onConfirm() {
      if (!this.selectedNamespaceId) {
        this.validationFailed = true;
        return;
      }

      this.isSaving = true;
      this.$emit('save-error', '');

      const numericId = getIdFromGraphQLId(this.selectedNamespaceId);

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateDuoDefaultNamespace,
          variables: {
            input: {
              duoDefaultNamespaceId: numericId,
            },
          },
        });

        const errors = data?.userPreferencesUpdate?.errors ?? [];
        if (errors.length > 0) {
          this.isSaving = false;
          this.$emit('save-error', this.$options.i18n.saveError);
          return;
        }

        // Keep the loading state until the page reloads on 'namespace-selected'.
        this.$emit('namespace-selected');
      } catch {
        this.isSaving = false;
        this.$emit('save-error', this.$options.i18n.saveError);
      }
    },
  },
};
</script>

<template>
  <div
    class="gl-mx-auto gl-flex gl-w-full gl-max-w-md gl-flex-col gl-items-start gl-py-8"
    data-testid="no-namespace-empty-state"
  >
    <h2 class="gl-my-0 gl-text-size-h2">
      {{ s__('DuoAgenticChat|Choose a group to use Agentic Chat') }}
    </h2>

    <template v-if="isLoading">
      <gl-loading-icon size="sm" class="gl-mt-4" />
    </template>
    <template v-else-if="hasNamespaceCandidates || fetchError">
      <p class="gl-mb-0 gl-text-subtle">
        {{
          s__(
            'DuoAgenticChat|This determines where your GitLab Duo usage is tracked. You can change this any time in your profile preferences.',
          )
        }}
      </p>
      <gl-form-group
        :label="__('Group')"
        label-class="gl-font-bold"
        class="gl-mb-0 gl-mt-5 gl-w-full"
        :state="validationFailed ? false : null"
        :invalid-feedback="s__('DuoAgenticChat|Select a group to continue')"
      >
        <!-- panel-match-trigger-width only sizes the options list, absent when items is
             empty (fetch-error case); the override + gl-relative match width regardless. -->
        <gl-collapsible-listbox
          :items="listboxItems"
          :selected="selectedNamespaceId"
          :toggle-text="selectedNamespaceName || s__('DuoAgenticChat|Select a group')"
          :no-results-text="noResultsText"
          :toggle-class="validationFailed ? '!gl-shadow-inner-1-red-400' : undefined"
          :searchable="hasNamespaceCandidates"
          :search-placeholder="s__('DuoAgenticChat|Search groups')"
          block
          panel-match-trigger-width
          class="gl-relative [&_.gl-new-dropdown-panel]:gl-w-full"
          data-testid="namespace-listbox"
          @search="onSearch"
          @select="onNamespaceSelect"
        >
          <!-- Overrides the group li's hardcoded gl-font-bold gl-text-strong to match the design. -->
          <template #group-label="{ group }">
            <span class="gl-font-normal gl-text-subtle">{{ group.text }}</span>
          </template>
          <template #list-item="{ item }">
            <gl-avatar-labeled
              :label="item.text"
              :src="item.avatarUrl"
              :entity-id="item.entityId"
              :entity-name="item.text"
              :size="24"
              shape="rect"
            />
          </template>
        </gl-collapsible-listbox>
      </gl-form-group>
      <gl-button
        variant="confirm"
        category="primary"
        block
        class="gl-mt-5"
        :loading="isSaving"
        data-testid="confirm-namespace-button"
        @click="onConfirm"
      >
        {{ __('Continue') }}
      </gl-button>
    </template>
    <template v-else>
      <p class="gl-mt-4 gl-text-subtle" data-testid="no-groups-message">
        {{ s__('DuoAgenticChat|No eligible groups available') }}
      </p>
    </template>

    <template v-if="isClassicAvailable && !isLoading">
      <div class="gl-mt-6 gl-flex gl-w-full gl-items-center gl-gap-3">
        <hr class="gl-my-0 gl-grow gl-border-default" />
        <span class="gl-text-subtle">{{ __('or') }}</span>
        <hr class="gl-my-0 gl-grow gl-border-default" />
      </div>
      <p class="gl-mb-0 gl-mt-6 gl-w-full gl-text-center gl-text-subtle">
        <gl-sprintf
          :message="
            s__(
              'DuoAgenticChat|%{linkStart}Use non-agentic Chat%{linkEnd} (answers questions only)',
            )
          "
        >
          <template #link="{ content }">
            <gl-button
              variant="link"
              data-testid="return-to-non-agentic-button"
              @click="$emit('return-to-classic')"
            >
              {{ content }}
            </gl-button>
          </template>
        </gl-sprintf>
      </p>
    </template>
  </div>
</template>
