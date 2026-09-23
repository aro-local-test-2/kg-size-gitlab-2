<script>
import { nextTick } from 'vue';
import { GlFilteredSearch } from '@gitlab/ui';
import { isEqual } from 'lodash-es';
import { OPERATOR_NOT } from '~/vue_shared/components/filtered_search_bar/constants';
import { ALL_ID, TRACKED_REF_TYPE } from './constants';

export default {
  name: 'FilteredSearch',
  components: {
    GlFilteredSearch,
  },
  inject: {
    defaultBranchContext: {
      default: () => null,
    },
    dashboardType: {
      default: '',
    },
  },
  props: {
    tokens: {
      type: Array,
      required: true,
    },
  },
  emits: ['filters-changed', 'url-params-changed'],
  data() {
    return {
      value: [],
      // Temporary until https://gitlab.com/gitlab-org/gitlab/-/issues/612168
      appliedTrackedRefs: [],
    };
  },
  computed: {
    filteredValue() {
      return this.value.filter(({ type }) => this.tokens.some((token) => token.type === type));
    },
    context() {
      return {
        defaultBranchContext: this.defaultBranchContext,
        dashboardType: this.dashboardType,
      };
    },
    // Temporary until https://gitlab.com/gitlab-org/gitlab/-/issues/612168: the malware token
    // reads the last applied refs from its config, because a sibling's live value is nulled
    // while that sibling is being edited.
    availableTokens() {
      return this.tokens.map((token) =>
        token.type === 'malware'
          ? { ...token, appliedTrackedRefs: this.appliedTrackedRefs }
          : token,
      );
    },
  },
  created() {
    this.value = this.tokens.map(this.buildInitialValue).filter(({ value }) => value.data?.length);

    this.updateUrlParams();
    this.emitFilters();
  },
  methods: {
    buildInitialValue(token) {
      const params = new URLSearchParams(window.location.search);
      const parse = (key) => params.get(key)?.split(',').filter(Boolean);

      const includeValues = parse(token.type);
      const excludeValues = parse(`not[${token.type}]`);

      let urlValues;
      if (includeValues) {
        urlValues = includeValues;
      } else if (excludeValues) {
        urlValues = excludeValues;
      }

      let data;
      if (urlValues) {
        data = token.token?.parseQueryParams?.(urlValues, token) ?? urlValues;
      } else {
        data = this.getDefaultValues(token);
      }

      return {
        type: token.type,
        value: {
          data,
          operator: excludeValues && !includeValues ? OPERATOR_NOT : token.operators[0].value,
        },
      };
    },
    getDefaultValues(tokenDef) {
      return tokenDef.token?.defaultValues?.({ ...this.context, config: tokenDef }) ?? [];
    },
    getSelectedValue(type) {
      const token = this.value.find((t) => t.type === type);
      return token?.value || {};
    },
    getTokenDefinition(type) {
      return this.tokens.find((token) => token.type === type);
    },
    getTokenComponent(type) {
      return this.getTokenDefinition(type)?.token;
    },
    transformFilters(type, { data, operator }, filters) {
      const token = this.getTokenComponent(type);
      // GlFilteredSearch nulls a token's data while it is being edited; a sibling token's
      // destroy can trigger an update in that state. Treat it as an empty selection.
      const values = data ?? [];
      if (token?.transformFilters) {
        return token.transformFilters(values, { filters, operator, ...this.context });
      }
      return {
        [type]: Array.isArray(values) ? values.filter((i) => i !== ALL_ID) : values,
      };
    },
    transformQueryParams(type, data) {
      const tokenDef = this.getTokenDefinition(type);
      const component = tokenDef?.token;
      // Data is null while the token is being edited and undefined when it was destroyed.
      const values = data ?? [];
      if (isEqual(values, this.getDefaultValues(tokenDef))) return undefined;

      if (component?.transformQueryParams) {
        return component.transformQueryParams(values, tokenDef);
      }
      return Array.isArray(values) ? values.join(',') : values;
    },
    // Temporary until https://gitlab.com/gitlab-org/gitlab/-/issues/612168: the token drops
    // itself a pass later, so this pass must not emit or persist malware next to a ref it
    // cannot apply to.
    malwareFilterIsOutOfScope() {
      const refs =
        this.filteredValue.find(({ type }) => type === TRACKED_REF_TYPE)?.value.data ?? [];

      return !refs.every((ref) => ref !== ALL_ID && ref.id === this.defaultBranchContext?.id);
    },
    emitFilters() {
      const filters = {};
      for (const { type, value } of this.filteredValue) {
        if (type === 'malware' && this.malwareFilterIsOutOfScope()) continue;

        Object.assign(filters, this.transformFilters(type, value, filters));
      }

      this.appliedTrackedRefs =
        this.filteredValue.find(({ type }) => type === TRACKED_REF_TYPE)?.value.data ?? [];
      this.$emit('filters-changed', filters);
    },
    updateUrlParams() {
      const params = {};

      for (const { type } of this.tokens) {
        const { data, operator } = this.getSelectedValue(type);
        const value =
          type === 'malware' && this.malwareFilterIsOutOfScope()
            ? undefined
            : this.transformQueryParams(type, data);

        params[type] = undefined;
        params[`not[${type}]`] = undefined;

        // "!=" uses the negation key (e.g. "not[severity]"), everything else
        // uses the standard key (e.g. "severity").
        if (operator === OPERATOR_NOT) {
          params[`not[${type}]`] = value;
        } else {
          params[type] = value;
        }
      }

      this.$emit('url-params-changed', params);
    },
    async update() {
      // Two nextTicks are needed because in Vue 3 compat mode, v-model updates
      // propagate asynchronously and a single nextTick is not sufficient for
      // this.value to reflect the latest state after token-complete/token-destroy events.
      await nextTick();
      await nextTick();
      this.updateUrlParams();
      this.emitFilters();
    },
  },
};
</script>
<template>
  <gl-filtered-search
    v-model="value"
    :placeholder="s__('SecurityReports|Filter results...')"
    :available-tokens="availableTokens"
    @token-complete="update"
    @token-destroy="update"
    @clear="update"
  />
</template>
