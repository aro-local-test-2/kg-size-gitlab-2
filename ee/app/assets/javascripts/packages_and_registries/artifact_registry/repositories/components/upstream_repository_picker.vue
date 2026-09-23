<script>
import {
  GlAlert,
  GlButton,
  GlFormGroup,
  GlIntersectionObserver,
  GlLoadingIcon,
  GlTokenSelector,
} from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { fetchPolicies } from '~/lib/graphql';
import { n__, s__, sprintf } from '~/locale';
import {
  GRAPHQL_PAGE_SIZE,
  REPOSITORY_FORMAT_CONTAINER_FAMILY,
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_LABELS,
  REPOSITORY_KIND_REMOTE,
  UPSTREAM_REPOSITORIES_CAP,
} from '../../constants';
import getUpstreamRepositoryCandidatesQuery from '../../graphql/queries/get_upstream_repository_candidates.query.graphql';
import { isContainerFormat } from '../../utils';

const ATTACHABLE_KINDS = [REPOSITORY_KIND_HOSTED, REPOSITORY_KIND_REMOTE];

export default {
  name: 'ArtifactRegistryUpstreamRepositoryPicker',
  i18n: {
    search: s__('ArtifactRegistry|Search by name or URL'),
  },
  components: {
    GlAlert,
    GlButton,
    GlFormGroup,
    GlIntersectionObserver,
    GlLoadingIcon,
    GlTokenSelector,
  },
  inject: ['organizationGid'],
  props: {
    format: {
      type: String,
      required: true,
    },
    excludedIds: {
      type: Array,
      required: true,
    },
    listSize: {
      type: Number,
      required: true,
    },
  },
  emits: ['confirm', 'close'],
  data() {
    return {
      candidates: undefined,
      loaded: [],
      selected: [],
      search: '',
      announcement: '',
      hasError: false,
    };
  },
  apollo: {
    candidates: {
      query: getUpstreamRepositoryCandidatesQuery,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      nextFetchPolicy: fetchPolicies.CACHE_FIRST,
      variables() {
        return {
          organizationId: this.organizationGid,
          kinds: ATTACHABLE_KINDS,
          formats: this.formatFamily,
          first: GRAPHQL_PAGE_SIZE,
        };
      },
      update: ({ organization }) =>
        organization?.artifactRegistryRepositories ?? { nodes: [], pageInfo: {} },
      result({ loading }) {
        if (loading) return;

        this.appendPage();
      },
      error() {
        this.hasError = true;
      },
    },
  },
  computed: {
    loading() {
      return this.$apollo.queries.candidates.loading;
    },
    pageInfo() {
      return this.candidates?.pageInfo ?? {};
    },
    hasNextPage() {
      return Boolean(this.pageInfo.hasNextPage);
    },
    formatFamily() {
      return isContainerFormat(this.format) ? REPOSITORY_FORMAT_CONTAINER_FAMILY : [this.format];
    },
    attachable() {
      return this.loaded.filter(({ id }) => !this.excludedIds.includes(id));
    },
    visible() {
      const selectedIds = this.selected.map(({ id }) => id);
      const unselected = this.attachable.filter(({ id }) => !selectedIds.includes(id));
      const term = this.search.trim().toLowerCase();

      if (!term) return unselected;

      return unselected.filter(
        (candidate) =>
          candidate.name.toLowerCase().includes(term) ||
          (this.candidateUrl(candidate) ?? '').toLowerCase().includes(term),
      );
    },
    placeholder() {
      return this.selected.length ? '' : this.$options.i18n.search;
    },
    excessCount() {
      return this.listSize + this.selected.length - UPSTREAM_REPOSITORIES_CAP;
    },
    wouldExceedCap() {
      return this.excessCount > 0;
    },
    capState() {
      return this.wouldExceedCap ? false : null;
    },
    capErrorText() {
      return sprintf(
        n__(
          'ArtifactRegistry|Remove %{count} repository from the selection to stay within the maximum of %{cap}.',
          'ArtifactRegistry|Remove %{count} repositories from the selection to stay within the maximum of %{cap}.',
          this.excessCount,
        ),
        { count: this.excessCount, cap: UPSTREAM_REPOSITORIES_CAP },
      );
    },
    hasNoAttachable() {
      return this.attachable.length === 0 && !this.hasNextPage && !this.loading;
    },
    hasNoMatch() {
      return Boolean(this.search.trim()) && this.visible.length === 0 && this.attachable.length > 0;
    },
    noAttachableText() {
      return sprintf(
        s__(
          'ArtifactRegistry|No %{format} repositories are available to add. Create a hosted or remote repository first.',
        ),
        { format: REPOSITORY_FORMAT_LABELS[this.format] },
      );
    },
    noMatchText() {
      return this.hasNextPage
        ? s__(
            'ArtifactRegistry|0 loaded repositories match. Keep scrolling to load and search more.',
          )
        : s__('ArtifactRegistry|No repositories match your search.');
    },
  },
  watch: {
    search(value) {
      if (!value) return;

      this.announcement = n__(
        'ArtifactRegistry|%d repository matches.',
        'ArtifactRegistry|%d repositories match.',
        this.visible.length,
      );
    },
    selected(value) {
      this.announcement = sprintf(
        n__(
          'ArtifactRegistry|%{count} repository selected. The list will hold %{total} of %{cap}.',
          'ArtifactRegistry|%{count} repositories selected. The list will hold %{total} of %{cap}.',
          value.length,
        ),
        {
          count: value.length,
          total: this.listSize + value.length,
          cap: UPSTREAM_REPOSITORIES_CAP,
        },
      );
    },
  },
  mounted() {
    this.$refs.tokenSelector.focusTextInput();
  },
  capErrorId: uniqueId('upstream-repository-picker-cap-error-'),
  methods: {
    appendPage() {
      const nodes = this.candidates?.nodes ?? [];
      const before = this.attachable.length;
      const known = new Set(this.loaded.map(({ id }) => id));

      this.loaded = [...this.loaded, ...nodes.filter(({ id }) => !known.has(id))];

      if (this.attachable.length > before) {
        this.announcement = n__(
          'ArtifactRegistry|%d repository loaded.',
          'ArtifactRegistry|%d repositories loaded.',
          this.attachable.length,
        );
      }
    },
    loadNextPage() {
      this.$apollo.queries.candidates.fetchMore({
        variables: { after: this.pageInfo.endCursor },
        updateQuery: (_, { fetchMoreResult }) => fetchMoreResult,
      });
    },
    candidateUrl({ settings }) {
      return settings?.url ?? null;
    },
    kindLabel(kind) {
      return REPOSITORY_KIND_LABELS[kind] || kind;
    },
    confirm() {
      this.$emit(
        'confirm',
        this.selected.map(({ id, name, kind, sizeBytes, settings }) => ({
          id,
          name,
          kind,
          sizeBytes: sizeBytes ?? null,
          url: settings?.url ?? null,
        })),
      );
    },
  },
};
</script>

<template>
  <div class="gl-p-3" data-testid="upstream-repository-picker">
    <gl-alert v-if="hasError" class="gl-mb-3" variant="danger" :dismissible="false">
      {{ s__('ArtifactRegistry|Failed to load repositories.') }}
    </gl-alert>

    <gl-form-group class="gl-mb-0" label-for="upstream-repository-picker-search" :state="capState">
      <template #invalid-feedback>
        <span v-if="wouldExceedCap" :id="$options.capErrorId" data-testid="picker-cap-error">{{
          capErrorText
        }}</span>
      </template>

      <gl-token-selector
        ref="tokenSelector"
        v-model="selected"
        :dropdown-items="visible"
        :hide-dropdown-with-no-items="false"
        menu-class="!gl-w-full"
        :placeholder="placeholder"
        :state="capState"
        :aria-label="$options.i18n.search"
        :text-input-attrs="{ id: 'upstream-repository-picker-search' }"
        data-testid="upstream-repository-picker-search"
        @keydown.enter.prevent
        @text-input="search = $event"
      >
        <template #dropdown-item-content="{ dropdownItem }">
          <div class="gl-flex gl-items-center gl-gap-3 gl-py-3">
            <div class="gl-grow">
              <span class="gl-wrap-anywhere" data-testid="candidate-name">{{
                dropdownItem.name
              }}</span>
              <span
                v-if="candidateUrl(dropdownItem)"
                class="gl-block gl-text-sm gl-text-subtle gl-wrap-anywhere"
                data-testid="candidate-url"
                >{{ candidateUrl(dropdownItem) }}</span
              >
            </div>
            <span class="gl-text-sm gl-text-subtle" data-testid="candidate-kind">{{
              kindLabel(dropdownItem.kind)
            }}</span>
          </div>
        </template>

        <template #no-results-content>
          <span v-if="hasNoAttachable" data-testid="picker-no-attachable">{{
            noAttachableText
          }}</span>
          <span v-else-if="hasNoMatch" data-testid="picker-no-match">{{ noMatchText }}</span>
        </template>

        <template #dropdown-footer>
          <gl-intersection-observer
            v-if="hasNextPage"
            data-testid="picker-sentinel"
            @appear="loadNextPage"
          />
          <gl-loading-icon v-if="loading" size="sm" />
        </template>
      </gl-token-selector>
    </gl-form-group>

    <div class="gl-mt-3 gl-flex gl-gap-3">
      <gl-button
        variant="confirm"
        size="small"
        :disabled="!selected.length || wouldExceedCap"
        :aria-describedby="wouldExceedCap ? $options.capErrorId : null"
        data-testid="picker-confirm"
        @click="confirm"
      >
        {{ __('Add') }}
      </gl-button>
      <gl-button size="small" data-testid="picker-cancel" @click="$emit('close')">
        {{ __('Cancel') }}
      </gl-button>
    </div>

    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="upstream-repository-picker-announcement"
      >{{ announcement }}</span
    >
  </div>
</template>
