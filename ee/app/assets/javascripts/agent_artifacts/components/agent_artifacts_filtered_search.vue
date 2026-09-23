<script>
import { GlFilteredSearch } from '@gitlab/ui';
import {
  OPERATORS_IS,
  OPERATORS_IS_NOT,
} from '~/vue_shared/components/filtered_search_bar/constants';
import { queryToObject } from '~/lib/utils/url_utility';
import { s__ } from '~/locale';
import DateToken from '~/vue_shared/components/filtered_search_bar/tokens/date_token.vue';
import ProjectToken from './tokens/project_token.vue';
import TriggeredByToken from './tokens/triggered_by_token.vue';

// Filter types that can be pre-set from the URL, deep-linked from the dashboard
// Developer activity (triggeredByUserId) and Project exposure (projectPath)
// cards. Kept intentionally narrow to just these two.
const URL_FILTER_TYPES = ['triggeredByUserId', 'projectPath'];

export default {
  name: 'AgentArtifactsFilteredSearch',
  components: {
    GlFilteredSearch,
  },
  inject: {
    groupId: { default: null },
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  emits: ['filter'],
  data() {
    return {
      filterValue: [],
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    tokens() {
      return [
        {
          type: 'startTimeAfter',
          icon: 'calendar',
          title: s__('AgentArtifacts|Created after'),
          token: DateToken,
          unique: true,
          operators: OPERATORS_IS,
        },
        {
          type: 'startTimeBefore',
          icon: 'calendar',
          title: s__('AgentArtifacts|Created before'),
          token: DateToken,
          unique: true,
          operators: OPERATORS_IS,
        },
        !this.isProjectMode &&
          this.groupId && {
            type: 'projectPath',
            icon: 'project',
            title: s__('AgentArtifacts|Project'),
            token: ProjectToken,
            unique: true,
            operators: OPERATORS_IS_NOT,
          },
        {
          type: 'triggeredByUserId',
          icon: 'user',
          title: s__('AgentArtifacts|Triggered by'),
          token: TriggeredByToken,
          unique: true,
          operators: OPERATORS_IS_NOT,
          fullPath: this.projectFullPath || this.groupFullPath,
          isProject: this.isProjectMode,
          valueField: 'id',
          defaultUsers: [],
        },
      ].filter(Boolean);
    },
  },
  created() {
    // Seed the filter from URL params so deep links (e.g. from the dashboard
    // cards) open the report with the filter already applied. Only seed types
    // that exist as a token in the current mode (projectPath has no token in
    // project mode), so we never create an orphan filter chip.
    const params = queryToObject(window.location.search);
    const availableTypes = new Set(this.tokens.map((token) => token.type));
    const seeded = URL_FILTER_TYPES.filter((type) => params[type] && availableTypes.has(type)).map(
      (type) => ({
        type,
        value: { data: params[type], operator: '=' },
      }),
    );

    if (!seeded.length) return;

    this.filterValue = seeded;
    // Emit after the initial render so the sibling table is mounted and applies
    // the filter; emitting during created() runs before the table can react, so
    // the results would not update.
    this.$nextTick(() => this.handleSubmit());
  },
  methods: {
    handleSubmit() {
      const variables = {};
      const notFilters = {};

      this.filterValue.forEach((filter) => {
        if (!filter.value?.data) return;

        const { data, operator } = filter.value;
        const { type } = filter;

        if (operator === '=') {
          variables[type] = data;
        } else if (operator === '!=') {
          notFilters[type] = data;
        }
      });

      if (Object.keys(notFilters).length > 0) {
        variables.not = notFilters;
      }

      this.$emit('filter', variables);
    },
  },
};
</script>

<template>
  <gl-filtered-search
    v-model="filterValue"
    :placeholder="s__('AgentArtifacts|Filter agent artifacts')"
    :available-tokens="tokens"
    terms-as-tokens
    @submit="handleSubmit"
    @clear="$emit('filter', {})"
  />
</template>
