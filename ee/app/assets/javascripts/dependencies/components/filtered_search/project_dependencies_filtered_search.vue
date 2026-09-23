<script>
import { __ } from '~/locale';
import {
  OPERATORS_IS,
  OPERATORS_IS_NOT,
  OPERATORS_OR,
} from '~/vue_shared/components/filtered_search_bar/constants';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import MalwareToken from 'ee/security_dashboard/components/shared/filtered_search/tokens/malware_token.vue';
import TrackedRefToken from 'ee/security_dashboard/components/shared/filtered_search/tokens/tracked_ref_token.vue';
import DependenciesFilteredSearch from './dependencies_filtered_search.vue';
import ComponentToken from './tokens/component_token.vue';
import ActivityToken from './tokens/activity_token.vue';
import VersionToken from './tokens/version_token.vue';
import { isTrackedRefFilterEnabled, buildDefaultTrackedRefFilter } from './utils';

const TRACKED_REF_TYPE = 'trackedRefIds';

export default {
  name: 'ProjectDependenciesFilteredSearch',
  components: {
    DependenciesFilteredSearch,
  },
  mixins: [glFeatureFlagsMixin(), glAbilitiesMixin()],
  inject: {
    projectFullPath: {
      default: '',
    },
    defaultBranchContext: {
      default: () => null,
    },
  },
  computed: {
    hasTrackedRefFilter() {
      return isTrackedRefFilterEnabled({
        glFeatures: this.glFeatures,
        projectFullPath: this.projectFullPath,
        defaultBranchContext: this.defaultBranchContext,
      });
    },
    tokens() {
      const tokens = [
        {
          type: 'component_names',
          title: __('Component'),
          multiSelect: true,
          unique: true,
          token: ComponentToken,
          operators: OPERATORS_IS,
        },
        {
          type: 'component_versions',
          title: __('Version'),
          multiSelect: true,
          unique: true,
          token: VersionToken,
          operators: OPERATORS_IS_NOT,
        },
        {
          type: 'component_activity',
          title: __('Activity'),
          multiSelect: false,
          unique: true,
          token: ActivityToken,
          operators: OPERATORS_IS,
        },
      ];

      if (
        this.glFeatures.dependencyMalwareDetection &&
        this.glFeatures.maliciousPackagesDependencyListFiltering &&
        this.glAbilities.readAdvancedDependencyManagement
      ) {
        tokens.push({
          type: 'malware',
          // we show the extra text that says "Only on default branch" if the tracked ref filter is enabled
          // Temporary until https://gitlab.com/gitlab-org/gitlab/-/issues/612168
          title: this.hasTrackedRefFilter
            ? MalwareToken.i18n.defaultBranchOnlyLabel
            : MalwareToken.i18n.label,
          multiSelect: false,
          unique: true,
          token: MalwareToken,
          operators: OPERATORS_IS,
        });
      }

      if (this.hasTrackedRefFilter) {
        tokens.push({
          type: TRACKED_REF_TYPE,
          title: TrackedRefToken.i18n.label,
          multiSelect: true,
          unique: true,
          token: TrackedRefToken,
          operators: OPERATORS_OR,
        });
      }

      return tokens;
    },
    initialFilterValue() {
      if (!this.hasTrackedRefFilter) {
        return [];
      }

      return buildDefaultTrackedRefFilter(this.defaultBranchContext);
    },
  },
};
</script>

<template>
  <dependencies-filtered-search
    :tokens="tokens"
    :value="initialFilterValue"
    filtered-search-id="project-level-filtered-search"
  />
</template>
