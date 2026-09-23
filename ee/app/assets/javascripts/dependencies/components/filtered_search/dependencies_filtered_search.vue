<script>
import { GlFilteredSearch } from '@gitlab/ui';
// eslint-disable-next-line no-restricted-imports
import { mapActions, mapState } from 'vuex';
import { s__ } from '~/locale';
import { NAMESPACE_PROJECT } from '../../constants';

export default {
  name: 'DependenciesFilteredSearch',
  components: {
    GlFilteredSearch,
  },
  inject: ['namespaceType'],
  props: {
    filteredSearchId: {
      type: String,
      required: true,
    },
    tokens: {
      type: Array,
      required: true,
    },
    value: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  computed: {
    ...mapState(['searchFilterParameters']),
    // Temporary until https://gitlab.com/gitlab-org/gitlab/-/issues/612168: malware is only in
    // scope on the default ref. "All tracked refs" is out of scope even though the query still
    // drops ALL and falls back to the default ref.
    availableTokens() {
      const appliedTrackedRefs = this.searchFilterParameters?.trackedRefIds || [];

      return this.tokens.map((token) =>
        // only the malware token needs the applied tracked refs
        token.type === 'malware' ? { ...token, appliedTrackedRefs } : token,
      );
    },
  },
  methods: {
    ...mapActions([
      'setSearchFilterParameters',
      'fetchDependencies',
      'fetchDependenciesViaGraphQL',
    ]),
    fetchDependenciesWithFeatureFlag() {
      if (this.namespaceType === NAMESPACE_PROJECT) {
        this.fetchDependenciesViaGraphQL();
      } else {
        this.fetchDependencies({ page: 1 });
      }
    },
  },
  i18n: {
    searchInputPlaceholder: s__('Dependencies|Search or filter dependencies…'),
  },
};
</script>

<template>
  <gl-filtered-search
    :id="filteredSearchId"
    :value="value"
    :placeholder="$options.i18n.searchInputPlaceholder"
    :available-tokens="availableTokens"
    terms-as-tokens
    @input="setSearchFilterParameters"
    @submit="fetchDependenciesWithFeatureFlag"
  />
</template>
